import AppKit
import ApplicationServices
import OSLog

/// Deliberately AX-only: never copies, reads the clipboard or invokes fallback automation.
@MainActor enum VocabularySelectionCapture {
    struct Result {
        var word = ""
        let message: String
    }

    static func capture() -> Result {
        guard AXIsProcessTrusted() else {
            return .init(message: String(localized: "Selection needs Accessibility access. You can still type a term here."))
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return unavailable()
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard AXUIElementSetMessagingTimeout(application, 0.2) == .success else { return unavailable() }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return unavailable() }
        let element = focused as! AXUIElement
        guard AXUIElementSetMessagingTimeout(element, 0.2) == .success else { return unavailable() }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else { return unavailable() }
        // Require a readable subrole before reading selected text, failing closed for secure/unknown fields.
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
              let subrole = subrole as? String, subrole != kAXSecureTextFieldSubrole as String else {
            return unavailable()
        }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let selected = selected as? String,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return unavailable() }
        do {
            return .init(word: try VocabularyLearningService.term(selected),
                         message: String(localized: "Selected text is ready. Press Return to add it, or Escape to cancel."))
        } catch {
            return .init(message: String(localized: "Select one short term without commas or line breaks, or type it here."))
        }
    }

    private static func unavailable() -> Result {
        Logger(subsystem: "com.jackie-yeh.wagong", category: "VocabularySelection").debug("Selected term unavailable; manual entry remains available")
        return .init(message: String(localized: "No readable selection. Type a term here; your clipboard was not used."))
    }
}
