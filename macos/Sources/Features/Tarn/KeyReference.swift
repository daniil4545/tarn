import SwiftUI

/// The keys Help lists. Ghostty has no call that lists all bindings, so this is a fixed list of
/// actions; Ghostty gives the trigger in effect for each one (`docs/plans/s4-settings.md` 1.3).
/// Actions bound with `performable` (undo, clear_screen, start_search, navigate_search) are not
/// listed: Ghostty leaves them out of the reverse lookup, so it reports no trigger for them.
enum KeyReference {
    struct Row: Identifiable {
        let label: String
        /// The Ghostty action name as in `keybind = key=action`; nil for a tarn key.
        let action: String?
        /// The key text of a tarn key, which Ghostty does not bind.
        let fixedKeys: String?

        var id: String { action ?? label }
        var source: String { action == nil ? "tarn" : "Ghostty" }

        init(_ label: String, action: String) {
            self.label = label
            self.action = action
            fixedKeys = nil
        }

        init(_ label: String, keys: String) {
            self.label = label
            action = nil
            fixedKeys = keys
        }
    }

    struct Group: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    /// Shown instead of keys for an action without a binding.
    static let notBound = "not bound"

    static let groups: [Group] = [
        Group(title: "Tabs and windows", rows: [
            Row("New tab in the current workspace", action: "new_tab"),
            Row("New window with Default", action: "new_window"),
            Row("Close the pane; the last one closes the tab", action: "close_surface"),
            Row("Close the tab", action: "close_tab"),
            Row("Close the window", action: "close_window"),
            Row("Go to tab 1, down the sidebar (2 to 8 likewise)", action: "goto_tab:1"),
            Row("Go to the last tab", action: "last_tab"),
            Row("Previous tab", action: "previous_tab"),
            Row("Next tab", action: "next_tab"),
            Row("Full screen", action: "toggle_fullscreen"),
        ]),
        Group(title: "Splits", rows: [
            Row("Split right", action: "new_split:right"),
            Row("Split down", action: "new_split:down"),
            Row("Previous split", action: "goto_split:previous"),
            Row("Next split", action: "goto_split:next"),
            Row("Focus the split above", action: "goto_split:up"),
            Row("Focus the split below", action: "goto_split:down"),
            Row("Focus the split on the left", action: "goto_split:left"),
            Row("Focus the split on the right", action: "goto_split:right"),
            Row("Resize the split up", action: "resize_split:up,10"),
            Row("Resize the split down", action: "resize_split:down,10"),
            Row("Resize the split left", action: "resize_split:left,10"),
            Row("Resize the split right", action: "resize_split:right,10"),
            Row("Equalize splits", action: "equalize_splits"),
            Row("Zoom the split", action: "toggle_split_zoom"),
        ]),
        Group(title: "Terminal", rows: [
            Row("Font size bigger", action: "increase_font_size:1"),
            Row("Font size smaller", action: "decrease_font_size:1"),
            Row("Font size reset", action: "reset_font_size"),
            Row("Jump to the previous prompt", action: "jump_to_prompt:-1"),
            Row("Jump to the next prompt", action: "jump_to_prompt:1"),
            Row("Command palette", action: "toggle_command_palette"),
            Row("Reload the Ghostty config", action: "reload_config"),
            Row("Settings", action: "open_config"),
        ]),
        Group(title: "Viewer", rows: ViewerWebView.keyTable.map { Row($0.help, keys: "⌘\($0.key.uppercased())") }
            + [Row("Close the file tab", keys: "⌘W")]),
    ]

    /// The key text in effect for a row, or `notBound` when Ghostty has no trigger for the action.
    @MainActor
    static func keys(for row: Row, in config: Ghostty.Config?) -> String {
        if let fixedKeys = row.fixedKeys { return fixedKeys }
        guard let action = row.action,
              let shortcut = config?.keyboardShortcut(for: action) else { return notBound }
        return shortcut.keyList.joined()
    }
}
