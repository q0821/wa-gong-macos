import Foundation
import OSLog

enum AppIdentity {
    static let displayName = "聲筆 Wa-Gong"
    static let bundleIdentifier = "com.jackie-yeh.wagong"
    static let legacyBundleIdentifier = "com.prakashjoshipax.VoiceInk"
    static let refineXPCBundleIdentifier = "\(bundleIdentifier).RefineXPC"
    static let iCloudContainerIdentifier = "iCloud.\(bundleIdentifier)"

    private static let logger = Logger(subsystem: bundleIdentifier, category: "AppIdentity")

    static var applicationSupportDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    static func migrateLegacyStorageIfNeeded(fileManager: FileManager = .default) {
        migrateLegacyUserDefaultsIfNeeded()

        let applicationSupportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let currentDirectory = applicationSupportRoot.appendingPathComponent(bundleIdentifier, isDirectory: true)
        let legacyDirectory = applicationSupportRoot.appendingPathComponent(
            legacyBundleIdentifier,
            isDirectory: true
        )

        guard !fileManager.fileExists(atPath: currentDirectory.path),
            fileManager.fileExists(atPath: legacyDirectory.path)
        else {
            return
        }

        do {
            try fileManager.moveItem(at: legacyDirectory, to: currentDirectory)
            logger.info("Migrated legacy application support data to the Wa-Gong storage location")
        } catch {
            logger.error("Failed to migrate legacy application support data: \(error, privacy: .public)")
        }
    }

    private static func migrateLegacyUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacyDomain = defaults.persistentDomain(forName: legacyBundleIdentifier), !legacyDomain.isEmpty else {
            return
        }

        let currentDomain = defaults.persistentDomain(forName: bundleIdentifier) ?? [:]
        guard currentDomain.isEmpty else {
            return
        }

        defaults.setPersistentDomain(legacyDomain, forName: bundleIdentifier)
        logger.info("Migrated legacy user defaults to the Wa-Gong preferences domain")
    }
}

enum CleanupSettingsKeys {
    static let isTranscriptionCleanupEnabled = "IsTranscriptionCleanupEnabled"
    static let transcriptionRetentionMinutes = "TranscriptionRetentionMinutes"
    static let isAudioCleanupEnabled = "IsAudioCleanupEnabled"
    static let audioRetentionPeriod = "AudioRetentionPeriod"
    static let lastAutomaticAudioCleanupDate = "AudioCleanupLastAutomaticCleanupDate"
}

enum RecorderDisplaySettingsKeys {
    static let showLiveTranscript = "ShowLiveTranscript"
}

enum AppDefaults {
    static let defaultTranscriptionLanguage = "auto"
    private static let transcriptionLanguageMigrationKey = "HasMigratedTranscriptionLanguageToAuto"

    static func registerDefaults() {
        migrateLegacyTranscriptionLanguageIfNeeded()

        UserDefaults.standard.register(defaults: [
            // Onboarding & General
            "hasCompletedOnboardingV2": false,
            "hasPreparedOnboardingV2": false,
            "enableAnnouncements": true,

            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "useAppleScriptPaste": false,

            // Audio & Media
            "isSystemMuteEnabled": true,
            "audioResumptionDelay": 0.0,
            "isPauseMediaEnabled": false,
            CustomSoundManager.SoundType.start.builtInSoundKey: CustomSoundManager.SoundType.start.defaultBuiltInSound
                .rawValue,
            CustomSoundManager.SoundType.stop.builtInSoundKey: CustomSoundManager.SoundType.stop.defaultBuiltInSound
                .rawValue,

            // Recording & Transcription
            "IsTextFormattingEnabled": true,
            "IsVADEnabled": true,
            "SelectedLanguage": defaultTranscriptionLanguage,
            "AppendTrailingSpace": true,
            "RecorderType": "mini",
            RecorderDisplaySettingsKeys.showLiveTranscript: true,

            // Cleanup
            CleanupSettingsKeys.isTranscriptionCleanupEnabled: false,
            CleanupSettingsKeys.transcriptionRetentionMinutes: 1440,
            CleanupSettingsKeys.isAudioCleanupEnabled: false,
            CleanupSettingsKeys.audioRetentionPeriod: 7,

            // UI & Behavior
            "IsMenuBarOnly": false,
            AppAppearancePreference.userDefaultsKey: AppAppearancePreference.system.rawValue,
            AppLanguagePreference.userDefaultsKey: AppLanguagePreference.systemValue,
            // Shortcuts
            "isMiddleClickToggleEnabled": false,
            "middleClickActivationDelay": 200,

            // Enhancement
            "SkipShortEnhancement": true,
            "ShortEnhancementWordThreshold": 3,
            "EnhancementTimeoutSeconds": 7,
            "EnhancementRetryOnTimeout": true,

            // Model
            "PrewarmModelOnWake": true,

        ])

        PasteMethod.migrateLegacyUserDefaultIfNeeded()
    }

    static func migrateLegacyTranscriptionLanguageIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: transcriptionLanguageMigrationKey) else { return }

        if defaults.string(forKey: "SelectedLanguage") == "en" {
            defaults.set(defaultTranscriptionLanguage, forKey: "SelectedLanguage")
        }

        defaults.set(true, forKey: transcriptionLanguageMigrationKey)
    }
}
