import AppKit
import Foundation

enum ExternalURLPolicy {
    static func validatedHTTPSURL(_ url: URL?) -> URL? {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host,
              !host.isEmpty else { return nil }
        return url
    }

    @MainActor
    static func confirmAndOpen(_ candidate: URL) -> Bool {
        guard let url = validatedHTTPSURL(candidate), let host = url.host else { return false }
        let alert = NSAlert()
        alert.messageText = String(localized: "Open external link?")
        alert.informativeText = String(
            format: String(localized: "This link will open in your browser.\n\nHost: %@\nURL: %@"),
            host,
            url.absoluteString
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Open"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return NSWorkspace.shared.open(url)
    }
}
