import Atomics
import Foundation
import SwiftUI
import Zip
import os

// MARK: - WhisperModelFile

struct WhisperModelFile: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var coreMLEncoderURL: URL?  // Path to the unzipped .mlmodelc directory
    var isCoreMLDownloaded: Bool { coreMLEncoderURL != nil }

    var downloadURL: String {
        WhisperModelArtifactCatalog.artifact(for: name)?.modelFile.downloadURL.absoluteString ?? ""
    }

    var filename: String {
        "\(name).bin"
    }

    // Core ML related properties
    var coreMLZipDownloadURL: String? {
        WhisperModelArtifactCatalog.artifact(for: name)?.coreMLArchive?.downloadURL.absoluteString
    }

    var coreMLEncoderDirectoryName: String? {
        guard coreMLZipDownloadURL != nil else { return nil }
        return "\(name)-encoder.mlmodelc"
    }
}

private enum WhisperDownloadError: Error {
    case invalidArtifact
    case oversizedArtifact
    case invalidArtifactSize
    case invalidArtifactChecksum
    case invalidArchive
    case archiveLimitsExceeded
}

enum WhisperModelImportPolicy {
    static let maximumFileBytes: Int64 = 4_000_000_000
    private static let ggmlMagic = Data([0x6c, 0x6d, 0x67, 0x67])

    static func validate(_ url: URL) throws -> Int64 {
        guard url.isFileURL,
              url.pathExtension.lowercased() == "bin",
              let values = try? url.resourceValues(
                  forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              Int64(size) <= maximumFileBytes,
              url.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: ggmlMagic.count) == ggmlMagic else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Int64(size)
    }

    static func validateTrustedArtifact(named modelName: String, at url: URL) throws -> Int64 {
        guard let artifact = WhisperModelArtifactCatalog.artifact(for: modelName) else {
            throw CocoaError(.fileReadUnknown)
        }
        let size = try validate(url)
        guard artifact.modelFile.integrityIsValid(at: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return size
    }
}

private final class WhisperDownloadCancellationController: @unchecked Sendable {
    private enum State {
        case pending
        case active(URLSessionDownloadTask, NSKeyValueObservation, @Sendable () -> Void)
        case finished
        case canceled
    }

    private let lock = NSLock()
    private var state: State = .pending

    func register(
        task: URLSessionDownloadTask,
        observation: NSKeyValueObservation,
        onCancel: @escaping @Sendable () -> Void
    ) -> Bool {
        lock.lock()
        let currentState = state
        switch currentState {
        case .pending:
            state = .active(task, observation, onCancel)
            lock.unlock()
            return true
        case .canceled:
            lock.unlock()
            task.cancel()
            observation.invalidate()
            onCancel()
            return false
        case .finished:
            lock.unlock()
            observation.invalidate()
            return false
        case .active:
            lock.unlock()
            task.cancel()
            observation.invalidate()
            onCancel()
            return false
        }
    }

    func finish() {
        lock.lock()
        let currentState = state
        state = .finished
        lock.unlock()
        if case .active(_, let observation, _) = currentState {
            observation.invalidate()
        }
    }

    func cancel() {
        lock.lock()
        let currentState = state
        guard case .finished = currentState else {
            state = .canceled
            lock.unlock()
            if case .active(let task, let observation, let onCancel) = currentState {
                task.cancel()
                observation.invalidate()
                onCancel()
            }
            return
        }
        lock.unlock()
    }
}

// MARK: - WhisperModelManager

@MainActor
class WhisperModelManager: ObservableObject {
    @Published var availableModels: [WhisperModelFile] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var whisperContext: WhisperContext?
    @Published var isModelLoaded = false
    @Published var loadedWhisperModel: WhisperModelFile?
    @Published var isModelLoading = false

    let modelsDirectory: URL
    let whisperPrompt = WhisperPrompt()

    /// Called when a model is deleted, passing the model name.
    /// TranscriptionModelManager listens to clear currentTranscriptionModel if needed.
    var onModelDeleted: ((String) -> Void)?

