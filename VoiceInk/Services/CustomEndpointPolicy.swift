import Foundation

enum CustomEndpointPolicy {
    static func isAllowed(_ endpoint: String) -> Bool {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            let host = components.host?.lowercased(),
            !host.isEmpty,
            components.user == nil,
            components.password == nil
        else {
            return false
        }

        if scheme == "https" {
            return true
        }

        guard scheme == "http" else { return false }
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return normalizedHost == "localhost" || normalizedHost == "127.0.0.1" || normalizedHost == "::1"
    }

    static func validatedURL(_ endpoint: String) -> URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAllowed(trimmed) else { return nil }
        return URL(string: trimmed)
    }
}
