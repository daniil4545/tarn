import AppKit
import Carbon.HIToolbox
import Testing
import WebKit
@testable import Ghostty

@Suite(.serialized)
@MainActor
struct ViewerClipboardTests {
    @Test(arguments: [
        "<input id='field'>", "<div id='field' contenteditable='true'></div>",
        "<article id='field' tabindex='0'>clipboard regression</article>",
    ])
    func pasteReachesTheFocusedWebFieldWithoutAMenuShortcut(html: String) async throws {
        let view = ViewerWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        view.loadHTMLString(html + "<script>window.tarn={paste(text){document.execCommand('insertText',false,text)}}</script>", baseURL: nil)
        // A cold WebKit process on CI takes over 10 s to load; the paste itself gets its own wait.
        let loaded = ContinuousClock.now + .seconds(60)
        while view.isLoading || view.url == nil {
            guard ContinuousClock.now < loaded else { throw CancellationError() }
            await Task.yield()
        }
        let deadline = ContinuousClock.now + .seconds(10)
        window.makeFirstResponder(view)
        _ = try await view.evaluateJavaScript("document.getElementById('field').focus()")
        let board = NSPasteboard.general
        let saved = board.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            board.clearContents()
            board.writeObjects(saved.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            })
        }
        board.clearContents()
        board.setString("clipboard regression", forType: .string)
        let key = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 1,
            windowNumber: window.windowNumber, context: nil, characters: "v",
            charactersIgnoringModifiers: "v", isARepeat: false, keyCode: UInt16(kVK_ANSI_V)))
        if !html.hasPrefix("<article") { #expect(view.performKeyEquivalent(with: key)) }
        var value: String?
        repeat {
            value = try await view.evaluateJavaScript(
                "document.getElementById('field').value ?? document.getElementById('field').textContent") as? String
            await Task.yield()
        } while value != "clipboard regression" && ContinuousClock.now < deadline
        #expect(value == "clipboard regression")
        _ = try await view.evaluateJavaScript("document.execCommand('selectAll')")
        let copy = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 2,
            windowNumber: window.windowNumber, context: nil, characters: "c",
            charactersIgnoringModifiers: "c", isARepeat: false, keyCode: UInt16(kVK_ANSI_C)))
        board.clearContents()
        #expect(view.performKeyEquivalent(with: copy))
        while board.string(forType: .string) == nil && ContinuousClock.now < deadline { await Task.yield() }
        #expect(board.string(forType: .string) == "clipboard regression")
    }

    @Test(arguments: [("c", "copy:"), ("v", "paste:"), ("x", "cut:"), ("a", "selectAll:"), ("z", "undo:")])
    func editKeysHaveNativeActions(key: String, action: String) {
        #expect(ViewerWebView.editAction(characters: key, flags: .command) == Selector(action))
        #expect(ViewerWebView.editAction(characters: key, flags: [.command, .option]) == nil)
        #expect(ViewerWebView.editAction(characters: key, flags: []) == nil)
    }
}
