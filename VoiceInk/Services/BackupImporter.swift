import Foundation
import SwiftData

enum BackupImportError: LocalizedError {
    case saveFailed(String, Error)
    case unsafeBackup(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let item, let error):
            return String(format: String(localized: "Failed to save imported %@: %@"), item, error.localizedDescription)
        case .unsafeBackup(let reason):
            return String(format: String(localized: "The settings backup is not safe to import: %@"), reason)
        }
    }
}

enum BackupImporter {
    private static let keyIsTextFormattingEnabled = "IsTextFormattingEnabled"

    @MainActor
    static func apply(
        _ backup: BackupFile, categories: Set<BackupCategory>, enhancementService: AIEnhancementService,
        recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager,
        mediaController: MediaController, playbackController: PlaybackController, recorderUIManager: RecorderUIManager,
        modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager,
        allowImportedCustomCommands: Bool = false
    ) throws {
        try BackupImportSecurityPolicy.validate(backup)
        var shouldRepairModePromptSelections = false

        if categories.contains(.dictionary) {
            try importDictionary(from: backup, modelContext: modelContext)
        }

        if categories.contains(.general) {
            importGeneral(
                backup.generalSettings,
                recordingShortcutManager: recordingShortcutManager,
                menuBarManager: menuBarManager,
                mediaController: mediaController,
                playbackController: playbackController,
                recorderUIManager: recorderUIManager
            )
        }

        if categories.contains(.prompts) {
            enhancementService.customPrompts = backup.customPrompts
            shouldRepairModePromptSelections = true
            print("Successfully imported \(backup.customPrompts.count) prompts.")
        }

        if categories.contains(.modes) {
            let modeManager = ModeManager.shared
            for config in modeManager.configurations {
                ShortcutStore.removeShortcutStorage(for: .mode(config.id))
            }

            let importedModes = BackupImportSecurityPolicy.sanitizedModes(
                backup.modeConfigs,
                allowCustomCommands: allowImportedCustomCommands
            )
            if allowImportedCustomCommands {
                modeManager.replaceConfigurationsFromApprovedImport(importedModes)
            } else {
                modeManager.configurations = importedModes
            }
            let importedModeIds = Set(importedModes.map(\.id))

            if let shortcuts = backup.modeShortcuts {
                for (idString, shortcutBackup) in shortcuts {
                    guard
                        let id = UUID(uuidString: idString),
                        importedModeIds.contains(id)
                    else {
                        continue
                    }

                    ShortcutStore.setShortcut(shortcutBackup.shortcut, for: .mode(id))
                }
            }

            if !allowImportedCustomCommands {
                modeManager.saveConfigurations()
            }
            shouldRepairModePromptSelections = true

            if let customEmojis = backup.customEmojis {
                let emojiManager = EmojiManager.shared
                for emoji in customEmojis {
                    _ = emojiManager.addCustomEmoji(emoji)
                }
            }
            print("Successfully imported \(importedModes.count) Mode configurations.")
        }

        if shouldRepairModePromptSelections {
            enhancementService.repairModePromptSelections()
        }

        if categories.contains(.customModels) {
            importCustomModels(backup.customCloudModels, transcriptionModelManager: transcriptionModelManager)
        }
    }

