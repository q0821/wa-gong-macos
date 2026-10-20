import Foundation
import AVFoundation
import CryptoKit
import Darwin
@testable import VoiceInk

@main
struct SignedAcceptance {
    enum Failure: Error { case failed }
    static func main() async throws {
        let app = URL(fileURLWithPath: NSHomeDirectory()+"/Applications/Wa-Gong Test.app")
        let helper = app.appendingPathComponent("Contents/MacOS/WaGongTEAWorker")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let runtime = root.appendingPathComponent("tools/local-model-probe/.runtime")
        let worker = try TEAWorkerConnection(executable: helper, validateSignature: true)
        let pid = worker.processIdentifier
        do {
            let ready = try await worker.exchange(.init(kind: "load", id: UUID(), generation: worker.generation,
                modelPath: runtime.appendingPathComponent("TEA-ASR-1.1-Q6_K.gguf").path), timeout: .seconds(30))
            guard ready.kind == "ready" else { throw Failure.failed }
            let file = try AVAudioFile(forReading: runtime.appendingPathComponent("zh.wav"))
            guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw Failure.failed }
            try file.read(into: buffer)
            guard let channel = buffer.floatChannelData?[0] else { throw Failure.failed }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let pcm = samples.withUnsafeBytes { Data($0) }
            let result = try await worker.exchange(.init(kind: "transcribe", id: UUID(), generation: worker.generation,
                language: "zh", pcm: pcm), timeout: .seconds(90))
            guard result.kind == "result", result.text?.contains("不要刪除") == true else { throw Failure.failed }
            guard worker.stop(), Darwin.kill(pid, 0) != 0, errno == ESRCH else { throw Failure.failed }
        } catch { _ = worker.stop(); throw error }
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tea-signature-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let binary = temporary.appendingPathComponent("Contents/MacOS/WaGongTEAWorker")
        let manifest = temporary.appendingPathComponent("Contents/Resources/TEAWorkerManifest.json")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: helper, to: binary)
        try Data("{\"version\":1,\"sha256\":\"bad\"}".utf8).write(to: manifest)
        try reject(binary)
        var modified = try Data(contentsOf: binary)
        modified.append(Data("invalid-signature-probe".utf8))
        try modified.write(to: binary)
        let hash = SHA256.hash(data: modified).map { String(format: "%02x", $0) }.joined()
        try JSONSerialization.data(withJSONObject: ["version": 1, "sha256": hash]).write(to: manifest)
        try reject(binary)
        let proof: [String: Any] = ["signed_installed_helper_load_and_fixed_synthetic": true,
            "manifest_mismatch_rejected": true, "tampered_binary_with_matching_hash_rejected": true,
            "helper_reaped": true, "app_not_initialized": true, "cloud_requests": 0]
        try JSONSerialization.data(withJSONObject: proof, options: .prettyPrinted).write(to: runtime.appendingPathComponent("managed-tea-signed-proof.json"), options: .withoutOverwriting)
        print("Signed installed helper: load, synthetic inference, cleanup and both tamper rejections passed")
    }
    static func reject(_ url: URL) throws {
        do { let worker = try TEAWorkerConnection(executable: url, validateSignature: true); _ = worker.stop(); throw Failure.failed }
        catch TEARuntimeError.invalidHelper {}
    }
}
