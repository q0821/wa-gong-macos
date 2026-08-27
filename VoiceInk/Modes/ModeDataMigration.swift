import Foundation

enum ModeDataMigration {
    static let legacyDefaultTranscriptionModelName = "parakeet-tdt-0.6b-v3"
    static let legacyLocalDefaultTranscriptionModelNames = [
        legacyDefaultTranscriptionModelName,
        StarterModeFactory.defaultLocalTranscriptionModelName,
    ]

    static func migratedStarterTranscriptionModelName(for config: ModeConfig) -> String? {
        guard StarterModeCatalog.ids.contains(config.id),
            let selectedModelName = config.selectedTranscriptionModelName,
            legacyLocalDefaultTranscriptionModelNames.contains(selectedModelName)
        else {
            return config.selectedTranscriptionModelName
        }

        return StarterModeFactory.defaultTranscriptionModelName
    }

    static func migratedStarterModeName(for config: ModeConfig) -> String {
        guard let template = StarterModeCatalog.templates.first(where: { $0.id == config.id }),
            config.name == legacyEnglishName(for: template.kind)
        else {
            return config.name
        }

        return template.name
    }

    private static func legacyEnglishName(for kind: StarterModeKind) -> String {
        switch kind {
        case .clean: "Dictation"
        case .enhance: "Enhancement"
        case .email: "Email"
        case .rewrite: "Rewrite"
        case .assistant: "Assistant"
        }
    }
}

extension ModeManager {
    func migratedModeConfigurationData(for configKey: String) -> Data? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: configKey) {
            return data
        }

        guard let legacyData = defaults.data(forKey: LegacyModeDataKey.configurations) else {
            return nil
        }

        defaults.set(legacyData, forKey: configKey)
        return legacyData
    }

    func migrateLoadedModeConfigurationsIfNeeded() {
        var didChange = false

        for index in configurations.indices {
            var config = configurations[index]
            var changedConfig = false

            let migratedName = ModeDataMigration.migratedStarterModeName(for: config)
            if migratedName != config.name {
                config.name = migratedName
                changedConfig = true
            }

            let migratedTranscriptionModelName = AppDefaults.migratedGeminiTranscriptionModelName(
                config.selectedTranscriptionModelName
            )
            if migratedTranscriptionModelName != config.selectedTranscriptionModelName {
                config.selectedTranscriptionModelName = migratedTranscriptionModelName
                changedConfig = true
            }

            let migratedAIModelName = AppDefaults.migratedGeminiAIModelName(config.selectedAIModel)
            if migratedAIModelName != config.selectedAIModel {
                config.selectedAIModel = migratedAIModelName
                changedConfig = true
            }

            if config.selectedTranscriptionModelName == nil {
                config.selectedTranscriptionModelName = UserDefaults.standard.string(
                    forKey: "CurrentTranscriptionModel")
                changedConfig = true
            }

            if let migratedModelName = ModeDataMigration.migratedStarterTranscriptionModelName(for: config),
                migratedModelName != config.selectedTranscriptionModelName
            {
                config.selectedTranscriptionModelName = migratedModelName
                changedConfig = true
            }

            if config.selectedLanguage == nil {
                config.selectedLanguage =
                    UserDefaults.standard.string(forKey: "SelectedLanguage")
                    ?? AppDefaults.defaultTranscriptionLanguage
                changedConfig = true
            }

            if config.selectedAIProvider == nil {
                config.selectedAIProvider = UserDefaults.standard.string(forKey: "selectedAIProvider")
                changedConfig = true
            }

            if config.selectedAIModel == nil,
                let provider = config.selectedAIProvider
            {
                config.selectedAIModel = UserDefaults.standard.string(forKey: "\(provider)SelectedModel")
                changedConfig = true
            }

            if config.isAIEnhancementEnabled && config.selectedPrompt == nil {
                config.selectedPrompt = UserDefaults.standard.string(forKey: "selectedPromptId")
                changedConfig = true
            }

            if changedConfig {
                configurations[index] = config
                didChange = true
            }
        }

        if didChange {
            saveConfigurations()
        }

        if let currentModel = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel"),
            ModeDataMigration.legacyLocalDefaultTranscriptionModelNames.contains(currentModel)
        {
            UserDefaults.standard.set(
                StarterModeFactory.defaultTranscriptionModelName,
                forKey: "CurrentTranscriptionModel"
            )
        }

        migrateLegacyShortcutStorageIfNeeded()
    }
    private func migrateLegacyShortcutStorageIfNeeded() {
        let defaults = UserDefaults.standard

        for config in configurations {
            let oldShortcutKey = "\(LegacyModeDataKey.shortcutPrefix)\(config.id.uuidString)"
            let newShortcutKey = ShortcutAction.mode(config.id).userDefaultsKey

            if defaults.object(forKey: newShortcutKey) == nil,
                let oldShortcutData = defaults.data(forKey: oldShortcutKey)
            {
                defaults.set(oldShortcutData, forKey: newShortcutKey)
            }

            let oldClearedKey = "\(oldShortcutKey)_cleared"
            let newClearedKey = "\(newShortcutKey)_cleared"
            if defaults.object(forKey: newClearedKey) == nil,
                defaults.object(forKey: oldClearedKey) != nil
            {
                defaults.set(defaults.bool(forKey: oldClearedKey), forKey: newClearedKey)
            }
        }
    }
}

private enum LegacyModeDataKey {
    static let configurations = "powerModeConfigurationsV2"
    static let shortcutPrefix = "Shortcut_powerMode_"
}
