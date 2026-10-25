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
        SessionRegistry.shared.suppresses(view.id)
    }

    // MARK: Notes

    /// What `tarn notify` does to a session.
    struct NoteChange: Equatable {
        let session: AgentSession
        /// Raise a banner: only for the first note since the user last focused the surface.
        let raise: Bool
    }

    /// The effect of `note` (already trimmed, not empty) on `old`, or nil when nothing changes:
    /// the user looks at the surface, or the text is the current note. While a note is
    /// unseen a new text replaces it without a new banner and sound (one banner per
    /// surface per need; `docs/spec.md` 2.4); after the user focuses the surface the next
    /// note banners again.
    static func note(_ note: String, on old: AgentSession, focused: Bool, now: Date) -> NoteChange? {
        guard !focused, note != old.note else { return nil }
        var session = old
        let first = old.note.isEmpty
        session.note = note
        if first { session.noteSince = now }
        return NoteChange(session: session, raise: first)
    }

    /// The banner title: the project name of the surface's working directory.
    static func title(cwd: String?) -> String { ProjectInfo.resolve(cwd: cwd).name }

    // MARK: Delivery

    /// Shows the notification through Ghostty's route (insertion point 21).
    @MainActor
    static func show(surface id: UUID, title: String, body: String) {
        guard let view = SessionRegistry.surfaceView(id) else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus != .authorized {
                logger.info("notifications are not authorized; the sidebar still marks the session")
            }
        }
        Ghostty.App.showDesktopNotification(view, title: title, body: body)
    }
}
