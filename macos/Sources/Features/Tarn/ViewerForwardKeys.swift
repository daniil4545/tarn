import AppKit
import GhosttyKit

/// Ghostty keybinds of the tab and the window that have no menu item. Ghostty runs them only from a
/// terminal that holds the keyboard (`SurfaceView_AppKit.swift` `performKeyEquivalent`), so while a
/// viewer pane holds it they would die. The viewer runs them on the focused terminal of its tab.
/// Terminal input bindings (`text:`, `csi:`, `jump_to_prompt`, scrolling) stay out: in the viewer the
/// same keys move the cursor of the page.
enum ViewerForwardKeys {
    static let actions: [String] = (1...8).map { "goto_tab:\($0)" } + [
        "last_tab", "previous_tab", "next_tab", "move_tab:-1", "move_tab:1",
        "goto_window:previous", "goto_window:next", "toggle_tab_overview",
        "toggle_maximize", "toggle_window_decorations", "toggle_background_opacity",
    ]

    private typealias Key = Ghostty.MenuShortcutManager.MenuShortcutKey

    /// The action of `actions` that `event` triggers with the keybinds of `config`, the user's own
    /// included. The key is matched as Ghostty's menu matches it (`Ghostty.MenuShortcutManager`):
    /// a physical trigger by the key code, any other by the character.
    @MainActor
    static func action(for event: NSEvent, config: Ghostty.Config) -> String? {
        let physical = Key(physicalKeyCode: event.keyCode, modifiers: event.modifierFlags)
        // The typed key as the menu sees it, and the key without Shift: Cmd+Shift+[ is "[" with Shift,
        // as the trigger has it, not "{". Command stays: it picks the Latin table of a Russian layout,
        // as `Ghostty.keyboardShortcut` does.
        let typed = [
            event.charactersIgnoringModifiers,
            event.characters(byApplyingModifiers: event.modifierFlags.intersection(.command)),
        ].compactMap { $0.flatMap { Key(keyEquivalent: $0, modifiers: event.modifierFlags) } }
        return actions.first { action in
            guard let trigger = config.keybindTrigger(for: action),
                  let shortcut = Ghostty.keyboardShortcut(for: trigger)
            else { return false }
            if trigger.tag == GHOSTTY_TRIGGER_PHYSICAL {
                let code = Ghostty.Input.Key(cKey: trigger.key.physical)?.keyCode
                return code.map { Key(shortcut, physicalKeyCode: $0) } == physical
            }
            return Key(shortcut).map(typed.contains) ?? false
        }
    }
}
