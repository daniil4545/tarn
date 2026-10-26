import AppKit
import Carbon.HIToolbox
import Testing
@testable import Ghostty
import GhosttyKit

/// The tab and window keybinds a viewer pane passes to its terminal, and the keys it keeps
/// (`docs/specs/viewer-pane.md`).
@Suite
struct ViewerForwardKeysTests {
    private static let cmd = NSEvent.ModifierFlags.command.rawValue
    private static let shift = NSEvent.ModifierFlags.shift.rawValue

    private func event(_ characters: String, _ keyCode: Int, _ flags: UInt) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
            timestamp: 1, windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode))!
    }

    @MainActor private func config(_ user: String = "") throws -> Ghostty.Config {
        let sandbox = try TarnConfigFileTests.Sandbox()
        try sandbox.write("user.conf", user)
        return sandbox.config()
    }

    @Test(arguments: [
        ("1", kVK_ANSI_1, cmd, "goto_tab:1"), ("8", kVK_ANSI_8, cmd, "goto_tab:8"), ("9", kVK_ANSI_9, cmd, "last_tab"),
        ("{", kVK_ANSI_LeftBracket, cmd | shift, "previous_tab"), ("}", kVK_ANSI_RightBracket, cmd | shift, "next_tab"),
    ])
    @MainActor func tabKeysGoToTheTerminal(characters: String, keyCode: Int, flags: UInt, action: String) throws {
        #expect(ViewerForwardKeys.action(for: event(characters, keyCode, flags), config: try config()) == action)
    }

    /// Menu keys, page keys and terminal input stay with the viewer: copy, the page cursor, Cmd+B.
    @Test(arguments: [
        ("c", kVK_ANSI_C, cmd), ("\u{F702}", kVK_LeftArrow, cmd), ("b", kVK_ANSI_B, cmd), ("1", kVK_ANSI_1, 0),
    ])
    @MainActor func otherKeysStayInTheViewer(characters: String, keyCode: Int, flags: UInt) throws {
        #expect(ViewerForwardKeys.action(for: event(characters, keyCode, flags), config: try config()) == nil)
    }

    @Test @MainActor func theUsersOwnKeybindWins() throws {
        let config = try config("keybind = ctrl+t=goto_tab:2\n")
        let ctrl = NSEvent.ModifierFlags.control.rawValue
        #expect(ViewerForwardKeys.action(for: event("t", kVK_ANSI_T, ctrl), config: config) == "goto_tab:2")
    }
}
