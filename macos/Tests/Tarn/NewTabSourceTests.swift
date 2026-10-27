import AppKit
import Testing
@testable import Ghostty

/// The tab a new tab from the "+" of a workspace header inherits from (Q1 of
/// `docs/plans/workspace-thin-layer.md`, as cmux does).
@Suite
struct NewTabSourceTests {
    private let t = (0..<4).map { _ in TabKey() }

    /// "~" holds t0, "tarn" holds t1 and t2, "notes" is empty.
    private func makeBook() -> (book: WorkspaceBook, tarn: Workspace.ID, notes: Workspace.ID) {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        var tarn: Workspace.ID?
        var notes: Workspace.ID?
        _ = book.edit(t[0]) {
            tarn = $0.create(name: "tarn", folder: "/p/F")
            notes = $0.create(name: "notes", folder: "/p/N")
        }
        _ = book.edit(t[0]) {
            $0.join(t[1], to: tarn!)
            $0.join(t[2], to: tarn!)
        }
        return (book, tarn!, notes!)
    }

    // spec: docs/plans/workspace-thin-layer.md Q1 - the selected tab of that workspace
    @Test func theSelectedTabOfTheWorkspaceIsTheSource() {
        let (book, tarn, _) = makeBook()
        #expect(book.sourceTab(for: tarn, order: Array(t.prefix(3)), selected: t[1]) == t[1])
    }

    // spec: docs/plans/workspace-thin-layer.md Q1 - the focus is in another workspace
    @Test func aSelectedTabElsewhereGivesTheLastTabOfTheWorkspace() {
        let (book, tarn, _) = makeBook()
        #expect(book.sourceTab(for: tarn, order: Array(t.prefix(3)), selected: t[0]) == t[2])
        #expect(book.sourceTab(for: tarn, order: [t[2], t[1], t[0]], selected: t[0]) == t[1])
    }

    // spec: docs/plans/workspace-thin-layer.md Q1 - an empty workspace falls back to Cmd+T
    @Test func anEmptyOrUnknownWorkspaceHasNoSource() {
        let (book, _, notes) = makeBook()
        #expect(book.sourceTab(for: notes, order: Array(t.prefix(3)), selected: t[0]) == nil)
        #expect(book.sourceTab(for: UUID(), order: Array(t.prefix(3)), selected: t[0]) == nil)
    }
}
