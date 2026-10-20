import Foundation
import AVFoundation
import Darwin
@testable import VoiceInk

@main
struct RuntimeAcceptance {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let runtimeDir = root.appendingPathComponent("tools/local-model-probe/.runtime")
        let helper = URL(fileURLWithPath: "/tmp/WaGongTEA-relocated.app/Contents/MacOS/WaGongTEAWorker")
        let model = runtimeDir.appendingPathComponent("TEA-ASR-1.1-Q6_K.gguf")
        let zh = try samples(runtimeDir.appendingPathComponent("zh.wav"))
        let english = try samples(runtimeDir.appendingPathComponent("english.wav"))
        if CommandLine.arguments.contains("--timeout-only") {
            let worker = try TEAWorkerConnection(executable: helper, validateSignature: false)
            let pid = worker.processIdentifier
            do {
                _ = try await worker.exchange(.init(kind: "load", id: UUID(), generation: worker.generation,
                    modelPath: model.path), timeout: .milliseconds(1))
                throw Failure.failed
            } catch TEARuntimeError.timedOut {}
            guard worker.stop(), Darwin.kill(pid, 0) != 0, errno == ESRCH else { throw Failure.failed }
            print("Actual App timeout path rejected and reaped its helper")
            return
        }
        let manager = TEARuntimeManager(helper: helper, model: model, verifyHelperSignature: false, idleDuration: .seconds(1))
        var evidence: [String: Any] = ["signed_identity_path_tested": false, "app_not_initialized": true]
        do {
            async let a: Void = manager.prepare()
            async let b: Void = manager.prepare()
            try await (a, b)
            guard let pid = await manager.loadedProcessIdentifier else { throw Failure.failed }
            let first = try await manager.transcribe(samples: zh, language: "zh")
            let second = try await manager.transcribe(samples: english, language: "en")
            guard first.contains("不要刪除"), second.contains("API"), !second.contains("今天"),
                  await manager.loadedProcessIdentifier == pid else { throw Failure.failed }
            evidence["coalesced_prepare_and_warm_reuse"] = true
            var warm: [Double] = []
            for _ in 0..<30 {
                let began = ContinuousClock.now
                let result = try await manager.transcribe(samples: zh, language: "zh")
                guard result.contains("不要刪除"), await manager.loadedProcessIdentifier == pid else { throw Failure.failed }
                warm.append(seconds(began))
            }
            warm.sort()
            evidence["warm_30_fixed_synthetic"] = ["p50_seconds": warm[14], "p95_seconds": warm[28]]
            let signal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let running = Task {
                try await manager.transcribe(samples: zh + zh + zh, language: "zh", onNativeEntry: { signal.continuation.yield(()) })
            }
            for await _ in signal.stream { break }
            do {
                _ = try await manager.transcribe(samples: zh, language: "zh")
                throw Failure.failed
            } catch TEARuntimeError.busy { evidence["busy_rejected"] = true }
            let cancelStart = ContinuousClock.now
            running.cancel()
            do { _ = try await running.value; throw Failure.failed } catch is CancellationError {}
            signal.continuation.finish()
            guard await manager.loadedProcessIdentifier == nil, Darwin.kill(pid, 0) != 0, errno == ESRCH else { throw Failure.failed }
            evidence["native_entry_cancel_reaped"] = true
            evidence["cancel_seconds"] = seconds(cancelStart)
            try await manager.prepare()
            _ = try await manager.transcribe(samples: zh, language: "zh")
            guard let crashed = await manager.loadedProcessIdentifier else { throw Failure.failed }
            Darwin.kill(crashed, SIGKILL)
            do { _ = try await manager.transcribe(samples: zh, language: "zh"); throw Failure.failed }
            catch TEARuntimeError.failed {}
            guard await manager.loadedProcessIdentifier == nil else { throw Failure.failed }
            evidence["crash_no_automatic_replay"] = true
            try await manager.prepare()
            _ = try await manager.transcribe(samples: zh, language: "zh")
            let idlePID = await manager.loadedProcessIdentifier
            try await Task.sleep(for: .milliseconds(1300))
            guard await manager.loadedProcessIdentifier == nil, let idlePID,
                  Darwin.kill(idlePID, 0) != 0, errno == ESRCH else { throw Failure.failed }
            evidence["idle_unloaded"] = true
            do { _ = try await manager.transcribe(samples: zh, language: "fr"); throw Failure.failed }
            catch TEARuntimeError.invalidAudio { evidence["unsupported_language_rejected"] = true }
            await manager.cancel()
            evidence["cleanup_completed"] = true
            let json = try JSONSerialization.data(withJSONObject: evidence, options: .prettyPrinted)
            try json.write(to: runtimeDir.appendingPathComponent("managed-tea-app-runtime-proof.json"), options: .withoutOverwriting)
            print(String(decoding: json, as: UTF8.self))
        } catch {
            await manager.cancel()
            throw error
        }
    }
    enum Failure: Error { case failed }
    static func samples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw Failure.failed }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData?[0] else { throw Failure.failed }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }
    static func seconds(_ start: ContinuousClock.Instant) -> Double {
        let c = start.duration(to: .now).components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
