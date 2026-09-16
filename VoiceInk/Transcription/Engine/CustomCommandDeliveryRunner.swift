import Darwin
import Foundation
import os

struct CustomCommandDeliveryContext {
    let transcript: String

    var standardInput: String {
        transcript
    }

    var environment: [String: String] {
        [
            "WAGONG_TRANSCRIPT": transcript,
            // Keep the previous variable available for existing user-authored commands.
            "VOICEINK_TRANSCRIPT": transcript
        ]
    }
}

struct CustomCommandDeliveryResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum CustomCommandDeliveryError: Error, LocalizedError {
    case commandNotConfigured
    case noTextToDeliver
    case launchFailed(String)
    case timeout(seconds: Double)
    case nonZeroExit(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .commandNotConfigured:
            return String(localized: "Custom command is empty.")
        case .noTextToDeliver:
            return String(localized: "No transcription text was available for the custom command.")
        case .launchFailed(let message):
            return String(format: String(localized: "Custom command could not start: %@"), message)
        case .timeout(let seconds):
            return String(format: String(localized: "Custom command timed out after %.0f seconds."), seconds)
        case .nonZeroExit(let status, let stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return String(format: String(localized: "Custom command exited with status %d."), status)
            }
            return String(
                format: String(localized: "Custom command exited with status %d: %@"), status,
                String(details.prefix(300)))
        }
    }
}

enum CustomCommandDeliveryRunner {
    private static let logger = Logger(
        subsystem: "com.jackie-yeh.wagong", category: "CustomCommandDeliveryRunner")

    static func run(
        command: String,
        timeout: TimeInterval,
        context: CustomCommandDeliveryContext
    ) async throws -> CustomCommandDeliveryResult {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            throw CustomCommandDeliveryError.commandNotConfigured
        }

