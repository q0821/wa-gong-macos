import Foundation

enum LocalSpeechModelFilter: String, CaseIterable, Identifiable {
    case chinese
    case installed
    case all

    var id: String { rawValue }

    init(storedValue: String) {
        self = Self(rawValue: storedValue) ?? .chinese
    }

    var title: String {
        switch self {
        case .chinese: return String(localized: "Supports Chinese")
        case .installed: return String(localized: "Installed speech models")
        case .all: return String(localized: "All speech models")
        }
    }

    func includes(_ model: any TranscriptionModel, isInstalled: Bool) -> Bool {
        switch self {
        case .chinese: return model.supportsChinese
        case .installed: return isInstalled
        case .all: return true
        }
    }
}
