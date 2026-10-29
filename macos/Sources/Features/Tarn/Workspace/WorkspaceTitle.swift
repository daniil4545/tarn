import AppKit

/// The workspace name in the window's subtitle. The title stays Ghostty's.
enum WorkspaceTitle {
    /// The subtitle for a tab in `workspace`, whatever the tab style.
    static func subtitle(workspace: String?) -> String {
        workspace ?? ""
    }

    /// Sets the subtitle of a tab window; writes only a change, because the title observers of
    /// `TerminalWindow` refresh the sidebar again.
    @MainActor
    static func apply(to window: NSWindow) {
        let text = subtitle(workspace: WorkspaceRegistry.shared.workspace(of: window)?.name)
        if window.subtitle != text { window.subtitle = text }
    }
}