        try Task.checkCancellation()
        let cancellation = ProcessCancellationController()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    execute(
                        command: trimmedCommand,
                        timeout: timeout,
                        context: context,
                        cancellation: cancellation,
                        continuation: continuation
                    )
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func execute(
        command: String,
        timeout: TimeInterval,
        context: CustomCommandDeliveryContext,
        cancellation: ProcessCancellationController,
        continuation: CheckedContinuation<CustomCommandDeliveryResult, Error>
    ) {
        var commandEnvironment = context.environment
        commandEnvironment["WAGONG_APPROVED_COMMAND"] = command
        let environment = ShellCommandEnvironment.commandEnvironment(
            additionalEnvironment: commandEnvironment
        )

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        let outputCollector = PipeOutputCollector(handle: outputPipe.fileHandleForReading)
        let errorCollector = PipeOutputCollector(handle: errorPipe.fileHandleForReading)
        let outputCollectors = [outputCollector, errorCollector]
        let inputWriteGroup = DispatchGroup()
        [
            inputPipe.fileHandleForWriting.fileDescriptor,
            outputPipe.fileHandleForReading.fileDescriptor,
            errorPipe.fileHandleForReading.fileDescriptor,
        ].forEach { descriptor in
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }

        let semaphore = DispatchSemaphore(value: 0)
        let shellProgram = """
            eval "$WAGONG_APPROVED_COMMAND"
            command_status=$?
            wait
            exit $command_status
            """
        let process: ProcessGroupChild

        do {
            process = try ProcessGroupChild.spawn(
                executable: "/bin/zsh",
                arguments: ["-lc", shellProgram],
                environment: environment,
                standardInput: inputPipe.fileHandleForReading.fileDescriptor,
                standardOutput: outputPipe.fileHandleForWriting.fileDescriptor,
                standardError: errorPipe.fileHandleForWriting.fileDescriptor,
                onExit: { semaphore.signal() }
            )
            try? inputPipe.fileHandleForReading.close()
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            cancellation.register(process: process, semaphore: semaphore)
        } catch {
            try? inputPipe.fileHandleForWriting.close()
            outputCollectors.forEach { $0.stop() }
            continuation.resume(throwing: CustomCommandDeliveryError.launchFailed(error.localizedDescription))
            return
        }

        if cancellation.isCanceled {
            terminate(process, semaphore: semaphore)
            try? inputPipe.fileHandleForWriting.close()
            outputCollectors.forEach { $0.stop() }
            continuation.resume(throwing: CancellationError())
            return
        }

        let timeoutDeadline = DispatchTime.now() + timeout
        startWritingStandardInput(context.standardInput, to: inputPipe.fileHandleForWriting, group: inputWriteGroup)

        let waitResult = semaphore.wait(timeout: timeoutDeadline)
        if cancellation.isCanceled {
            terminate(process, semaphore: semaphore)
            try? inputPipe.fileHandleForWriting.close()
            _ = waitForCollectors(outputCollectors, timeout: 1)
            outputCollectors.forEach { $0.stop() }
            _ = waitForGroup(inputWriteGroup, timeout: 1)
            continuation.resume(throwing: CancellationError())
            return
        }
        if waitResult == .timedOut {
            terminate(process, semaphore: semaphore)
            try? inputPipe.fileHandleForWriting.close()
            _ = waitForCollectors(outputCollectors, timeout: 1)
            outputCollectors.forEach { $0.stop() }
            _ = waitForGroup(inputWriteGroup, timeout: 1)
            continuation.resume(throwing: CustomCommandDeliveryError.timeout(seconds: timeout))
            return
        }

        _ = waitForCollectors(outputCollectors, timeout: 2)
        outputCollectors.forEach { $0.stop() }
        _ = waitForGroup(inputWriteGroup, timeout: 1)

        let stdout = outputCollector.stringValue()
        let stderr = errorCollector.stringValue()

        guard process.terminationStatus == 0 else {
            continuation.resume(
                throwing: CustomCommandDeliveryError.nonZeroExit(
                    status: process.terminationStatus,
                    stderr: stderr
                )
            )
            return
        }

        continuation.resume(
            returning: CustomCommandDeliveryResult(
                status: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        )
    }

    private static func startWritingStandardInput(_ input: String, to handle: FileHandle, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                try? handle.close()
                group.leave()
            }

            guard let inputData = input.data(using: .utf8),
                !inputData.isEmpty
            else {
                return
            }

            do {
                try handle.write(contentsOf: inputData)
            } catch {
                // The command may exit before reading stdin; its exit status is handled separately.
            }
        }
    }

    private static func terminate(_ process: ProcessGroupChild, semaphore: DispatchSemaphore) {
        guard process.isRunning else { return }

        signalProcessGroup(process.processIdentifier, signal: SIGTERM)
        let didExitAfterTerminate = semaphore.wait(timeout: .now() + 2) == .success

        if isProcessGroupRunning(process.processIdentifier) {
            signalProcessGroup(process.processIdentifier, signal: SIGKILL)
        }

        if !didExitAfterTerminate,
            semaphore.wait(timeout: .now() + 1) == .timedOut
        {
            logger.error(
                "Custom command process \(process.processIdentifier, privacy: .public) did not exit after SIGKILL")
        }
    }

    private static func signalProcessGroup(_ processGroupID: pid_t, signal: Int32) {
        if kill(-processGroupID, signal) != 0 && errno != ESRCH {
            logger.error(
                "Failed to signal custom command process group \(processGroupID, privacy: .public): errno \(errno, privacy: .public)"
            )
        }
    }

    private static func isProcessGroupRunning(_ processGroupID: pid_t) -> Bool {
        errno = 0
        if kill(-processGroupID, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func waitForGroup(_ group: DispatchGroup, timeout: TimeInterval) -> Bool {
        group.wait(timeout: .now() + timeout) == .success
    }

    private static func waitForCollectors(_ collectors: [PipeOutputCollector], timeout: TimeInterval) -> Bool {
        let deadline = DispatchTime.now() + timeout
        return collectors.allSatisfy { $0.wait(until: deadline) }
    }

    private final class ProcessCancellationController: @unchecked Sendable {
        private let lock = NSLock()
        private var canceled = false
        private var process: ProcessGroupChild?
        private var semaphore: DispatchSemaphore?

        var isCanceled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return canceled
        }

        func register(process: ProcessGroupChild, semaphore: DispatchSemaphore) {
            lock.lock()
            self.process = process
            self.semaphore = semaphore
            let shouldCancel = canceled
            lock.unlock()

            if shouldCancel {
                Self.terminateRegistered(process: process, semaphore: semaphore)
            }
        }

        func cancel() {
            lock.lock()
            canceled = true
            let process = process
            let semaphore = semaphore
            lock.unlock()

            guard let process, let semaphore else { return }
            Self.terminateRegistered(process: process, semaphore: semaphore)
        }

        private static func terminateRegistered(process: ProcessGroupChild, semaphore: DispatchSemaphore) {
            DispatchQueue.global(qos: .userInitiated).async {
                CustomCommandDeliveryRunner.terminate(process, semaphore: semaphore)
            }
        }
    }
}

private final class ProcessGroupChild: @unchecked Sendable {
    enum SpawnError: Error {
        case initialization(Int32)
        case spawn(Int32)
    }

