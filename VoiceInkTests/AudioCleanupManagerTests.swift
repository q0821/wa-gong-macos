import Foundation
import SwiftData
import Testing
@testable import VoiceInk

@MainActor
struct AudioCleanupManagerTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func withFixture(_ body: (AudioCleanupManager, ModelContext, URL, UserDefaults) async throws -> Void) async throws {
        let suite = "AudioCleanupTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let container = try ModelContainer(for: Transcription.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let manager = AudioCleanupManager(defaults: defaults, recordingsDirectory: root, now: { fixedNow })
        try await body(manager, container.mainContext, root, defaults)
    }

    private func add(_ name: String, daysOld: Double, bytes: Int = 100, root: URL, context: ModelContext) throws -> Transcription {
        let url = root.appendingPathComponent(name).appendingPathExtension("wav")
        try Data(repeating: 1, count: bytes).write(to: url)
        let item = Transcription(text: name, duration: 1, audioFileURL: url.absoluteString, transcriptionStatus: .completed)
        item.timestamp = fixedNow.addingTimeInterval(-daysOld * 86400)
        context.insert(item)
        try context.save()
        return item
    }

    @Test func defaultsDeleteAtThreeDaysEvenBelowCapacityAndKeepNewerAudio() async throws {
        try await withFixture { manager, context, root, _ in
            let expired = try add("expired", daysOld: 3, root: root, context: context)
            let recent = try add("recent", daysOld: 2.99, root: root, context: context)
            await manager.runAutomaticCleanupIfNeeded(modelContext: context)
            #expect(expired.audioFileURL == nil)
            #expect(expired.text == "expired")
            #expect(recent.audioFileURL != nil)
        }
    }

    @Test func capacityBoundaryAndSecondCleanupAfterNewRecording() async throws {
        try await withFixture { manager, context, root, defaults in
            defaults.set(1, forKey: CleanupSettingsKeys.audioStorageLimitMB)
            let oldest = try add("oldest", daysOld: 2, bytes: 500_000, root: root, context: context)
            _ = try add("newer", daysOld: 1, bytes: 500_000, root: root, context: context)
            await manager.runAutomaticCleanupIfNeeded(modelContext: context)
            #expect(oldest.audioFileURL != nil)
            _ = try add("newest", daysOld: 0, bytes: 10, root: root, context: context)
            await manager.runAutomaticCleanupIfNeeded(modelContext: context)
            #expect(oldest.audioFileURL == nil)
            #expect(manager.currentStorageBytes() == 500_010)
        }
    }

    @Test func stalePreviewDoesNotDeleteAudioThatIsNowInUse() async throws {
        try await withFixture { manager, context, root, _ in
            let item = try add("in-use", daysOld: 5, root: root, context: context)
            let info = await manager.getCleanupInfo(modelContext: context)
            let urlString = try #require(item.audioFileURL)
            let url = try #require(URL(string: urlString))
            AudioCleanupManager.protect(url)
            defer { AudioCleanupManager.release(url) }
            let result = await manager.runCleanupForTranscriptions(modelContext: context, transcriptions: info.transcriptions)
            #expect(result.deletedCount == 0)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func explicitOptOutAndExternalOrSymlinkFilesArePreserved() async throws {
        try await withFixture { manager, context, root, defaults in
            let item = try add("expired", daysOld: 5, root: root, context: context)
            defaults.set(false, forKey: CleanupSettingsKeys.isAudioCleanupEnabled)
            await manager.runAutomaticCleanupIfNeeded(modelContext: context)
            #expect(item.audioFileURL != nil)
            let external = root.appendingPathComponent("external", isDirectory: true)
            try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
            let outside = try add("source", daysOld: 5, root: external, context: context)
            let sourceString = try #require(outside.audioFileURL)
            let sourceURL = try #require(URL(string: sourceString))
            let link = root.appendingPathComponent("link.wav")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sourceURL)
            let linked = Transcription(text: "link", duration: 1, audioFileURL: link.absoluteString, transcriptionStatus: .completed)
            linked.timestamp = fixedNow.addingTimeInterval(-10 * 86400)
            context.insert(linked)
            try context.save()
            defaults.set(true, forKey: CleanupSettingsKeys.isAudioCleanupEnabled)
            await manager.runAutomaticCleanupIfNeeded(modelContext: context)
            #expect(outside.audioFileURL != nil)
            #expect(linked.audioFileURL != nil)
            #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        }
    }

    @Test func capacityDeletesOldestFinishedAudioButKeepsTextAndPendingFiles() async throws {
        let suite = "AudioCleanupTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: CleanupSettingsKeys.isAudioCleanupEnabled)
        defaults.set(3, forKey: CleanupSettingsKeys.audioRetentionPeriod)
        defaults.set(1, forKey: CleanupSettingsKeys.audioStorageLimitMB)
        let container = try ModelContainer(
            for: Transcription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let now = Date()
        var items: [Transcription] = []
        for index in 0..<3 {
            let url = root.appendingPathComponent("\(index).wav")
            try Data(repeating: 1, count: 400_000).write(to: url)
            let item = Transcription(text: "保留文字 \(index)", duration: 1,
                                     audioFileURL: url.absoluteString,
                                     transcriptionStatus: index == 0 ? .pending : .completed)
            item.timestamp = now.addingTimeInterval(Double(index - 3) * 60)
            context.insert(item)
            items.append(item)
        }
        try context.save()
        let manager = AudioCleanupManager(defaults: defaults, recordingsDirectory: root)
        await manager.runAutomaticCleanupIfNeeded(modelContext: context)
        #expect(items[0].audioFileURL != nil)
        #expect(items[1].audioFileURL == nil)
        #expect(items[2].audioFileURL != nil)
        #expect(items[1].text == "保留文字 1")
        #expect(try context.fetchCount(FetchDescriptor<Transcription>()) == 3)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("0.wav").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("1.wav").path))
    }
}
