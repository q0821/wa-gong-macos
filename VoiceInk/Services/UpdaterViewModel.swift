import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
final class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    struct AvailableUpdate: Equatable {
        let versionIdentifier: String
        let displayVersion: String
    }

    private enum DefaultsKey {
        static let automaticUpdateChecks = "WaGongChecksForUpdatesOnLaunch"
        static let interactedUpdateVersions = "WaGongInteractedUpdateVersions"
        static let legacyAutomaticUpdateChecks = "VoiceInkChecksForUpdatesOnLaunch"
        static let legacyInteractedUpdateVersions = "VoiceInkInteractedUpdateVersions"
        static let sparkleAutomaticChecks = "SUEnableAutomaticChecks"
    }

    // Wa-Gong does not have a public Sparkle feed yet. Keep the updater package available,
    // but do not probe or advertise the old upstream feed.
    private static let hasConfiguredUpdateFeed = false

    private let defaults: UserDefaults
    private var isUserInitiatedUpdateCheck = false
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    @Published var canCheckForUpdates = false
    @Published private(set) var checksForUpdatesWhenDashboardAppears = false
    @Published private(set) var availableUpdate: AvailableUpdate?

    override init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        checksForUpdatesWhenDashboardAppears = Self.initialAutomaticCheckPreference(in: defaults)
        super.init()

        let updater = updaterController.updater

        // Wa-Gong owns automatic discovery through Sparkle's non-presenting probe.
        // Keeping Sparkle's scheduler disabled prevents it from showing an update
        // window independently of the Dashboard button.
        updater.automaticallyChecksForUpdates = false
        updaterController.startUpdater()

        canCheckForUpdates = Self.hasConfiguredUpdateFeed && updater.canCheckForUpdates
        updater.publisher(for: \.canCheckForUpdates)
            .map { Self.hasConfiguredUpdateFeed && $0 }
            .assign(to: &$canCheckForUpdates)
    }

    func setChecksForUpdatesWhenDashboardAppears(_ value: Bool) {
        guard checksForUpdatesWhenDashboardAppears != value else { return }

        checksForUpdatesWhenDashboardAppears = value
        defaults.set(value, forKey: DefaultsKey.automaticUpdateChecks)

        if value {
            checkForUpdateInformationIfPossible()
        } else {
            availableUpdate = nil
        }
    }

    func checkForUpdatesIfDue() {
        guard checksForUpdatesWhenDashboardAppears else { return }

        let updater = updaterController.updater
        guard !updater.sessionInProgress else { return }

        if let lastCheckDate = updater.lastUpdateCheckDate {
            let elapsed = Date().timeIntervalSince(lastCheckDate)
            guard elapsed < 0 || elapsed >= updater.updateCheckInterval else { return }
        }

        checkForUpdateInformationIfPossible()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }

        // Any explicit check is interaction with the currently advertised update.
        // Persist it before presenting Sparkle so dismissing or closing the native
        // window cannot make the Dashboard button reappear for the same build.
        if let availableUpdate {
            rememberInteraction(with: availableUpdate.versionIdentifier)
            self.availableUpdate = nil
        }

        if !updaterController.updater.sessionInProgress {
            isUserInitiatedUpdateCheck = true
        }
        updaterController.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let update = AvailableUpdate(
            versionIdentifier: item.versionString,
            displayVersion: item.displayVersionString
        )

        if isUserInitiatedUpdateCheck {
            rememberInteraction(with: update.versionIdentifier)
            availableUpdate = nil
        } else if checksForUpdatesWhenDashboardAppears && !hasInteracted(with: update.versionIdentifier) {
            availableUpdate = update
        } else {
            availableUpdate = nil
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableUpdate = nil
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        isUserInitiatedUpdateCheck = false
    }

    private func checkForUpdateInformationIfPossible() {
        guard Self.hasConfiguredUpdateFeed else { return }
        let updater = updaterController.updater
        guard !updater.sessionInProgress else { return }
        updater.checkForUpdateInformation()
    }

    private func hasInteracted(with versionIdentifier: String) -> Bool {
        interactedUpdateVersions
            .contains(versionIdentifier) == true
    }

    private func rememberInteraction(with versionIdentifier: String) {
        var versions = interactedUpdateVersions
        guard !versions.contains(versionIdentifier) else { return }
        versions.append(versionIdentifier)
        defaults.set(versions, forKey: DefaultsKey.interactedUpdateVersions)
    }

    private var interactedUpdateVersions: [String] {
        let current = defaults.stringArray(forKey: DefaultsKey.interactedUpdateVersions) ?? []
        let legacy = defaults.stringArray(forKey: DefaultsKey.legacyInteractedUpdateVersions) ?? []
        return Array(Set(current + legacy)).sorted()
    }

    private static func initialAutomaticCheckPreference(in defaults: UserDefaults) -> Bool {
        if let preference = defaults.object(forKey: DefaultsKey.automaticUpdateChecks) as? Bool {
            return preference
        }

        let preference =
            (defaults.object(forKey: DefaultsKey.legacyAutomaticUpdateChecks) as? Bool)
            ?? (defaults.object(forKey: DefaultsKey.sparkleAutomaticChecks) as? Bool)
            ?? true

        defaults.set(preference, forKey: DefaultsKey.automaticUpdateChecks)
        return preference
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}
