import Foundation
import CTranscribe

/// One request per disposable process. Audio enters stdin; text leaves stdout only.
@main
struct GGUFWorker {
    static func emit(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
    static func main() {
        do { try run() }
        catch {
            try? emit(["event": "error", "kind": "inference_failed"])
            exit(1)
        }
    }
    static func run() throws {
        let args = CommandLine.arguments
        guard args.count == 3, ["tea", "qwen"].contains(args[1]) else { throw CocoaError(.fileReadCorruptFile) }
        Transcribe.disableLogging()
        try Transcribe.initBackends()
        let model = try Model(path: args[2], options: .init(backend: .metal))
        try emit(["event": "loaded", "version": Transcribe.version(), "commit": Transcribe.versionCommit()])
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard data.count <= 3_000_000,
              let input = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let encoded = input["pcm"], let pcmData = Data(base64Encoded: encoded),
              pcmData.count > 0, pcmData.count <= 30 * 16_000 * 4, pcmData.count % 4 == 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let samples = pcmData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        guard samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else { throw CocoaError(.fileReadCorruptFile) }
        let language = input["language"] ?? "auto"
        guard ["auto", "zh", "en"].contains(language) else { throw CocoaError(.fileReadCorruptFile) }
        let session = try model.session(.init(nThreads: 4, nCtx: 4096))
        // This callback is an observable native-run entry point. Cancellation is enforced
        // by the parent terminating/reaping this process, not by pretending this SDK polls.
        transcribe_set_abort_callback(session.ptr, { _ in
            FileHandle.standardOutput.write(Data("{\"event\":\"running\"}\n".utf8))
            return false
        }, nil)
        let transcript = try session.run(samples, options: .init(timestamps: .none, language: language == "auto" ? nil : language))
        guard !session.wasTruncated else { throw CocoaError(.fileReadCorruptFile) }
        let text = args[1] == "tea" ? TEATranscriptDecoder.decode(transcript.text) : transcript.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        try emit(["event": "result", "text": text])
    }
}
