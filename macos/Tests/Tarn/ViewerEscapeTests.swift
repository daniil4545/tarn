import AppKit
import Carbon.HIToolbox
import Testing
@testable import Ghostty

/// Escape belongs to the viewer page (find bar, file tree). The viewer answers Hide Find Bar
/// (`ViewerWebView.findHide`) without menu validation, so it relies on that item carrying no key
/// by default: Ghostty's default `end_search` bindings (Escape, Shift+Cmd+F) are performable, and
/// performable bindings stay out of the menu (`src/input/Binding.zig`, `reverse`).
@Suite
struct ViewerEscapeTests {
    @MainActor @Test func hideFindBarHasNoDefaultKeySoEscapeStaysWithTheViewer() throws {
        let sandbox = try TarnConfigFileTests.Sandbox()
        try sandbox.write("user.conf", "")
        let manager = Ghostty.MenuShortcutManager()
        let item = NSMenuItem(title: "Hide Find Bar", action: nil, keyEquivalent: "")
        manager.syncMenuShortcut(sandbox.config(), action: "end_search", menuItem: item)
        #expect(item.keyEquivalent.isEmpty)

        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
            keyCode: UInt16(kVK_Escape)))
        #expect(!manager.performGhosttyBindingMenuKeyEquivalent(with: escape))
    }
}
