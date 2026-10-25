import AppKit

/// The workspace name in the window's subtitle (Q4, Q10). The title stays Ghostty's.
enum WorkspaceTitle {
    /// The subtitle for a tab in `workspace`. Empty with the top tab bar: there the workspaces
    /// are not shown (D14, S22).
    static func subtitle(workspace: String?, style: TabStyle) -> String {
        style == .sidebar ? workspace ?? "" : ""
    }

    /// Sets the subtitle of a tab window; writes only a change, because the title observers of
    /// `TerminalWindow` refresh the sidebar again.
    @MainActor
    static func apply(to window: NSWindow, style: TabStyle = .current) {
        let text = subtitle(workspace: WorkspaceRegistry.shared.workspace(of: window)?.name, style: style)
        if window.subtitle != text { window.subtitle = text }
    }
}
