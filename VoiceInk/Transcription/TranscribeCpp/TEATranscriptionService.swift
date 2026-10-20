import AppKit
import FluidAudio
import Foundation
import os
import AVFoundation

final class TEATranscriptionService: TranscriptionService, @unchecked Sendable {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pressure: DispatchSourceMemoryPressure?
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "TEA")

    init() {
        let center = NotificationCenter.default
        for name in [Notification.Name.modeConfigurationApplied, .transcribeCppModelDeleted,
                     NSApplication.willTerminateNotification] {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: nil) { _ in
                Task { await TEARuntimeManager.shared.cancel() }
            }))
        }
        observers.append((center, center.addObserver(forName: .didChangeModel, object: nil, queue: nil) { note in
            if note.userInfo?["modelName"] as? String != TranscribeCppModelCatalog.tea.modelName {
                Task { await TEARuntimeManager.shared.cancel() }
            }
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                                            object: nil, queue: nil) { _ in
            Task { await TEARuntimeManager.shared.cancel() }
        }))
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        source.setEventHandler { Task { await TEARuntimeManager.shared.unloadIfIdle() } }
        source.resume()
        pressure = source
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
        pressure?.cancel()
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String {
        guard model.name == TranscribeCppModelCatalog.tea.modelName else { throw TEARuntimeError.invalidModel }
        let started = ContinuousClock.now
        do {
            let samples = try await Task.detached {
                do {
                    let file = try AVAudioFile(forReading: audioURL)
                    let duration = Double(file.length) / file.processingFormat.sampleRate
                    guard duration.isFinite, duration > 0, duration <= 30 else { throw TEARuntimeError.invalidAudio }
                    return try AudioConverter().resampleAudioFile(audioURL)
                } catch { throw TEARuntimeError.invalidAudio }
            }.value
            try Task.checkCancellation()
            logger.notice("TEA audio preprocessing elapsed=\(started.duration(to: .now).formatted(.units(allowed: [.seconds])), privacy: .public)")
            let language = context.language == "zh-TW" ? "zh" : (context.language ?? "auto")
            let result = try await TEARuntimeManager.shared.transcribe(samples: samples, language: language)
            logger.notice("TEA total processing elapsed=\(started.duration(to: .now).formatted(.units(allowed: [.seconds])), privacy: .public)")
            return result
        } catch is CancellationError { throw CancellationError() }
        catch let error as TEARuntimeError { throw error }
        catch { throw TEARuntimeError.failed }
    }

    func cleanup() { Task { await TEARuntimeManager.shared.cancel() } }
}
