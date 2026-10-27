// The ordered list with a cursor that steps to the entry after the focused one follows
// Limpid `AttentionState.swift` (`attentionTargets`, `jumpToAttention`) at 327e41d3c087
// (MIT, nek0der). The order itself is `docs/spec.md` section 8; see THIRD_PARTY.md.

import AppKit

/// Cmd+U: focus the next session that needs the user (`docs/spec.md` R4).
enum AttentionJump {
    /// Sessions that need the user, most urgent first: `failed`, then `permission`, then
    /// `waiting` or a note. Inside a group unseen sessions come first, then the one that
    /// has waited longest. Sessions in `idle` or `working` without a note are skipped.
    static func order(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions
            .filter { $0.need != nil || !$0.note.isEmpty }
            .sorted { a, b in
                if group(a) != group(b) { return group(a) < group(b) }
                if unseen(a) != unseen(b) { return unseen(a) }
                if waiting(a) != waiting(b) { return waiting(a) < waiting(b) }
                return a.surfaceID.uuidString < b.surfaceID.uuidString
            }
    }

    /// The entry after the focused one in `ordered`, wrapping around; the first entry when the
    /// focused surface is not in the list. Nil when there is nothing but the focused one.
    static func next(in ordered: [AgentSession], focused: UUID?) -> AgentSession? {
        guard !ordered.isEmpty else { return nil }
        guard let focused, let index = ordered.firstIndex(where: { $0.surfaceID == focused }) else {
            return ordered[0]
        }
        let target = ordered[(index + 1) % ordered.count]
        return target.surfaceID == focused ? nil : target
    }

    private static func group(_ session: AgentSession) -> Int {
        switch session.need {
        case .failed: 0
        case .permission: 1
        case .waiting, nil: 2
        }
    }

    /// A note stays unseen until the surface is focused, which also clears it.
    private static func unseen(_ session: AgentSession) -> Bool {
        !session.seen || !session.note.isEmpty
    }

    private static func waiting(_ session: AgentSession) -> Date {
        session.need == nil ? session.noteSince : session.since
    }

    @MainActor
    static func perform() {
        guard TarnModules.isOn(.notifications) else { return }
        let registry = SessionRegistry.shared
        let live = registry.liveSessions()
        let focusedID = (NSApp.keyWindow?.windowController as? BaseTerminalController)?.focusedSurface?.id
        guard let target = next(in: order(live.map(\.session)), focused: focusedID),
              let view = live.first(where: { $0.session.surfaceID == target.surfaceID })?.view,
              let controller = view.window?.windowController as? BaseTerminalController
        else {
            NSSound.beep()
            return
        }
        controller.focusSurface(view)
    }
}

extension BaseTerminalController {
    /// The Window menu item "Jump to Waiting Session" (Cmd+U), found through the responder chain.
    @IBAction func jumpToWaitingSession(_ sender: Any?) {
        AttentionJump.perform()
    }
}