    @MainActor
    private static func importGeneral(
        _ general: GeneralBackup?, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager,
        mediaController: MediaController, playbackController: PlaybackController, recorderUIManager: RecorderUIManager
    ) {
        guard let general else {
            print("No general settings found in the imported file.")
            return
        }

        if let shortcut = general.primaryRecordingShortcut {
            ShortcutStore.setShortcut(shortcut.shortcut, for: .primaryRecording)
            recordingShortcutManager.primaryRecordingShortcut = .custom
        }
        if let shortcut2 = general.secondaryRecordingShortcut {
            ShortcutStore.setShortcut(shortcut2.shortcut, for: .secondaryRecording)
            recordingShortcutManager.secondaryRecordingShortcut = .custom
        }
        if let pasteShortcut = general.pasteLastTranscriptionShortcut {
            ShortcutStore.setShortcut(pasteShortcut.shortcut, for: .pasteLastTranscription)
        }
        if let pasteEnhancementShortcut = general.pasteLastEnhancementShortcut {
            ShortcutStore.setShortcut(pasteEnhancementShortcut.shortcut, for: .pasteLastEnhancement)
        }
        if let retryShortcut = general.retryLastTranscriptionShortcut {
            ShortcutStore.setShortcut(retryShortcut.shortcut, for: .retryLastTranscription)
        }
        if let cancelShortcut = general.cancelRecorderShortcut {
            ShortcutStore.setShortcut(cancelShortcut.shortcut, for: .cancelRecorder)
        }
        if let historyShortcut = general.openHistoryWindowShortcut {
            ShortcutStore.setShortcut(historyShortcut.shortcut, for: .openHistoryWindow)
        }
        if let dictionaryShortcut = general.quickAddToDictionaryShortcut {
            ShortcutStore.setShortcut(dictionaryShortcut.shortcut, for: .quickAddToDictionary)
        }

        if let shortcutRawValue = general.primaryRecordingShortcutRawValue,
            let shortcut = RecordingShortcutManager.ShortcutSelection(rawValue: shortcutRawValue)
        {
            recordingShortcutManager.primaryRecordingShortcut = shortcut
        }
        if let secondaryShortcutRawValue = general.secondaryRecordingShortcutRawValue,
            let secondaryShortcut = RecordingShortcutManager.ShortcutSelection(rawValue: secondaryShortcutRawValue)
        {
            recordingShortcutManager.secondaryRecordingShortcut = secondaryShortcut
        }
        if let modeRawValue = general.primaryRecordingShortcutModeRawValue,
            let mode = RecordingShortcutManager.Mode(rawValue: modeRawValue)
        {
            recordingShortcutManager.primaryRecordingShortcutMode = mode
        }
        if let secondaryModeRawValue = general.secondaryRecordingShortcutModeRawValue,
            let secondaryMode = RecordingShortcutManager.Mode(rawValue: secondaryModeRawValue)
        {
            recordingShortcutManager.secondaryRecordingShortcutMode = secondaryMode
        }
        if let middleClickEnabled = general.isMiddleClickToggleEnabled {
            recordingShortcutManager.isMiddleClickToggleEnabled = middleClickEnabled
        }
        if let middleClickDelay = general.middleClickActivationDelay {
            recordingShortcutManager.middleClickActivationDelay = middleClickDelay
        }
        if let launch = general.launchAtLoginEnabled {
            LaunchAtLoginManager.shared.setEnabled(launch)
        }
        if let menuOnly = general.isMenuBarOnly {
            menuBarManager.isMenuBarOnly = menuOnly
        }
        if let recType = general.recorderType {
            recorderUIManager.recorderType = recType
        }
        if let rawAppearancePreference = general.appAppearancePreference,
            let appearancePreference = AppAppearancePreference(rawValue: rawAppearancePreference)
        {
            UserDefaults.standard.set(appearancePreference.rawValue, forKey: AppAppearancePreference.userDefaultsKey)
            appearancePreference.apply()
        }
        if let rawLanguagePreference = general.appLanguagePreference {
            let languagePreference = AppLanguagePreference.normalizedRawValue(rawLanguagePreference)
            UserDefaults.standard.set(languagePreference, forKey: AppLanguagePreference.userDefaultsKey)
            AppLanguagePreference.apply(rawValue: languagePreference)
        }

        if let transcriptionCleanup = general.isTranscriptionCleanupEnabled {
            UserDefaults.standard.set(transcriptionCleanup, forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled)
        }
        if let transcriptionMinutes = general.transcriptionRetentionMinutes {
            UserDefaults.standard.set(transcriptionMinutes, forKey: CleanupSettingsKeys.transcriptionRetentionMinutes)
        }
        if let audioCleanup = general.isAudioCleanupEnabled {
            UserDefaults.standard.set(audioCleanup, forKey: CleanupSettingsKeys.isAudioCleanupEnabled)
        }
        if let audioRetention = general.audioRetentionPeriod {
            UserDefaults.standard.set(audioRetention, forKey: CleanupSettingsKeys.audioRetentionPeriod)
        }

        if let muteSystem = general.isSystemMuteEnabled {
            mediaController.isSystemMuteEnabled = muteSystem
        }
        if let pauseMedia = general.isPauseMediaEnabled {
            playbackController.isPauseMediaEnabled = pauseMedia
        }
        if let audioDelay = general.audioResumptionDelay {
            mediaController.audioResumptionDelay = audioDelay
        }
        if let experimentalEnabled = general.isExperimentalFeaturesEnabled {
            UserDefaults.standard.set(experimentalEnabled, forKey: "isExperimentalFeaturesEnabled")
            if experimentalEnabled == false {
                playbackController.isPauseMediaEnabled = false
            }
        }
        if let textFormattingEnabled = general.isTextFormattingEnabled {
            UserDefaults.standard.set(textFormattingEnabled, forKey: keyIsTextFormattingEnabled)
        }
        if let restoreClipboard = general.restoreClipboardAfterPaste {
            UserDefaults.standard.set(restoreClipboard, forKey: "restoreClipboardAfterPaste")
        }
        if let clipboardDelay = general.clipboardRestoreDelay {
            UserDefaults.standard.set(clipboardDelay, forKey: "clipboardRestoreDelay")
        }

        print("Successfully imported general settings.")
    }

