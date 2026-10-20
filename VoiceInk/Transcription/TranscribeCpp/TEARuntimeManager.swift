import Foundation
import Security
import Darwin
import CryptoKit
import os

enum TEARuntimeError: LocalizedError {
    case unavailable, modelMissing, invalidModel, invalidHelper, busy, invalidAudio, timedOut, failed, reapFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: return String(localized: "TEA requires an Apple silicon Mac.")
        case .modelMissing: return String(localized: "Download or import the TEA model first.")
        case .invalidModel: return String(localized: "TEA model verification failed. Import or download the model again.")
        case .invalidHelper: return String(localized: "The TEA component is missing or invalid. Reinstall this App version.")
        case .busy: return String(localized: "TEA is processing another recording. Please wait.")
        case .invalidAudio: return String(localized: "TEA accepts recordings up to 30 seconds in Chinese or English.")
        case .timedOut: return String(localized: "TEA timed out. Your recording was not sent to a cloud service.")
        case .failed: return String(localized: "TEA could not finish recognition. Please try again.")
        case .reapFailed: return String(localized: "TEA could not stop its recognition component. Quit the App before trying again.")
        }
    }
}

/// Owns exactly one native process. No public socket or credentials are used.
final class TEAWorkerConnection: @unchecked Sendable {
    let generation = UUID()
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lifetime = Pipe()
    private let lock = NSLock()
    private let stopLock = NSLock()
    private var operation: UUID?
    private var timedOutOperation: UUID?
    private var stopped = false
    private var reaped = false
    var processIdentifier: Int32 { process.processIdentifier }

