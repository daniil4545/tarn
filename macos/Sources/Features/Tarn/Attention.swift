import Foundation
import OSLog
import UserNotifications

/// What a session needs from the user, in the words of `docs/spec.md` section 11.
enum AgentNeed: Equatable {
    case waiting, permission, failed

    var body: String {
        switch self {
        case .permission: "Needs your permission"
        case .waiting: "Waiting for you"
        case .failed: "Failed, see the session"
        }
    }
}

extension AgentSession {
    var need: AgentNeed? {
        switch state {
        case .permission: .permission
        case .waiting: failed ? .failed : .waiting
        case .idle, .working: nil
        }
    }
}

/// Notifications of `docs/spec.md` R4: one per need, through Ghostty's own route, never for
/// a surface the user looks at. The gate is pure; the registry feeds it.
enum Attention {
    private static let logger = Logger(subsystem: "tarn", category: "attention")

    /// A note longer than this is cut: it is shown in a banner and in `tarn ls`.
    static let maxNote = 500

    /// Replaced by tests; the default shows the notification through Ghostty (insertion point 21).
    @MainActor static var deliver: (Ghostty.SurfaceView, _ title: String, _ body: String) -> Void = { view, title, body in
        Ghostty.App.showDesktopNotification(view, title: title, body: body)
    }

    // MARK: Gate

    /// The body to raise when `new` entered a need `old` did not have. The same state repeated
    /// raises nothing; a new permission request counts as a new need, because approving in
    /// the terminal sends no event (`docs/spec.md` section 8, known limit). `seen` is false
    /// only when the user was not looking at the surface at the change.
    static func body(old: AgentSession, new: AgentSession, focused: Bool) -> String? {
        guard let need = new.need, !focused, !new.seen else { return nil }
        let isNew = need != old.need || (need == .permission && new.request != old.request)
        return isNew ? need.body : nil
    }

    /// `text` trimmed and cut to `maxNote`; empty when there is nothing to say.
    static func trimmed(note text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > maxNote ? String(trimmed.prefix(maxNote - 1)) + "…" : trimmed
    }

    /// Terminal notifications (OSC 9, 777) of a surface with a live agent session are dropped:
    /// tarn names the project and the need (`docs/spec.md` section 12).
    @MainActor
    static func suppresses(_ view: Ghostty.SurfaceView) -> Bool {
        guard let session = SessionRegistry.shared.sessions[view.id] else { return false }
        return !session.agentSessionID.isEmpty
    }

    // MARK: Delivery

    @MainActor
    static func consider(old: AgentSession, new: AgentSession, view: Ghostty.SurfaceView) {
        guard let body = body(old: old, new: new, focused: SessionRegistry.isFocused(view)) else { return }
        raise(view: view, body: body)
    }

    @MainActor
    static func raise(view: Ghostty.SurfaceView, body: String) {
        let title = ProjectInfo.resolve(cwd: view.pwd).name
        logger.info("raised for \(view.id, privacy: .public)")
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus != .authorized {
                logger.info("notifications are not authorized; the sidebar still marks the session")
            }
        }
        deliver(view, title, body)
    }
}