    let processIdentifier: pid_t
    private let lock = NSLock()
    private var rawWaitStatus: Int32?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rawWaitStatus == nil
    }

    var terminationStatus: Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard let rawWaitStatus else { return -1 }
        if (rawWaitStatus & 0x7f) == 0 {
            return (rawWaitStatus >> 8) & 0xff
        }
        return 128 + (rawWaitStatus & 0x7f)
    }

    private init(processIdentifier: pid_t, onExit: @escaping @Sendable () -> Void) {
        self.processIdentifier = processIdentifier
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var status: Int32 = 0
            while waitpid(processIdentifier, &status, 0) == -1 && errno == EINTR {}
            lock.lock()
            rawWaitStatus = status
            lock.unlock()
            onExit()
        }
    }

    static func spawn(
        executable: String,
        arguments: [String],
        environment: [String: String],
        standardInput: Int32,
        standardOutput: Int32,
        standardError: Int32,
        onExit: @escaping @Sendable () -> Void
    ) throws -> ProcessGroupChild {
        var fileActions: posix_spawn_file_actions_t? = nil
        var attributes: posix_spawnattr_t? = nil
        var result = posix_spawn_file_actions_init(&fileActions)
        guard result == 0 else { throw SpawnError.initialization(result) }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        result = posix_spawn_file_actions_adddup2(&fileActions, standardInput, STDIN_FILENO)
        guard result == 0 else { throw SpawnError.initialization(result) }
        if standardInput != STDIN_FILENO {
            result = posix_spawn_file_actions_addclose(&fileActions, standardInput)
            guard result == 0 else { throw SpawnError.initialization(result) }
        }
        result = posix_spawn_file_actions_adddup2(&fileActions, standardOutput, STDOUT_FILENO)
        guard result == 0 else { throw SpawnError.initialization(result) }
        if standardOutput != STDOUT_FILENO {
            result = posix_spawn_file_actions_addclose(&fileActions, standardOutput)
            guard result == 0 else { throw SpawnError.initialization(result) }
        }
        result = posix_spawn_file_actions_adddup2(&fileActions, standardError, STDERR_FILENO)
        guard result == 0 else { throw SpawnError.initialization(result) }
        if standardError != STDERR_FILENO {
            result = posix_spawn_file_actions_addclose(&fileActions, standardError)
            guard result == 0 else { throw SpawnError.initialization(result) }
        }

        result = posix_spawnattr_init(&attributes)
        guard result == 0 else { throw SpawnError.initialization(result) }
        defer { posix_spawnattr_destroy(&attributes) }
        result = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        guard result == 0 else { throw SpawnError.initialization(result) }
        result = posix_spawnattr_setpgroup(&attributes, 0)
        guard result == 0 else { throw SpawnError.initialization(result) }

        var argumentPointers = ([executable] + arguments).map { strdup($0) } + [nil]
        var environmentPointers = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argumentPointers {
                if let pointer { free(pointer) }
            }
            for pointer in environmentPointers {
                if let pointer { free(pointer) }
            }
        }

        var pid: pid_t = 0
        result = argumentPointers.withUnsafeMutableBufferPointer { argumentsBuffer in
            environmentPointers.withUnsafeMutableBufferPointer { environmentBuffer in
                posix_spawn(
                    &pid,
                    executable,
                    &fileActions,
                    &attributes,
                    argumentsBuffer.baseAddress!,
                    environmentBuffer.baseAddress!
                )
            }
        }
        guard result == 0 else { throw SpawnError.spawn(result) }
        return ProcessGroupChild(processIdentifier: pid, onExit: onExit)
    }
}

private final class PipeOutputCollector {
    private let handle: FileHandle
    private let buffer = LockedDataBuffer()
    private let drainTracker = PipeDrainTracker()
    private let stopLock = NSLock()
    private var stopped = false

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] handle in
            self?.readAvailableData(from: handle)
        }
    }

    func stop() {
        stopLock.lock()
        guard !stopped else {
            stopLock.unlock()
            return
        }
        stopped = true
        stopLock.unlock()

        handle.readabilityHandler = nil
        drainTracker.finish()
    }

    func wait(until deadline: DispatchTime) -> Bool {
        drainTracker.wait(until: deadline)
    }

    func stringValue() -> String {
        buffer.stringValue()
    }

    private func readAvailableData(from handle: FileHandle) {
        let data = handle.availableData
        if data.isEmpty {
            drainTracker.finish()
        } else {
            buffer.append(data)
        }
    }
}

private final class PipeDrainTracker {
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var didFinish = false

    init() {
        group.enter()
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }

        guard !didFinish else { return }
        didFinish = true
        group.leave()
    }

    func wait(until deadline: DispatchTime) -> Bool {
        group.wait(timeout: deadline) == .success
    }
}

private final class LockedDataBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func stringValue() -> String {
        lock.lock()
        let value = data
        lock.unlock()
        return String(data: value, encoding: .utf8) ?? ""
    }
}
