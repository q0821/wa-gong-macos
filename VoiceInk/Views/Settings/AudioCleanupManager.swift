import Foundation
import SwiftData
import os

/// Audio-only retention. All entry points share the same policy and execute on the model's actor.
@MainActor
final class AudioCleanupManager {
    static let shared = AudioCleanupManager()
    static let didCleanAudio = Notification.Name("WaGongAudioCleanupCompleted")
    private static var protectedPaths: [String: Int] = [:]
    private let defaults: UserDefaults
    private let recordingsDirectory: URL
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.jackie-yeh.wagong", category: "AudioCleanup")
    private var cleanupTimer: Timer?
    private var completionObserver: NSObjectProtocol?
    private var scheduledContext: ModelContext?
    private var isCleaning = false

    init(defaults: UserDefaults = .standard, recordingsDirectory: URL = AppIdentity.applicationSupportDirectoryURL.appendingPathComponent("Recordings"), now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.recordingsDirectory = recordingsDirectory.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func protect(_ url: URL) {
        protectedPaths[url.standardizedFileURL.resolvingSymlinksInPath().path, default: 0] += 1
    }

    static func release(_ url: URL) {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if let count = protectedPaths[path], count > 1 {
            protectedPaths[path] = count - 1
        } else {
            protectedPaths.removeValue(forKey: path)
        }
    }

    func startAutomaticCleanup(modelContext: ModelContext) {
        stopAutomaticCleanup()
        scheduledContext = modelContext
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let context = self.scheduledContext else { return }
                await self.runAutomaticCleanupIfNeeded(modelContext: context)
            }
        }
        completionObserver = NotificationCenter.default.addObserver(forName: .transcriptionCompleted, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let context = self.scheduledContext else { return }
                await self.runAutomaticCleanupIfNeeded(modelContext: context)
            }
        }
    }

    func stopAutomaticCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        completionObserver = nil
        scheduledContext = nil
    }

    func runAutomaticCleanupIfNeeded(modelContext: ModelContext) async {
        // A hosted test app shares production preferences; only fixture instances may clean during tests.
        if defaults === UserDefaults.standard,
           ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil { return }
        guard defaults.object(forKey: CleanupSettingsKeys.isAudioCleanupEnabled) as? Bool ?? true,
              !defaults.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled), !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false }
        let info = await getCleanupInfo(modelContext: modelContext)
        _ = await runCleanupForTranscriptions(modelContext: modelContext, transcriptions: info.transcriptions)
    }

    func runManualCleanup(modelContext: ModelContext) async {
        await runAutomaticCleanupIfNeeded(modelContext: modelContext)
    }

    private func safeAudioURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.isFileURL else { return nil }
        let standardized = url.standardizedFileURL
        guard standardized.deletingLastPathComponent() == recordingsDirectory,
              standardized.pathExtension.lowercased() == "wav",
              let values = try? standardized.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              standardized.resolvingSymlinksInPath() == standardized else { return nil }
        return standardized
    }

    private func directoryFiles() -> [(url: URL, bytes: Int64)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: recordingsDirectory,
                          includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])) ?? []
        return files.compactMap { file in
            guard let url = safeAudioURL(file.absoluteString),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
            return (url, Int64(size))
        }
    }

    func currentStorageBytes() -> Int64 {
        directoryFiles().reduce(0) { $0 + $1.bytes }
    }

    func getCleanupInfo(modelContext: ModelContext) async -> (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) {
        do {
            let items = try modelContext.fetch(FetchDescriptor<Transcription>())
            let files = directoryFiles()
            let bytesByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.url.path, $0.bytes) })
            var remainingBytes = files.reduce(Int64(0)) { $0 + $1.bytes }
            let days = max(1, defaults.object(forKey: CleanupSettingsKeys.audioRetentionPeriod) as? Int ?? 3)
            let limitMB = max(1, defaults.object(forKey: CleanupSettingsKeys.audioStorageLimitMB) as? Int ?? 300)
            let limitBytes = Int64(min(limitMB, 1_000_000)) * 1_000_000
            let cutoff = now().addingTimeInterval(-Double(days) * 86400)
            let grouped = Dictionary(grouping: items.compactMap { item -> (String, Transcription)? in
                guard let url = safeAudioURL(item.audioFileURL) else { return nil }
                return (url.path, item)
            }, by: { $0.0 })
            // The newest reference controls retention; any pending reference protects a shared file.
            let candidates = grouped.compactMap { path, references -> (String, Date, [Transcription])? in
                let records = references.map(\.1)
                guard Self.protectedPaths[path] == nil,
                      records.allSatisfy({ $0.transcriptionStatus != TranscriptionStatus.pending.rawValue }),
                      let date = records.map(\.timestamp).max() else { return nil }
                return (path, date, records)
            }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
            var selected: [Transcription] = []
            var count = 0
            var deletedBytes: Int64 = 0
            for (path, date, records) in candidates {
                guard date <= cutoff || remainingBytes > limitBytes else { continue }
                let bytes = bytesByPath[path] ?? 0
                selected += records
                count += 1
                deletedBytes += bytes
                remainingBytes -= bytes
            }
            return (count, deletedBytes, selected)
        } catch {
            logger.error("Could not inspect audio retention: \(String(describing: type(of: error)), privacy: .public)")
            return (0, 0, [])
        }
    }

    func runCleanupForTranscriptions(modelContext: ModelContext, transcriptions: [Transcription]) async -> (deletedCount: Int, errorCount: Int) {
        guard defaults.object(forKey: CleanupSettingsKeys.isAudioCleanupEnabled) as? Bool ?? true,
              !defaults.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) else { return (0, 0) }
        // Recheck after the user confirms: work may have started or settings may have changed.
        let eligible = await getCleanupInfo(modelContext: modelContext)
        let requestedIDs = Set(transcriptions.map(\.id))
        let grouped = Dictionary(grouping: eligible.transcriptions, by: { $0.audioFileURL ?? "" })
        var deleted = 0
        var errors = 0
        for (string, records) in grouped {
            guard records.contains(where: { requestedIDs.contains($0.id) }),
                  let url = safeAudioURL(string), Self.protectedPaths[url.path] == nil else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                for record in records { record.audioFileURL = nil }
                deleted += 1
            } catch { errors += 1 }
        }
        if deleted > 0 {
            do { try modelContext.save() } catch { errors += 1 }
            NotificationCenter.default.post(name: Self.didCleanAudio, object: nil)
        }
        if deleted > 0 || errors > 0 {
            logger.notice("Audio cleanup deleted=\(deleted, privacy: .public) errors=\(errors, privacy: .public)")
        }
        return (deleted, errors)
    }

    func formatFileSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
