import Foundation
import Combine

enum TEARuntimePhase: String, Sendable {
    case idle, preparing, loading, ready, recognizing, delivering, failed

    static let notification = Notification.Name("TEARuntimePhaseChanged")
    func publish() {
        NotificationCenter.default.post(name: Self.notification, object: nil, userInfo: ["phase": rawValue])
    }
}

/// Metadata only; never contains audio, transcript, path or request headers.
final class TEARuntimeActivity: ObservableObject {
    static let shared = TEARuntimeActivity()
    @Published private(set) var phase: TEARuntimePhase = .idle
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: TEARuntimePhase.notification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?["phase"] as? String, let phase = TEARuntimePhase(rawValue: raw) else { return }
            self?.phase = phase
        }
    }
}
