import AppKit
import Foundation
import SwiftUI

@MainActor
struct EmailSupport {
    private static let supportEmailAddress = "jackie@tellustek.com"
    private static let supportEmailSubject = "Wa-Gong Support Request"

    static func generateSupportEmailBody() -> String {
        let systemInfo = SystemInfoService.shared.getSystemInfoString()

        return """

            ------------------------
            ✨ **SCREEN RECORDING HIGHLY RECOMMENDED** ✨
            ▶️ Create a quick screen recording showing the issue!
            ▶️ It helps me understand and fix the problem much faster.

            📝 ISSUE DETAILS:
            - What steps did you take before the issue occurred?
            - What did you expect to happen?
            - What actually happened instead?


            ## 📋 常見問題：
            寄出郵件前，可先檢視 Wa-Gong 的 GitHub Issues： https://github.com/q0821/wa-gong-macos/issues
            ------------------------

            System Information:
            \(systemInfo)


            """
    }

    static func generateSupportEmailURL() -> URL? {
        let encodedSubject = supportEmailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(supportEmailAddress)?subject=\(encodedSubject)")
    }

    static func openSupportEmail() {
        let body = generateSupportEmailBody()

        if let sharingService = NSSharingService(named: .composeEmail) {
            sharingService.recipients = [supportEmailAddress]
            sharingService.subject = supportEmailSubject
            sharingService.perform(withItems: [body])
            return
        }

        SystemInfoService.shared.copySystemInfoToClipboard()

        if let emailURL = generateSupportEmailURL() {
            NSWorkspace.shared.open(emailURL)
        }
    }
}