    init(executable: URL, validateSignature: Bool = true) throws {
        let values = try executable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw TEARuntimeError.invalidHelper }
        if validateSignature { try Self.verifySignature(executable) }
        let sandbox = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        guard FileManager.default.isExecutableFile(atPath: sandbox.path) else { throw TEARuntimeError.invalidHelper }
        process.executableURL = sandbox
        process.arguments = ["-p", "(version 1) (allow default) (deny network*)", executable.path]
        process.standardInput = input
        process.standardOutput = output
        // fd 2 is deliberately a read end. Native logs never enter App logs.
        process.standardError = lifetime.fileHandleForReading
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw TEARuntimeError.failed
        }
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory()]
        try process.run()
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? lifetime.fileHandleForReading.close()
    }

    deinit { _ = stop() }

    private static func verifySignature(_ executable: URL) throws {
        let manifestURL = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/TEAWorkerManifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              manifest["version"] as? Int == TEAWorkerWire.version,
              let binary = try? Data(contentsOf: executable),
              manifest["sha256"] as? String == SHA256.hash(data: binary).map({ String(format: "%02x", $0) }).joined() else {
            throw TEARuntimeError.invalidHelper
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executable as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw TEARuntimeError.invalidHelper
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              info[kSecCodeInfoTeamIdentifier as String] as? String == "8N33V8XXTX" else {
            throw TEARuntimeError.invalidHelper
        }
    }

    func exchange(_ message: TEAWorkerWire.Message, timeout: Duration,
                  onNativeEntry: @escaping @Sendable () -> Void = {}) async throws -> TEAWorkerWire.Message {
        let id = UUID()
        guard lock.withLock({
            guard !stopped, operation == nil else { return false }
            operation = id
            return true
        }) else { throw TEARuntimeError.busy }
        let watchdog = Task.detached { [self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            let expired = lock.withLock {
                guard operation == id, !stopped else { return false }
                timedOutOperation = id
                return true
            }
            if expired { _ = stop() }
        }
        defer {
            watchdog.cancel()
            lock.withLock { if operation == id { operation = nil } }
        }
        return try await withTaskCancellationHandler {
            do {
                let response = try await Task.detached { [self] in
                    try input.fileHandleForWriting.write(contentsOf: TEAWorkerWire.encode(message))
                    while true {
                        let response = try TEAWorkerWire.read(from: output.fileHandleForReading)
                        guard response.id == message.id, response.generation == message.generation else {
                            throw TEARuntimeError.failed
                        }
                        if response.kind == "running" { onNativeEntry(); continue }
                        guard (message.kind == "load" && response.kind == "ready") ||
                              (message.kind == "transcribe" && response.kind == "result") else {
                            throw TEARuntimeError.failed
                        }
                        return response
                    }
                }.value
                try Task.checkCancellation()
                guard !lock.withLock({ stopped }) else { throw TEARuntimeError.failed }
                return response
            } catch {
                let didReap = await Task.detached { [self] in stop() }.value
                if !didReap { throw TEARuntimeError.reapFailed }
                if Task.isCancelled { throw CancellationError() }
                if lock.withLock({ timedOutOperation == id }) { throw TEARuntimeError.timedOut }
                throw TEARuntimeError.failed
            }
        } onCancel: {
            Task.detached { [self] in _ = stop() }
        }
    }

    /// Stop only our child, wait for actual exit, and refuse replacement if unreaped.
    @discardableResult func stop() -> Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        if lock.withLock({ stopped }) { return reaped }
        lock.withLock { stopped = true }
        try? lifetime.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let clock = ContinuousClock()
        let softDeadline = clock.now.advanced(by: .seconds(2))
        while process.isRunning, clock.now < softDeadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        let hardDeadline = clock.now.advanced(by: .seconds(5))
        while process.isRunning, clock.now < hardDeadline { Thread.sleep(forTimeInterval: 0.01) }
        reaped = !process.isRunning
        if reaped {
            process.waitUntilExit()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        return reaped
    }
}

actor TEARuntimeManager {
    static let shared = TEARuntimeManager()
    private var connection: TEAWorkerConnection?
    private var loading: Task<TEAWorkerConnection, Error>?
    private var stopping: Task<Bool, Never>?
    private var epoch = UUID()
    private var busy = false
    private var blocked = false
    private var idle: Task<Void, Never>?
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "TEARuntime")
    private let helperOverride: URL?
    private let modelOverride: URL?
    private let verifyHelperSignature: Bool
    private let idleDuration: Duration

    init(helper: URL? = nil, model: URL? = nil, verifyHelperSignature: Bool = true, idleDuration: Duration = .seconds(120)) {
        helperOverride = helper
        modelOverride = model
        self.verifyHelperSignature = verifyHelperSignature
        self.idleDuration = idleDuration
    }

    var loadedProcessIdentifier: Int32? { connection?.processIdentifier }

    func prepare() async throws {
        _ = try await readyConnection()
        if !busy { scheduleIdle() }
    }

    private func readyConnection() async throws -> TEAWorkerConnection {
        try Task.checkCancellation()
        guard !blocked else { throw TEARuntimeError.reapFailed }
        if let connection { return connection }
        let current = epoch
        if loading == nil {
            TEARuntimePhase.loading.publish()
            let helperOverride = self.helperOverride
            let modelOverride = self.modelOverride
            let verifyHelperSignature = self.verifyHelperSignature
            loading = Task.detached {
                #if !arch(arm64)
                throw TEARuntimeError.unavailable
                #else
                let artifact = TranscribeCppModelCatalog.tea
                let modelURL = modelOverride ?? artifact.modelFileURL
                guard FileManager.default.fileExists(atPath: modelURL.path) else { throw TEARuntimeError.modelMissing }
                let validationStart = ContinuousClock.now
                try TEAModelInstaller.validate(modelURL)
                Logger(subsystem: AppIdentity.bundleIdentifier, category: "TEARuntime").notice("TEA model verification elapsed=\(validationStart.duration(to: .now).formatted(.units(allowed: [.seconds])), privacy: .public)")
                try Task.checkCancellation()
                guard let executable = helperOverride ?? Bundle.main.executableURL?.deletingLastPathComponent()
                    .appendingPathComponent("WaGongTEAWorker") else { throw TEARuntimeError.invalidHelper }
                let worker = try TEAWorkerConnection(executable: executable, validateSignature: verifyHelperSignature)
                do {
                    let began = ContinuousClock.now
                    let ready = try await worker.exchange(.init(kind: "load", id: UUID(), generation: worker.generation,
                                                        modelPath: modelURL.path), timeout: .seconds(30))
                    guard let nativeSeconds = ready.seconds, nativeSeconds.isFinite, nativeSeconds >= 0 else { throw TEARuntimeError.failed }
                    Logger(subsystem: AppIdentity.bundleIdentifier, category: "TEARuntime").notice("TEA loaded: native_seconds=\(nativeSeconds, privacy: .public), total_load=\(began.duration(to: .now).formatted(.units(allowed: [.seconds])), privacy: .public)")
                    return worker
                } catch { _ = worker.stop(); throw error }
                #endif
            }
        }
        guard let task = loading else { throw TEARuntimeError.failed }
        do {
            let ready = try await task.value
            if Task.isCancelled {
                await cancel()
                throw CancellationError()
            }
            guard epoch == current else {
                let reaped = await Task.detached { ready.stop() }.value
                if !reaped { blocked = true }
                throw CancellationError()
            }
            connection = ready
            loading = nil
            TEARuntimePhase.ready.publish()
            return ready
        } catch {
            if epoch == current { loading = nil; TEARuntimePhase.failed.publish() }
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            if let error = error as? TEARuntimeError { throw error }
            throw TEARuntimeError.failed
        }
    }

    func transcribe(samples: [Float], language: String,
                    onNativeEntry: @escaping @Sendable () -> Void = {}) async throws -> String {
        guard !busy else { throw TEARuntimeError.busy }
        guard !samples.isEmpty, samples.count <= TEAWorkerWire.maximumSamples,
              samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }), ["auto", "zh", "en"].contains(language) else {
            throw TEARuntimeError.invalidAudio
        }
        busy = true
        idle?.cancel()
        let current = epoch
        defer { busy = false; if epoch == current { scheduleIdle() } }
        return try await withTaskCancellationHandler {
            do {
                let worker = try await readyConnection()
                try Task.checkCancellation()
                guard epoch == current else { throw CancellationError() }
                TEARuntimePhase.recognizing.publish()
                let data = samples.withUnsafeBytes { Data($0) }
                let result = try await worker.exchange(.init(kind: "transcribe", id: UUID(), generation: worker.generation,
                                                             language: language, pcm: data), timeout: .seconds(90), onNativeEntry: onNativeEntry)
                try Task.checkCancellation()
                guard epoch == current else { throw CancellationError() }
                guard let text = result.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let seconds = result.seconds, seconds.isFinite, seconds >= 0 else {
                    throw TEARuntimeError.failed
                }
                logger.notice("TEA recognition native_seconds=\(seconds, privacy: .public), samples=\(samples.count, privacy: .public)")
                TEARuntimePhase.ready.publish()
                return text
            } catch {
                await cancel()
                throw error
            }
        } onCancel: { Task { await self.cancel() } }
    }

    func cancel() async {
        if let stopping {
            _ = await stopping.value
            return
        }
        epoch = UUID()
        idle?.cancel(); idle = nil
        let task = loading
        loading = nil
        task?.cancel()
        let worker = connection
        connection = nil
        // Keep manager unavailable until previous work has actually been reaped.
        blocked = true
        let shutdown = Task.detached {
            var reaped = worker?.stop() ?? true
            if let task, let ready = try? await task.value { reaped = ready.stop() && reaped }
            return reaped
        }
        stopping = shutdown
        let reaped = await shutdown.value
        stopping = nil
        blocked = !reaped
        (reaped ? TEARuntimePhase.idle : .failed).publish()
    }

    func unloadIfIdle() async { if !busy { await cancel() } }

    private func scheduleIdle() {
        idle?.cancel()
        let current = epoch
        let duration = idleDuration
        idle = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self else { return }
            await self.expire(current)
        }
    }

    private func expire(_ expected: UUID) async { if epoch == expected, !busy { await cancel() } }
}
