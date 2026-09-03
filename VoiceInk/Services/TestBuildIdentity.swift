import Foundation

struct TestBuildIdentity: Equatable, Sendable {
    static let buildIDKey = "WaGongBuildID"
    static let buildChannelKey = "WaGongBuildChannel"
    static let sourceFingerprintKey = "WaGongSourceFingerprint"
    static let sourceRevisionKey = "WaGongSourceRevision"
    static let sourceStateKey = "WaGongSourceState"
    static let buildTimestampKey = "WaGongBuildTimestamp"
    static let receiptArgument = "--test-build-receipt"

    let buildID: String
    let channel: String
    let sourceFingerprint: String
    let sourceRevision: String
    let sourceState: String
    let buildTimestamp: String

    init?(infoDictionary: [String: Any]) {
        guard
            let buildID = Self.nonemptyString(for: Self.buildIDKey, in: infoDictionary),
            let channel = Self.nonemptyString(for: Self.buildChannelKey, in: infoDictionary),
            let sourceFingerprint = Self.nonemptyString(for: Self.sourceFingerprintKey, in: infoDictionary),
            let sourceRevision = Self.nonemptyString(for: Self.sourceRevisionKey, in: infoDictionary),
            let sourceState = Self.nonemptyString(for: Self.sourceStateKey, in: infoDictionary),
            let buildTimestamp = Self.nonemptyString(for: Self.buildTimestampKey, in: infoDictionary)
        else {
            return nil
        }

        self.buildID = buildID
        self.channel = channel
        self.sourceFingerprint = sourceFingerprint
        self.sourceRevision = sourceRevision
        self.sourceState = sourceState
        self.buildTimestamp = buildTimestamp
    }

    static var current: TestBuildIdentity? {
        guard let infoDictionary = Bundle.main.infoDictionary else {
            return nil
        }
        return TestBuildIdentity(infoDictionary: infoDictionary)
    }

    var badgeLabel: String {
        "TEST \(sourceFingerprint.prefix(8).uppercased())"
    }

    static func requestedReceiptURL(arguments: [String]) -> URL? {
        guard
            let argumentIndex = arguments.firstIndex(of: receiptArgument),
            arguments.indices.contains(argumentIndex + 1)
        else {
            return nil
        }

        let path = arguments[argumentIndex + 1]
        guard !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    func writeLaunchReceiptIfRequested(
        arguments: [String] = CommandLine.arguments,
        bundle: Bundle = .main,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        fileManager: FileManager = .default
    ) throws {
        guard let receiptURL = Self.requestedReceiptURL(arguments: arguments) else {
            return
        }

        let receipt = TestBuildLaunchReceipt(
            buildID: buildID,
            sourceFingerprint: sourceFingerprint,
            bundleIdentifier: bundle.bundleIdentifier ?? "",
            bundlePath: bundle.bundleURL.path,
            executablePath: bundle.executableURL?.path ?? "",
            processIdentifier: processIdentifier,
            launchedAt: Self.timestamp()
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(receipt)

        try fileManager.createDirectory(
            at: receiptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: receiptURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receiptURL.path)
    }

    private static func nonemptyString(for key: String, in dictionary: [String: Any]) -> String? {
        guard let value = dictionary[key] as? String else {
            return nil
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !trimmedValue.contains("$(") else {
            return nil
        }
        return trimmedValue
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

struct TestBuildLaunchReceipt: Codable, Equatable, Sendable {
    let buildID: String
    let sourceFingerprint: String
    let bundleIdentifier: String
    let bundlePath: String
    let executablePath: String
    let processIdentifier: Int32
    let launchedAt: String
}
