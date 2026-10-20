import Foundation
import Dispatch
import Darwin
import CTranscribe

// stdin/stdout are framed requests/results. fd 2 is a separate read-only
// lifetime pipe. Native logs are disabled before any model or thread exists.
// No credential, text, audio, model path or error description is logged.
transcribe_log_set({ _, _, _ in }, nil)
signal(SIGPIPE, SIG_IGN)
DispatchQueue.global(qos: .utility).async {
    var byte: UInt8 = 0
    while true {
        let count = Darwin.read(STDERR_FILENO, &byte, 1)
        if count < 0 && errno == EINTR { continue }
        if count <= 0 { _exit(0) }
        // No messages are valid on the lifetime channel.
        _exit(1)
    }
}

func send(_ message: TEAWorkerWire.Message) throws {
    try FileHandle.standardOutput.write(contentsOf: TEAWorkerWire.encode(message))
}

final class NativeEntry {
    let message: TEAWorkerWire.Message
    init(_ message: TEAWorkerWire.Message) { self.message = message }
}

func run() throws {
    let load = try TEAWorkerWire.read(from: .standardInput)
    guard load.kind == "load", let path = load.modelPath else { throw TEAWorkerWire.Failure.invalidFrame }
    let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
          values.fileSize == 1_692_286_464 else { throw TEAWorkerWire.Failure.invalidFrame }
    let start = ContinuousClock.now
    guard transcribe_init_backends_default() == TRANSCRIBE_OK else { throw TEAWorkerWire.Failure.invalidFrame }
    var params = transcribe_model_load_params()
    transcribe_model_load_params_init(&params)
    params.backend = TRANSCRIBE_BACKEND_METAL
    var pointer: OpaquePointer?
    guard transcribe_model_load_file(path, &params, &pointer) == TRANSCRIBE_OK, let model = pointer else {
        throw TEAWorkerWire.Failure.invalidFrame
    }
    defer { transcribe_model_free(model) }
    guard String(cString: transcribe_model_arch_string(model)) == "qwen3_asr" else {
        throw TEAWorkerWire.Failure.invalidFrame
    }
    try send(.init(kind: "ready", id: load.id, generation: load.generation, seconds: elapsed(start)))
    while true {
        let request = try TEAWorkerWire.read(from: .standardInput)
        guard request.generation == load.generation else { throw TEAWorkerWire.Failure.invalidFrame }
        if request.kind == "shutdown" { return }
        guard request.kind == "transcribe", let pcm = request.pcm,
              let language = request.language, ["auto", "zh", "en"].contains(language) else {
            throw TEAWorkerWire.Failure.invalidFrame
        }
        let samples = try TEAWorkerWire.samples(from: pcm)
        var sessionParams = transcribe_session_params()
        transcribe_session_params_init(&sessionParams)
        sessionParams.n_threads = 4
        sessionParams.n_ctx = 4096
        var sessionPointer: OpaquePointer?
        guard transcribe_session_init(model, &sessionParams, &sessionPointer) == TRANSCRIBE_OK,
              let session = sessionPointer else { throw TEAWorkerWire.Failure.invalidFrame }
        // A fresh session per utterance; the model alone stays loaded.
        do {
            defer { transcribe_session_free(session) }
            let entry = NativeEntry(.init(kind: "running", id: request.id, generation: request.generation))
            transcribe_set_abort_callback(session, { raw in
                if let raw {
                    do { try send(Unmanaged<NativeEntry>.fromOpaque(raw).takeUnretainedValue().message) }
                    catch { _exit(1) }
                }
                return false
            }, Unmanaged.passUnretained(entry).toOpaque())
            var runParams = transcribe_run_params()
            transcribe_run_params_init(&runParams)
            runParams.timestamps = TRANSCRIBE_TIMESTAMPS_NONE
            let began = ContinuousClock.now
            let status = withExtendedLifetime(entry) {
                language.withCString { languagePointer in
                    runParams.language = language == "auto" ? nil : languagePointer
                    return samples.withUnsafeBufferPointer {
                        transcribe_run(session, $0.baseAddress, Int32($0.count), &runParams)
                    }
                }
            }
            guard status == TRANSCRIBE_OK, !transcribe_was_truncated(session) else {
                throw TEAWorkerWire.Failure.invalidFrame
            }
            let text = TEATranscriptDecoder.decode(String(cString: transcribe_full_text(session)))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 65_536 else {
                throw TEAWorkerWire.Failure.invalidFrame
            }
            try send(.init(kind: "result", id: request.id, generation: request.generation,
                           text: text, seconds: elapsed(began)))
        }
    }
}

func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let parts = start.duration(to: .now).components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}

do { try run() }
catch { _exit(1) }
