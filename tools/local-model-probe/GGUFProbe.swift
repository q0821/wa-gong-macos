import Foundation
import Darwin

/// Isolated probe compiled with the exact checked-out Swift binding and native binary.
/// Input/output files are restricted by the Python driver to this task's synthetic fixtures.
@main
struct GGUFProbe {
    static func seconds(_ start: ContinuousClock.Instant) -> Double {
        let d = start.duration(to: .now).components
        return Double(d.seconds) + Double(d.attoseconds) / 1e18
    }
    static func emit(_ record: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
    static func main() {
        do {
            let status = try run()
            // Exit only after model/session ARC cleanup, never inside a live Metal scope.
            if status != 0 { exit(Int32(status)) }
        } catch {
            try? emit(["event": "failure", "type": String(describing: type(of: error))])
            exit(1)
        }
    }
    static func run() throws -> Int {
        Transcribe.disableLogging()
        try Transcribe.initBackends()
        try emit(["event": "runtime", "version": Transcribe.version(),
                  "commit": Transcribe.versionCommit(), "metal": Transcribe.backendAvailable(.metal)])
        let args = CommandLine.arguments
        guard args.count > 2 else { return 0 }
        let started = ContinuousClock.now
        let model = try Model(path: args[1], options: ModelOptions(backend: .metal))
        try emit(["event": "loaded", "seconds": seconds(started), "arch": model.arch,
                  "backend": model.backend, "initial_prompt": model.supports(.initialPrompt),
                  "cancellation": model.supports(.cancellation)])
        let specification = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [[String: Any]]
        for fixture in specification {
            let data = try Data(contentsOf: URL(fileURLWithPath: fixture["pcm"] as! String))
            let pcm = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            for iteration in 0..<2 {
                let session = try model.session(.init(nThreads: 4, nCtx: 512))
                let start = ContinuousClock.now
                let transcript = try session.run(pcm, options: RunOptions(timestamps: .none, language: fixture["language"] as? String))
                guard !session.wasTruncated, !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NSError(domain: "GGUFProbe", code: 1)
                }
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                try emit(["event": "transcript", "fixture": fixture["id"]!, "iteration": iteration,
                          "seconds": seconds(start), "audio_seconds": Double(pcm.count) / 16000,
                          "text": transcript.text, "max_rss_bytes": usage.ru_maxrss,
                          "truncated": session.wasTruncated])
            }
        }
        let fixture = specification[0]
        let data = try Data(contentsOf: URL(fileURLWithPath: fixture["pcm"] as! String))
        var pcm = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        pcm = Array(repeating: pcm, count: 4).flatMap { $0 }
        let control = try model.session(.init(nThreads: 4, nCtx: 2048))
        let controlStart = ContinuousClock.now
        _ = try control.run(pcm, options: RunOptions(timestamps: .none, language: "zh"))
        try emit(["event": "cancel_control", "audio_seconds": Double(pcm.count) / 16000,
                  "seconds": seconds(controlStart), "truncated": control.wasTruncated])
        let session = try model.session(.init(nThreads: 4, nCtx: 2048))
        let token = CancellationToken()
        session.setCancellationToken(token)
        let start = ContinuousClock.now
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { token.cancel() }
        var cancellationConfirmed = false
        do {
            _ = try session.run(pcm, options: RunOptions(timestamps: .none, language: "zh"))
            try emit(["event": "cancel", "aborted": session.wasAborted, "requested": token.isCancelled, "returned_success": true, "seconds": seconds(start)])
        } catch {
            try emit(["event": "cancel", "aborted": session.wasAborted,
                      "requested": token.isCancelled, "seconds": seconds(start), "failure_type": String(describing: type(of: error))])
            cancellationConfirmed = session.wasAborted && token.isCancelled
            guard cancellationConfirmed else { throw error }
        }
        return cancellationConfirmed ? 0 : 2
    }
}