    /// Called after a new model is added (downloaded or imported) so
    /// TranscriptionModelManager can rebuild allAvailableModels.
    var onModelsChanged: (() -> Void)?

    let logger = Logger(subsystem: "com.jackie-yeh.wagong", category: "WhisperModelManager")

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    // MARK: - Model Directory Management

    func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(
                at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logError("Error creating models directory", error)
        }
    }

    func loadAvailableModels() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: modelsDirectory, includingPropertiesForKeys: nil)
            availableModels = fileURLs.compactMap { url in
                guard url.pathExtension == "bin" else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                guard WhisperModelArtifactCatalog.artifact(for: name) != nil else { return nil }
                return WhisperModelFile(name: name, url: url)
            }
        } catch {
            logError("Error loading available models", error)
        }
    }

    // MARK: - Model Loading

    func loadModel(_ model: WhisperModelFile) async throws {
        guard whisperContext == nil else { return }

        isModelLoading = true
        defer { isModelLoading = false }

        do {
            guard WhisperModelArtifactCatalog.artifact(for: model.name) != nil else {
                throw WhisperDownloadError.invalidArtifact
            }
            let modelURL = model.url
            let isValid = await Task.detached(priority: .utility) {
                (try? WhisperModelImportPolicy.validateTrustedArtifact(named: model.name, at: modelURL)) != nil
            }.value
            try Task.checkCancellation()
            guard isValid else { throw WhisperDownloadError.invalidArtifactChecksum }
            whisperContext = try await WhisperContext.createContext(path: model.url.path)

            let currentPrompt =
                UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? whisperPrompt.transcriptionPrompt
            await whisperContext?.setPrompt(currentPrompt)

            isModelLoaded = true
            loadedWhisperModel = model
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WaGongEngineError.modelLoadFailed
        }
    }

    // MARK: - Model Download & Management

    private func downloadFileWithProgress(
        from artifact: WhisperRemoteArtifact,
        progressKey: String
    ) async throws -> Data {
        let destinationURL = modelsDirectory.appendingPathComponent(UUID().uuidString)
        let cancellation = WhisperDownloadCancellationController()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let finished = ManagedAtomic(false)

                func finishOnce(_ result: Result<Data, Error>) {
                    if finished.exchange(true, ordering: .acquiring) == false {
                        cancellation.finish()
                        continuation.resume(with: result)
                    }
                }

                let task = URLSession.shared.downloadTask(with: artifact.downloadURL) { tempURL, response, error in
                    if let error = error {
                        finishOnce(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode),
                        let tempURL = tempURL
                    else {
                        finishOnce(.failure(URLError(.badServerResponse)))
                        return
                    }

                    do {
                        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                        guard Self.regularFileSize(at: destinationURL) == artifact.size else {
                            throw WhisperDownloadError.invalidArtifactSize
                        }
                        guard artifact.integrityIsValid(at: destinationURL) else {
                            throw WhisperDownloadError.invalidArtifactChecksum
                        }
                        let data = try Data(contentsOf: destinationURL, options: .mappedIfSafe)
                        try FileManager.default.removeItem(at: destinationURL)
                        finishOnce(.success(data))
                    } catch {
                        try? FileManager.default.removeItem(at: destinationURL)
                        finishOnce(.failure(error))
                    }
                }

                var lastUpdateTime = Date()
                var lastProgressValue: Double = 0

                let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                    if progress.completedUnitCount > artifact.size {
                        task.cancel()
                        try? FileManager.default.removeItem(at: destinationURL)
                        finishOnce(.failure(WhisperDownloadError.oversizedArtifact))
                        return
                    }
                    let currentTime = Date()
                    let timeSinceLastUpdate = currentTime.timeIntervalSince(lastUpdateTime)
                    let currentProgress = round(progress.fractionCompleted * 100) / 100

                    if timeSinceLastUpdate >= 0.5 && abs(currentProgress - lastProgressValue) >= 0.01 {
                        lastUpdateTime = currentTime
                        lastProgressValue = currentProgress

                        DispatchQueue.main.async {
                            self.downloadProgress[progressKey] = currentProgress
                        }
                    }
                }

                let shouldResume = cancellation.register(
                    task: task,
                    observation: observation,
                    onCancel: {
                        try? FileManager.default.removeItem(at: destinationURL)
                        finishOnce(.failure(CancellationError()))
                    }
                )
                if shouldResume {
                    task.resume()
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func downloadModel(_ model: WhisperModel) async {
        guard let artifact = WhisperModelArtifactCatalog.artifact(for: model.name) else {
            handleModelDownloadError(model, WhisperDownloadError.invalidArtifact)
            return
        }
        await performModelDownload(model, artifact)
    }

    private func performModelDownload(_ model: WhisperModel, _ artifact: WhisperModelArtifact) async {
        do {
            var whisperModel = try await downloadMainModel(model, artifact: artifact)

            if let coreMLArtifact = artifact.coreMLArchive {
                whisperModel = try await downloadAndSetupCoreMLModel(for: whisperModel, artifact: coreMLArtifact)
            }

            availableModels.append(whisperModel)
            self.downloadProgress.removeValue(forKey: model.name + "_main")

            onModelsChanged?()

            if shouldWarmup(model) {
                WhisperModelWarmupCoordinator.shared.scheduleWarmup(for: model, whisperModelManager: self)
            }
        } catch {
            handleModelDownloadError(model, error)
        }
    }

    private func downloadMainModel(_ model: WhisperModel, artifact: WhisperModelArtifact) async throws
        -> WhisperModelFile
    {
        let progressKeyMain = model.name + "_main"
        let data = try await downloadFileWithProgress(from: artifact.modelFile, progressKey: progressKeyMain)

        let destinationURL = modelsDirectory.appendingPathComponent(model.filename)
        try data.write(to: destinationURL)

        return WhisperModelFile(name: model.name, url: destinationURL)
    }

    private func downloadAndSetupCoreMLModel(for model: WhisperModelFile, artifact: WhisperRemoteArtifact) async throws
        -> WhisperModelFile
    {
        let progressKeyCoreML = model.name + "_coreml"
        let coreMLData = try await downloadFileWithProgress(from: artifact, progressKey: progressKeyCoreML)

        let coreMLZipPath = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc.zip")
        try coreMLData.write(to: coreMLZipPath)

        return try await unzipAndSetupCoreMLModel(
            for: model,
            artifact: artifact,
            zipPath: coreMLZipPath,
            progressKey: progressKeyCoreML
        )
    }

    private func unzipAndSetupCoreMLModel(
        for model: WhisperModelFile,
        artifact: WhisperRemoteArtifact,
        zipPath: URL,
        progressKey: String
    ) async throws
        -> WhisperModelFile
    {
        let coreMLDestination = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc")
        let stagingDirectory = modelsDirectory.appendingPathComponent(".coreml-staging-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        try await unzipCoreMLFile(zipPath, to: stagingDirectory)
        try Self.validateExtractedArchive(
            at: stagingDirectory,
            maximumEntryCount: 4_096,
            maximumExpandedBytes: artifact.size * 8
        )
        let stagedModel = stagingDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc")
        guard FileManager.default.fileExists(atPath: stagedModel.path) else {
            throw WhisperDownloadError.invalidArchive
        }
        try? FileManager.default.removeItem(at: coreMLDestination)
        try FileManager.default.moveItem(at: stagedModel, to: coreMLDestination)
        return try verifyAndCleanupCoreMLFiles(model, coreMLDestination, zipPath, progressKey)
    }

    private func unzipCoreMLFile(_ zipPath: URL, to destination: URL) async throws {
        let finished = ManagedAtomic(false)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            func finishOnce(_ result: Result<Void, Error>) {
                if finished.exchange(true, ordering: .acquiring) == false {
                    continuation.resume(with: result)
                }
            }

            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Zip.unzipFile(zipPath, destination: destination, overwrite: true, password: nil)
                finishOnce(.success(()))
            } catch {
                finishOnce(.failure(error))
            }
        }
    }

    private func verifyAndCleanupCoreMLFiles(
        _ model: WhisperModelFile, _ destination: URL, _ zipPath: URL, _ progressKey: String
    ) throws -> WhisperModelFile {
        var model = model

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            try? FileManager.default.removeItem(at: zipPath)
            throw WaGongEngineError.unzipFailed
        }

        try? FileManager.default.removeItem(at: zipPath)
        model.coreMLEncoderURL = destination
        self.downloadProgress.removeValue(forKey: progressKey)

        return model
    }

    private func shouldWarmup(_ model: WhisperModel) -> Bool {
        !model.name.contains("q5") && !model.name.contains("q8")
    }

    private func handleModelDownloadError(_ model: WhisperModel, _ error: Error) {
        self.downloadProgress.removeValue(forKey: model.name + "_main")
        self.downloadProgress.removeValue(forKey: model.name + "_coreml")
    }

    private nonisolated static func regularFileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return -1 }
        return Int64(values?.fileSize ?? -1)
    }

    nonisolated static func validateExtractedArchive(
        at root: URL,
        maximumEntryCount: Int,
        maximumExpandedBytes: Int64
    ) throws {
        let rootPath = root.standardizedFileURL.path
        guard maximumEntryCount > 0, maximumExpandedBytes >= 0,
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: []
            )
        else {
            throw WhisperDownloadError.invalidArchive
        }

        var entryCount = 0
        var expandedBytes: Int64 = 0
        for case let entryURL as URL in enumerator {
            entryCount += 1
            guard entryCount <= maximumEntryCount else {
                throw WhisperDownloadError.archiveLimitsExceeded
            }

            let standardizedPath = entryURL.standardizedFileURL.path
            guard standardizedPath.hasPrefix(rootPath + "/") else {
                throw WhisperDownloadError.invalidArchive
            }
            let values = try entryURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true,
                values.isDirectory == true || values.isRegularFile == true
            else {
                throw WhisperDownloadError.invalidArchive
            }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                let (nextBytes, overflow) = expandedBytes.addingReportingOverflow(size)
                guard !overflow, nextBytes <= maximumExpandedBytes else {
                    throw WhisperDownloadError.archiveLimitsExceeded
                }
                expandedBytes = nextBytes
            }
        }
    }

    func deleteModel(_ model: WhisperModelFile) async {
        do {
            try FileManager.default.removeItem(at: model.url)

            if let coreMLURL = model.coreMLEncoderURL {
                try? FileManager.default.removeItem(at: coreMLURL)
            } else {
                let coreMLDir = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc")
                if FileManager.default.fileExists(atPath: coreMLDir.path) {
                    try? FileManager.default.removeItem(at: coreMLDir)
                }
            }

            availableModels.removeAll { $0.id == model.id }

            // Notify TranscriptionModelManager to clear currentTranscriptionModel if it matches
            onModelDeleted?(model.name)
        } catch {
            logError("Error deleting model: \(model.name)", error)
        }
    }

    func unloadModel() {
        Task {
            await whisperContext?.releaseResources()
            whisperContext = nil
            isModelLoaded = false
        }
    }

    func clearDownloadedModels() async {
        for model in availableModels {
            do {
                try FileManager.default.removeItem(at: model.url)
            } catch {
                logError("Error deleting model during cleanup", error)
            }
        }
        availableModels.removeAll()
    }

    // MARK: - Resource Management

    /// Releases the WhisperContext and resets model-loaded state.
    /// Does NOT call serviceRegistry.cleanup() — that is WaGongEngine's responsibility.
    func cleanupResources() async {
        logger.notice("WhisperModelManager.cleanupResources: releasing whisper context")
        await whisperContext?.releaseResources()
        whisperContext = nil
        isModelLoaded = false
        logger.notice("WhisperModelManager.cleanupResources: completed")
    }

    // MARK: - Import Local Model

    func importWhisperModel(from sourceURL: URL) async {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL = modelsDirectory.appendingPathComponent("\(baseName).bin")
        let stagingURL = modelsDirectory.appendingPathComponent(".import-\(UUID().uuidString).bin")
        var didCreateDestination = false

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            await NotificationManager.shared.showNotification(
                title: String(format: String(localized: "A model named %@.bin already exists"), baseName),
                type: .warning,
                duration: 4.0
            )
            return
        }

        do {
            let sourceSize = try WhisperModelImportPolicy.validateTrustedArtifact(named: baseName, at: sourceURL)
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
            let stagedSize = try WhisperModelImportPolicy.validateTrustedArtifact(named: baseName, at: stagingURL)
            guard stagedSize == sourceSize else { throw CocoaError(.fileReadCorruptFile) }
            try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
            didCreateDestination = true
            guard try WhisperModelImportPolicy.validateTrustedArtifact(named: baseName, at: destinationURL) == sourceSize else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let newWhisperModel = WhisperModelFile(name: baseName, url: destinationURL)
            availableModels.append(newWhisperModel)

            onModelsChanged?()

            await NotificationManager.shared.showNotification(
                title: String(format: String(localized: "Imported %@"), destinationURL.lastPathComponent),
                type: .success,
                duration: 3.0
            )
        } catch {
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                do {
                    try FileManager.default.removeItem(at: stagingURL)
                } catch {
                    logger.error("Failed to remove an incomplete imported model")
                }
            }
            if didCreateDestination {
                do {
                    try FileManager.default.removeItem(at: destinationURL)
                } catch {
                    logger.error("Failed to remove an invalid imported model")
                }
            }
            logError("Failed to import local model", error)
            await NotificationManager.shared.showNotification(
                title: String(format: String(localized: "Failed to import model: %@"), error.localizedDescription),
                type: .error,
                duration: 5.0
            )
        }
    }

    // MARK: - Helpers

    private func logError(_ message: String, _ error: Error) {
        logger.error("❌ \(message, privacy: .public): \(error, privacy: .public)")
    }
}