    @MainActor
    private static func importDictionary(from backup: BackupFile, modelContext: ModelContext) throws {
        var insertedWords = 0
        var insertedReplacements = 0
        var skippedInvalidReplacements = 0

        if let words = backup.vocabularyWords {
            let descriptor = FetchDescriptor<VocabularyWord>()
            let existingWords = try modelContext.fetch(descriptor)
            var existingWordsSet = Set(existingWords.map { $0.word.lowercased() })

            for item in words {
                let word = item.word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty else { continue }

                let lowercasedWord = word.lowercased()
                if !existingWordsSet.contains(lowercasedWord) {
                    modelContext.insert(VocabularyWord(word: word))
                    existingWordsSet.insert(lowercasedWord)
                    insertedWords += 1
                }
            }
        } else {
            print("No vocabulary words found in the imported file. Existing items remain unchanged.")
        }

        if let replacements = backup.wordReplacements {
            let descriptor = FetchDescriptor<WordReplacement>()
            let existingReplacements = try modelContext.fetch(descriptor)

            var existingKeys = Set<String>()
            for existing in existingReplacements {
                existingKeys.formUnion(tokens(from: existing.originalText))
            }

            for (original, replacement) in replacements {
                let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                let importTokens = tokens(from: trimmedOriginal)
                guard !importTokens.isEmpty, !trimmedReplacement.isEmpty else {
                    skippedInvalidReplacements += 1
                    continue
                }

                let hasConflict = importTokens.contains { existingKeys.contains($0) }

                if !hasConflict {
                    modelContext.insert(
                        WordReplacement(originalText: trimmedOriginal, replacementText: trimmedReplacement))
                    existingKeys.formUnion(importTokens)
                    insertedReplacements += 1
                }
            }
        } else {
            print("No word replacements found in the imported file. Existing replacements remain unchanged.")
        }

        guard insertedWords > 0 || insertedReplacements > 0 else {
            print("No new dictionary entries were imported.")
            if skippedInvalidReplacements > 0 {
                print("Skipped \(skippedInvalidReplacements) invalid word replacements from the imported file.")
            }
            DictionaryService.removeExactDuplicateContent(context: modelContext, source: "settings import")
            return
        }

        do {
            try modelContext.save()
            print(
                "Successfully imported \(insertedWords) vocabulary words and \(insertedReplacements) word replacements to SwiftData."
            )
            if skippedInvalidReplacements > 0 {
                print("Skipped \(skippedInvalidReplacements) invalid word replacements from the imported file.")
            }
            DictionaryService.removeExactDuplicateContent(context: modelContext, source: "settings import")
        } catch {
            modelContext.rollback()
            throw BackupImportError.saveFailed("dictionary entries", error)
        }
    }

    @MainActor
    private static func importCustomModels(
        _ models: [CustomModelBackup]?, transcriptionModelManager: TranscriptionModelManager
    ) {
        guard let models else {
            print("No custom models found in the imported file.")
            return
        }

        let customModelManager = CustomCloudModelManager.shared
        customModelManager.customModels = models.map { $0.makeImportedModel() }
        customModelManager.saveCustomModels()
        transcriptionModelManager.refreshAllAvailableModels()
        print("Successfully imported \(models.count) custom model definitions.")
    }

