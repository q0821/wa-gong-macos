import Foundation
import OSLog
import SwiftData

class TranscriptionAutoCleanupService {
    static let shared = TranscriptionAutoCleanupService()

    private let logger = Logger(subsystem: "com.jackie-yeh.wagong", category: "TranscriptionAutoCleanupService")
    private var modelContext: ModelContext?

    private var recordingsDirectory: URL {
        AppIdentity.applicationSupportDirectoryURL
            .appendingPathComponent("Recordings")
    }

    private var deletionPolicy: AudioFileDeletionPolicy {
        AudioFileDeletionPolicy(recordingsDirectory: recordingsDirectory)
    }

    private init() {}

    func startMonitoring(modelContext: ModelContext) {
        self.modelContext = modelContext

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTranscriptionCompleted(_:)),
            name: .transcriptionCompleted,
            object: nil
        )

        if UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) {
            Task { [weak self] in
                guard let self = self, let modelContext = self.modelContext else { return }
                await self.sweepOldTranscriptions(modelContext: modelContext)
            }
        }
    }

    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self, name: .transcriptionCompleted, object: nil)
    }

    func runManualCleanup(modelContext: ModelContext) async {
        await sweepOldTranscriptions(modelContext: modelContext)
    }

    @objc private func handleTranscriptionCompleted(_ notification: Notification) {
        let isEnabled = UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled)
        guard isEnabled else { return }

        let minutes = UserDefaults.standard.integer(forKey: CleanupSettingsKeys.transcriptionRetentionMinutes)
        if minutes > 0 {
            if let modelContext = self.modelContext {
                Task { [weak self] in
                    guard let self = self else { return }
                    await self.sweepOldTranscriptions(modelContext: modelContext)
                }
            }
            return
        }

        guard let transcription = notification.object as? Transcription,
            let modelContext = self.modelContext
        else {
            logger.error("Invalid transcription or missing model context")
            return
        }

        guard transcription.transcriptionStatus != TranscriptionStatus.pending.rawValue else {
            logger.error("Refused to delete a pending transcription")
            return
        }

        if transcription.audioFileURL != nil {
            guard let url = deletionPolicy.safeAudioURL(transcription.audioFileURL) else {
                logger.error("Refused to delete an audio file outside the safe recording boundary")
                return
            }
            let allTranscriptions: [Transcription]
            do {
                allTranscriptions = try modelContext.fetch(FetchDescriptor<Transcription>())
            } catch {
                logger.error(
                    "Refused audio deletion because shared references could not be checked: \(String(describing: type(of: error)), privacy: .public)"
                )
                return
            }
            let hasOtherReference = allTranscriptions.contains { candidate in
                candidate.id != transcription.id
                    && deletionPolicy.safeAudioURL(candidate.audioFileURL)?.path == url.path
            }
            if !hasOtherReference, !AudioCleanupManager.isProtected(url) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    logger.error("Failed to delete an audio file: \(String(describing: type(of: error)), privacy: .public)")
                    return
                }
            }
        }

        modelContext.delete(transcription)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
        } catch {
            logger.error("Failed to save after transcription deletion: \(error, privacy: .public)")
        }
    }

    private func sweepOldTranscriptions(modelContext: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) else {
            return
        }

        let retentionMinutes = UserDefaults.standard.integer(forKey: CleanupSettingsKeys.transcriptionRetentionMinutes)
        let effectiveMinutes = max(retentionMinutes, 0)

        let cutoffDate = Date().addingTimeInterval(TimeInterval(-effectiveMinutes * 60))

        let modelContainer = await MainActor.run { modelContext.container }

        do {
            let backgroundContext = ModelContext(modelContainer)

            let allItems = try backgroundContext.fetch(FetchDescriptor<Transcription>())
            let items = allItems.filter {
                $0.timestamp < cutoffDate
                    && $0.transcriptionStatus != TranscriptionStatus.pending.rawValue
            }
            let expiredIDs = Set(items.map(\.id))
            let groupedReferences = Dictionary(grouping: allItems.compactMap { item -> (String, Transcription)? in
                guard let url = deletionPolicy.safeAudioURL(item.audioFileURL) else { return nil }
                return (url.path, item)
            }, by: { $0.0 })
            let deletablePaths: Set<String> = Set(groupedReferences.compactMap { path, references in
                let records = references.map(\.1)
                guard records.allSatisfy({ expiredIDs.contains($0.id) }),
                    records.allSatisfy({ $0.transcriptionStatus != TranscriptionStatus.pending.rawValue }),
                    let url = records.compactMap({ deletionPolicy.safeAudioURL($0.audioFileURL) }).first,
                    !AudioCleanupManager.isProtected(url)
                else { return nil }
                return path
            })
            var deletedAudioPaths = Set<String>()
            var deletedCount = 0
            for transcription in items {
                if transcription.audioFileURL != nil {
                    guard let url = deletionPolicy.safeAudioURL(transcription.audioFileURL) else {
                        logger.error("Skipped a transcription with an unsafe audio file location")
                        backgroundContext.delete(transcription)
                        deletedCount += 1
                        continue
                    }
                    if deletablePaths.contains(url.path), deletedAudioPaths.insert(url.path).inserted {
                        do {
                            try FileManager.default.removeItem(at: url)
                        } catch {
                            logger.error("Failed to delete an expired audio file: \(String(describing: type(of: error)), privacy: .public)")
                            continue
                        }
                    }
                }
                backgroundContext.delete(transcription)
                deletedCount += 1
            }
            if deletedCount > 0 {
                try backgroundContext.save()
                logger.notice("Cleaned up \(deletedCount, privacy: .public) old transcription(s)")
                await MainActor.run {
                    NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
                }
            }
        } catch {
            logger.error("Failed during transcription cleanup: \(error, privacy: .public)")
        }
    }

}