// MARK: - WhisperModelProvider

extension WhisperModelManager: WhisperModelProvider {}

// MARK: - Download Progress View

struct DownloadProgressView: View {
    let modelName: String
    let downloadProgress: [String: Double]
    var isOptimizing = false

    @Environment(\.colorScheme) private var colorScheme

    private var mainProgress: Double {
        downloadProgress[modelName + "_main"] ?? 0
    }

    private var coreMLProgress: Double {
        supportsCoreML ? (downloadProgress[modelName + "_coreml"] ?? 0) : 0
    }

    private var supportsCoreML: Bool {
        !modelName.contains("q5") && !modelName.contains("q8")
    }

    private var totalProgress: Double {
        if isOptimizing {
            return 1
        }

        return supportsCoreML ? (mainProgress * 0.5) + (coreMLProgress * 0.5) : mainProgress
    }

    private var downloadPhase: String {
        if isOptimizing {
            return String(localized: "Optimizing model for your device")
        }

        if supportsCoreML && downloadProgress[modelName + "_coreml"] != nil {
            return String(format: String(localized: "Downloading Core ML Model for %@"), modelName)
        }
        return String(format: String(localized: "Downloading %@ Model"), modelName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(downloadPhase)
                    .lineLimit(1)

                Spacer()

                Text(totalProgress, format: .percent.precision(.fractionLength(0)))
                    .fontDesign(.monospaced)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color(.secondaryLabelColor))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.Border.control.opacity(0.3))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.Accent.primary)
                        .frame(width: max(0, min(geometry.size.width * totalProgress, geometry.size.width)), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
        .animation(.smooth, value: totalProgress)
    }
}
