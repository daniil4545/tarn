import AppKit

/// `tarn close <pane>`: closes a pane at once, with no confirmation, whatever runs in it
/// (`docs/specs/agent-cli.md` 4.8). Follows WezTerm `kill-pane` and herdr `pane close`. Which panes
/// an agent may close is a rule of the skill, not a check here.
enum ClosePane {
    static let unsavedEdits = AgentRefusal(text: "unsaved viewer edits")

    @MainActor
    static func run(_ message: [String: Any], _ scope: AgentScope) -> Result<[String: Any], AgentRefusal> {
        scope.pane(message["pane"] as? String).flatMap { row in
            guard let view = SessionRegistry.surfaceView(row.pane),
                  let controller = BaseTerminalController.controller(owning: view)
            else { return .failure(.noPane(row.pane.uuidString)) }
            if holdsUnsavedEdits(controller) { return .failure(unsavedEdits) }
            close(view, in: controller)
            return .success([:])
        }
    }

    /// The last pane of a tab whose viewer has unsaved edits: its close would put the Save sheet
    /// (`ViewerClose.intercept`) on the user's window, so the agent is refused instead.
    @MainActor
    static func holdsUnsavedEdits(_ controller: BaseTerminalController) -> Bool {
        guard let terminal = controller as? TerminalController, Array(terminal.surfaceTree).count == 1 else { return false }
        return !ViewerClose.dirtyPaths(in: terminal.viewerHost.models).isEmpty
    }

    /// Ghostty's close without the alert. A wait on the pane answers `closed` through the
    /// `surfaceTreeDidChange` insertion point, or the window close for the last pane of a tab.
    /// Ghostty refocuses its last focused surface; the first responder it had is given back.
    @MainActor
    static func close(_ view: Ghostty.SurfaceView, in controller: BaseTerminalController) {
        let window = controller.window
        let responder = window?.firstResponder
        controller.closeSurface(view, withConfirmation: false)
        guard let responder, responder !== view, responder !== window else { return }
        NewPane.keep(responder, in: window)
    }
}