    private static func tokens(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

enum BackupImportSecurityPolicy {
    static let maximumFileBytes = 10 * 1024 * 1024
    static let allowedTranscriptionRetentionMinutes: Set<Int> = [0, 60, 24 * 60, 3 * 24 * 60, 7 * 24 * 60]
    static let allowedAudioRetentionDays: Set<Int> = [1, 3, 7, 14, 30]

    static func validate(_ backup: BackupFile) throws {
        let limits: [(String, Int, Int)] = [
            ("custom prompts", backup.customPrompts.count, 1_000),
            ("modes", backup.modeConfigs.count, 500),
            ("mode shortcuts", backup.modeShortcuts?.count ?? 0, 500),
            ("vocabulary words", backup.vocabularyWords?.count ?? 0, 10_000),
            ("word replacements", backup.wordReplacements?.count ?? 0, 10_000),
            ("custom emojis", backup.customEmojis?.count ?? 0, 1_000),
            ("custom models", backup.customCloudModels?.count ?? 0, 500),
        ]
        if let exceeded = limits.first(where: { $0.1 > $0.2 }) {
            throw BackupImportError.unsafeBackup("\(exceeded.0) exceeds the supported item limit")
        }

        if let minutes = backup.generalSettings?.transcriptionRetentionMinutes,
            !allowedTranscriptionRetentionMinutes.contains(minutes)
        {
            throw BackupImportError.unsafeBackup("transcription retention has an unsupported value")
        }
        if let days = backup.generalSettings?.audioRetentionPeriod,
            !allowedAudioRetentionDays.contains(days)
        {
            throw BackupImportError.unsafeBackup("audio retention has an unsupported value")
        }
    }

    static func loadFileURL(_ url: URL) throws -> Data {
        do {
            return try BoundedRegularFileReader.load(url, maximumBytes: maximumFileBytes)
        } catch {
            throw BackupImportError.unsafeBackup("the selected item must be a direct regular file no larger than 10 MB")
        }
    }

    static func destructiveCleanupSummary(
        _ general: GeneralBackup?,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard let general else { return nil }
        var lines: [String] = []
        let importsTranscriptionCleanup = general.isTranscriptionCleanupEnabled != nil
            || general.transcriptionRetentionMinutes != nil
        let effectiveTranscriptionCleanup = general.isTranscriptionCleanupEnabled
            ?? defaults.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled)
        if importsTranscriptionCleanup, effectiveTranscriptionCleanup {
            let minutes = general.transcriptionRetentionMinutes
                ?? (defaults.object(forKey: CleanupSettingsKeys.transcriptionRetentionMinutes) as? Int)
                ?? 24 * 60
            lines.append("Transcript history and related audio will be deleted after \(minutes) minutes.")
        }
        let importsAudioCleanup = general.isAudioCleanupEnabled != nil || general.audioRetentionPeriod != nil
        let effectiveAudioCleanup = general.isAudioCleanupEnabled
            ?? defaults.bool(forKey: CleanupSettingsKeys.isAudioCleanupEnabled)
        if importsAudioCleanup, effectiveAudioCleanup {
            let days = general.audioRetentionPeriod
                ?? (defaults.object(forKey: CleanupSettingsKeys.audioRetentionPeriod) as? Int)
                ?? 3
            lines.append("Audio files will be deleted after \(days) days while transcript history is kept.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func sanitizedModes(_ modes: [ModeConfig], allowCustomCommands: Bool) -> [ModeConfig] {
        guard !allowCustomCommands else { return modes }

        return modes.map { mode in
            guard mode.outputMode == .customCommand, mode.customCommand?.trimmedCommand != nil else {
                return mode
            }

            var sanitized = mode
            sanitized.isEnabled = false
            sanitized.isDefault = false
            return sanitized
        }
    }

    static func importedCommands(in modes: [ModeConfig]) -> [(modeName: String, command: String)] {
        modes.compactMap { mode in
            guard mode.outputMode == .customCommand, let command = mode.customCommand?.trimmedCommand else {
                return nil
            }
            return (mode.name, command)
        }
    }
}
