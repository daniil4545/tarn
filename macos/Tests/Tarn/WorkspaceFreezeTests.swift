import Foundation
import Testing
@testable import Ghostty

/// Workspaces off: the workspaces are frozen, new tabs join "~", nothing moves; on again the
/// tabs regroup (`docs/modules/workspaces.md`).
@Suite
struct WorkspaceFreezeTests {
    private let t = (0..<6).map { _ in TabKey() }

    /// Two workspaces: A holds t0 and t1, B holds t2.
    private func seeded() -> WorkspaceBook {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        let b = book.newWorkspace("B", in: t[0])
        _ = book.edit(t[2]) { $0.join(t[2], to: b) }
        return book
    }

    @Test func aNewTabJoinsHomeAndNothingMoves() {
        var book = seeded()
        let first = book.names([t[0], t[1], t[2]])
        book.frozen = true
        let outcome = book.pass([[t[0], t[1], t[2], t[3]]])
        #expect(outcome.reorders.isEmpty)
        #expect(book.workspace(of: t[3])?.name == "~")
        #expect(book.workspace(of: t[0])?.name == first.first)
        #expect(book.workspace(of: t[2])?.name == "B")
    }

    @Test func aDragDoesNotChangeMembership() {
        var book = seeded()
        book.frozen = true
        // t2 dragged between t0 and t1: in a live book that would move it into A.
        let outcome = book.pass([[t[0], t[2], t[1]]])
        #expect(outcome.reorders.isEmpty)
        #expect(book.workspace(of: t[2])?.name == "B")
        #expect(book.workspace(of: t[1])?.name == book.workspace(of: t[0])?.name)
    }

    @Test func closingATabKeepsTheRestFrozen() {
        var book = seeded()
        book.frozen = true
        _ = book.pass([[t[0], t[2]]])
        #expect(book.workspace(of: t[1]) == nil)
        #expect(book.workspace(of: t[2])?.name == "B")
    }

    @Test func homeIsOneWorkspaceForAllNewTabs() {
        var book = seeded()
        book.frozen = true
        _ = book.pass([[t[0], t[1], t[2], t[3]]])
        _ = book.pass([[t[0], t[1], t[2], t[3], t[4]]])
        #expect(book.workspace(of: t[3])?.id == book.workspace(of: t[4])?.id)
    }

    @Test func onAgainTheTabsRegroupAndHomeStays() {
        var book = seeded()
        book.frozen = true
        // Frozen order: A, B, A, home, A.
        let order = [t[0], t[2], t[1], t[3], t[4]]
        _ = book.pass([[t[0], t[1], t[2], t[3], t[4]]])
        _ = book.pass([order])
        book.frozen = false
        book.regroupPending = true
        let outcome = book.pass([order])
        #expect(outcome.reorders.isEmpty == false)

        // Apply the moves as the registry does and look again: every workspace is one run.
        var native = order
        for move in outcome.reorders {
            let at = native.firstIndex(of: move.tab)!
            native.remove(at: at)
            native.insert(move.tab, at: at + move.delta)
        }
        #expect(native == [t[0], t[1], t[2], t[3], t[4]])
        #expect(book.pass([native]).reorders.isEmpty)
        #expect(book.names(native).count == 3)
        #expect(book.workspace(of: t[4])?.name == "~")
    }

    @Test func regroupKeepsTheOrderOfFirstAppearance() {
        let a = Workspace(name: "A")
        let b = Workspace(name: "B")
        let set = WorkspaceSet(workspaces: [a, b], members: [t[0]: a.id, t[1]: b.id, t[2]: a.id, t[3]: b.id])
        var native = [t[0], t[1], t[2], t[3]]
        for move in set.regroup(order: native) {
            let at = native.firstIndex(of: move.tab)!
            native.remove(at: at)
            native.insert(move.tab, at: at + move.delta)
        }
        #expect(native == [t[0], t[2], t[1], t[3]])
    }
}
