import AppKit
import Testing
@testable import Ghostty

@Suite
@MainActor
struct FinderRevealTests {
    @Test func selectionResolvesWithoutRequiringAViewerSupportedType() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a file.pdf")
        try Data([0, 1, 2]).write(to: file)
        #expect(FinderReveal.file("a file.pdf:12:3", cwd: dir.path) == file)
        #expect(FinderReveal.file(file.absoluteString, cwd: nil) == file)
        #expect(FinderReveal.file("missing", cwd: dir.path) == nil)
        #expect(FinderReveal.file("https://example.com/a.pdf", cwd: dir.path) == nil)
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "")
        FinderReveal.add(to: menu, file: file)
        #expect(menu.items.first?.title == "Copy")
        let item = try #require(menu.items.last)
        #expect(item.title == "Show in Finder")
        #expect(item.target != nil)
        #expect(item.representedObject as AnyObject? === item.target)
        let empty = NSMenu()
        FinderReveal.add(to: empty, file: nil)
        #expect(empty.items.isEmpty)
    }
}
