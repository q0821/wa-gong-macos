import Foundation
import Testing
@testable import VoiceInk

struct TestBuildIdentityTests {
    @Test func completeBuildMetadataCreatesIdentity() throws {
        let identity = try #require(
            TestBuildIdentity(
                infoDictionary: [
                    TestBuildIdentity.buildIDKey: "T-20260903-221500-7f3a2c91",
                    TestBuildIdentity.buildChannelKey: "test",
                    TestBuildIdentity.sourceFingerprintKey: "7f3a2c91abcdef",
                    TestBuildIdentity.sourceRevisionKey: "0123456789abcdef",
                    TestBuildIdentity.sourceStateKey: "dirty",
                    TestBuildIdentity.buildTimestampKey: "2026-09-03T22:15:00Z",
                ]
            )
        )

        #expect(identity.buildID == "T-20260903-221500-7f3a2c91")
        #expect(identity.badgeLabel == "TEST 7F3A2C91")
    }

    @Test func missingOrUnexpandedBuildMetadataDoesNotCreateIdentity() {
        let missingFingerprint = TestBuildIdentity(
            infoDictionary: [
                TestBuildIdentity.buildIDKey: "T-20260903-221500-7f3a2c91",
                TestBuildIdentity.buildChannelKey: "test",
                TestBuildIdentity.sourceRevisionKey: "0123456789abcdef",
                TestBuildIdentity.sourceStateKey: "dirty",
                TestBuildIdentity.buildTimestampKey: "2026-09-03T22:15:00Z",
            ]
        )
        let unexpandedBuildID = TestBuildIdentity(
            infoDictionary: [
                TestBuildIdentity.buildIDKey: "$(WAGONG_BUILD_ID)",
                TestBuildIdentity.buildChannelKey: "test",
                TestBuildIdentity.sourceFingerprintKey: "7f3a2c91abcdef",
                TestBuildIdentity.sourceRevisionKey: "0123456789abcdef",
                TestBuildIdentity.sourceStateKey: "dirty",
                TestBuildIdentity.buildTimestampKey: "2026-09-03T22:15:00Z",
            ]
        )

        #expect(missingFingerprint == nil)
        #expect(unexpandedBuildID == nil)
    }

    @Test func receiptArgumentRequiresFollowingPath() {
        #expect(TestBuildIdentity.requestedReceiptURL(arguments: ["Wa-Gong"]) == nil)
        #expect(TestBuildIdentity.requestedReceiptURL(arguments: ["Wa-Gong", "--test-build-receipt"]) == nil)
        #expect(
            TestBuildIdentity.requestedReceiptURL(
                arguments: ["Wa-Gong", "--test-build-receipt", "/tmp/receipt.plist"]
            )?.path == "/tmp/receipt.plist"
        )
    }

    @Test func launchReceiptIsWrittenWithRestrictivePermissions() throws {
        let identity = try #require(
            TestBuildIdentity(
                infoDictionary: [
                    TestBuildIdentity.buildIDKey: "T-20260903-221500-7f3a2c91",
                    TestBuildIdentity.buildChannelKey: "test",
                    TestBuildIdentity.sourceFingerprintKey: "7f3a2c91abcdef",
                    TestBuildIdentity.sourceRevisionKey: "0123456789abcdef",
                    TestBuildIdentity.sourceStateKey: "dirty",
                    TestBuildIdentity.buildTimestampKey: "2026-09-03T22:15:00Z",
                ]
            )
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let receiptURL = temporaryDirectory.appendingPathComponent("receipt.plist")

        try identity.writeLaunchReceiptIfRequested(
            arguments: ["Wa-Gong", "--test-build-receipt", receiptURL.path],
            bundle: .main,
            processIdentifier: 42
        )

        let data = try Data(contentsOf: receiptURL)
        let receipt = try PropertyListDecoder().decode(TestBuildLaunchReceipt.self, from: data)
        let attributes = try FileManager.default.attributesOfItem(atPath: receiptURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)

        #expect(receipt.buildID == identity.buildID)
        #expect(receipt.sourceFingerprint == identity.sourceFingerprint)
        #expect(receipt.processIdentifier == 42)
        #expect(permissions.intValue == 0o600)
    }
}
