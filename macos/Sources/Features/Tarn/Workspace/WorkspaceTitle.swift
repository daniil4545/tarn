import AppKit

/// The workspace name in the window's subtitle. The title stays Ghostty's.
enum WorkspaceTitle {
    /// The subtitle for a tab in `workspace`, whatever the tab style. Empty while Workspaces is off.
    static func subtitle(workspace: String?, workspacesOn: Bool) -> String {
        workspacesOn ? workspace ?? "" : ""
    }

    /// Sets the subtitle of a tab window; writes only a change, because the title observers of
    /// `TerminalWindow` refresh the sidebar again.
    @MainActor
    static func apply(to window: NSWindow, workspacesOn: Bool = TarnModules.isOn(.workspaces)) {
        let text = subtitle(workspace: WorkspaceRegistry.shared.workspace(of: window)?.name, workspacesOn: workspacesOn)
        if window.subtitle != text { window.subtitle = text }
    }
}
