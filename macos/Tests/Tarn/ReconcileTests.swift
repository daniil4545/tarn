import Foundation
import Testing
@testable import Ghostty

/// Following a tab order Ghostty changed: membership never follows the order
/// (`docs/specs/workspace-folder.md` M3), and a tab no rule placed is ungrouped (M1).
@Suite
struct ReconcileTests {
    private let t = (0..<5).map { _ in TabKey() }

    /// A: t0 t1; B: t2 t3.
    private func twoWorkspaces() -> WorkspaceBook {
        var book = WorkspaceBook()
        _ = book.pass([Array(t[0...3])])
        book.group("A", [t[0], t[1]])
        book.group("B", [t[2], t[3]])
        return book
    }

    /// spec: docs/specs/workspace-folder.md S60
    @Test func aNativeReorderChangesNoMembership() {
        var book = twoWorkspaces()
        let before = book.set(of: t[0])
        for order in [[t[1], t[2], t[0], t[3]], [t[3], t[0], t[1], t[2]], [t[2], t[0], t[3], t[1]]] {
            _ = book.pass([order])
        }
        #expect(book.set(of: t[0]) == before)
        #expect(book.workspace(of: t[0])?.name == "A")
        #expect(book.workspace(of: t[3])?.name == "B")
    }

    /// spec: docs/specs/workspace-folder.md S40
    @Test func aNewWindowIsOneUngroupedTabWithNoGroupAtAll() {
        var book = WorkspaceBook()
        let outcome = book.pass([[t[0]]])
        #expect(outcome.changed.count == 1)
        #expect(book.set(of: t[0])?.workspaces.isEmpty == true)
        #expect(book.workspace(of: t[0]) == nil)
        #expect(book.runs(for: [t[0]]).map(\.workspace) == [nil])
        #expect(book.runs(for: [t[0]]).map(\.tabs) == [[t[0]]])
    }

    @Test func anUnannouncedTabIsUngroupedWhereverGhosttyPutIt() {
        var book = twoWorkspaces()
        _ = book.pass([[t[0], t[4], t[1], t[2], t[3]]])
        #expect(book.workspace(of: t[4]) == nil)
        #expect(book.set(of: t[4])?.id == book.set(of: t[0])?.id)
        #expect(book.set(of: t[0])?.workspaces.count == 2)
    }

    /// A set lives while it has a tab, not while it has a group.
    @Test func aSetOfUngroupedTabsOutlivesItsLastGroup() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        book.group("A", [t[1]])
        _ = book.closing(t[1])
        #expect(book.set(of: t[0]) != nil)
        #expect(book.sets.count == 1)
        #expect(book.set(of: t[0])?.workspaces.isEmpty == true)
    }

    @Test func nothingChangedChangesNothing() {
        var book = twoWorkspaces()
        let before = book.set(of: t[0])
        let outcome = book.pass([Array(t[0...3])])
        #expect(outcome == WorkspaceBook.Outcome())
        #expect(book.set(of: t[0]) == before)
    }
}
