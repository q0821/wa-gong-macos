import Foundation
import Security
import Testing
@testable import VoiceInk

struct LegacyKeychainMigrationTests {
    @Test func currentValueTakesPriorityWithoutReadingLegacyStorage() {
        let current = Data("current".utf8)
        var didReadLegacy = false

        let result = LegacyKeychainMigration.resolve(
            current: .value(current),
            readLegacy: {
                didReadLegacy = true
                return .value(Data("legacy".utf8))
            },
            saveCurrent: { (_: Data) in false },
            deleteLegacy: {}
        )

        #expect(result.value == current)
        #expect(!didReadLegacy)
    }

    @Test func legacyValueIsCopiedThenDeletedAfterSuccessfulSave() {
        let legacy = Data("legacy".utf8)
        var savedValue: Data?
        var didDeleteLegacy = false

        let result = LegacyKeychainMigration.resolve(
            current: .notFound,
            readLegacy: { .value(legacy) },
            saveCurrent: { value in
                savedValue = value
                return true
            },
            deleteLegacy: { didDeleteLegacy = true }
        )

        #expect(result.value == legacy)
        #expect(savedValue == legacy)
        #expect(didDeleteLegacy)
    }

    @Test func failedSaveReturnsLegacyValueWithoutDeletingIt() {
        let legacy = Data("legacy".utf8)
        var didDeleteLegacy = false

        let result = LegacyKeychainMigration.resolve(
            current: .notFound,
            readLegacy: { .value(legacy) },
            saveCurrent: { _ in false },
            deleteLegacy: { didDeleteLegacy = true }
        )

        #expect(result.value == legacy)
        #expect(!didDeleteLegacy)
    }

    @Test func unavailableLegacyStorageIsNotReportedAsMissing() {
        let result = LegacyKeychainMigration.resolve(
            current: .notFound,
            readLegacy: { .unavailable(errSecAuthFailed) },
            saveCurrent: { (_: Data) in false },
            deleteLegacy: {}
        )

        #expect(result.unavailableStatus == errSecAuthFailed)
    }

    @Test func localBuildReadsProductionValueWhenNoLocalValueExists() {
        let production = Data("production".utf8)

        let result = LocalBuildKeychainLookup.resolve(
            local: .notFound,
            readLegacyLocal: { nil },
            migrateLegacyLocal: { _ in },
            readProduction: { .value(production) }
        )

        #expect(result.value == production)
    }

    @Test func localBuildValueOverridesProductionWithoutReadingIt() {
        let local = Data("local".utf8)
        var didReadProduction = false

        let result = LocalBuildKeychainLookup.resolve(
            local: .value(local),
            readLegacyLocal: { nil },
            migrateLegacyLocal: { _ in },
            readProduction: {
                didReadProduction = true
                return .value(Data("production".utf8))
            }
        )

        #expect(result.value == local)
        #expect(!didReadProduction)
    }

    @Test func legacyLocalValueOverridesProductionAndMigratesLocally() {
        let legacyLocal = Data("legacy-local".utf8)
        var migratedValue: Data?
        var didReadProduction = false

        let result = LocalBuildKeychainLookup.resolve(
            local: .notFound,
            readLegacyLocal: { legacyLocal },
            migrateLegacyLocal: { migratedValue = $0 },
            readProduction: {
                didReadProduction = true
                return .value(Data("production".utf8))
            }
        )

        #expect(result.value == legacyLocal)
        #expect(migratedValue == legacyLocal)
        #expect(!didReadProduction)
    }

    @Test func unavailableLocalKeychainDoesNotFallBackToProduction() {
        var didReadProduction = false

        let result = LocalBuildKeychainLookup.resolve(
            local: .unavailable(errSecAuthFailed),
            readLegacyLocal: { nil },
            migrateLegacyLocal: { _ in },
            readProduction: {
                didReadProduction = true
                return .value(Data("production".utf8))
            }
        )

        #expect(result.unavailableStatus == errSecAuthFailed)
        #expect(!didReadProduction)
    }
}

private extension KeychainService.ReadResult where Value == Data {
    var value: Data? {
        guard case .value(let value) = self else { return nil }
        return value
    }

    var unavailableStatus: OSStatus? {
        guard case .unavailable(let status) = self else { return nil }
        return status
    }
}
