import Foundation
import Testing
@testable import Ghostty

/// A closed tab comes back to its workspace through Ghostty's undo.
@MainActor
@Suite
struct TombstoneTests {
    private let t = (0..<8).map { _ in TabKey() }

    private func tombstone(_ surfaces: [UUID], tab: TabKey? = nil) -> WorkspaceTombstone {
        var book = WorkspaceBook()
        let key = tab ?? TabKey()
        _ = book.pass([[key]])
        let closed = book.closing(key)!
        return WorkspaceTombstone(closed: closed, surfaces: Set(surfaces), viewers: nil)
    }

    @Test func aTombstoneIsMatchedBySurfaceIdsOnlyAfterItsUndoRan() {
        let shelf = TombstoneShelf()
        let surface = UUID()
        let token = TombstoneToken(tombstone([surface]))
        #expect(shelf.claim(surfaces: [surface]) == nil)

        shelf.arm(token)
        #expect(shelf.claim(surfaces: [UUID()]) == nil)
        #expect(shelf.claim(surfaces: [surface]) != nil)
        #expect(shelf.claim(surfaces: [surface]) == nil)
    }

    @Test func theTombstoneWithTheMostSharedSurfacesWins() {
        let shelf = TombstoneShelf()
        let a = UUID(), b = UUID(), c = UUID()
        let one = TombstoneToken(tombstone([a]))
        let two = TombstoneToken(tombstone([b, c]))
        shelf.arm(one)
        shelf.arm(two)
        #expect(shelf.claim(surfaces: [a, b, c])?.surfaces == [b, c])
        #expect(shelf.claim(surfaces: [a])?.surfaces == [a])
    }

    @Test func whatNoWindowClaimedIsDroppedAndCounted() {
        let shelf = TombstoneShelf()
        shelf.arm(TombstoneToken(tombstone([UUID()])))
        #expect(shelf.settle() == 1)
        #expect(shelf.armedCount == 0)
        #expect(shelf.settle() == 0)
    }

    /// The tombstone is an action in the same undo group as Ghostty's own, and it runs first
    /// (last registered, first run), so it is armed before Ghostty's action creates the window.
    @Test func theTombstoneActionRunsInGhosttysUndoGroupBeforeGhosttysAction() {
        let manager = ExpiringUndoManager()
        manager.groupsByEvent = false
        let shelf = TombstoneShelf()
        let surface = UUID()
        let owner = NSObject()
        var claimed: WorkspaceTombstone?

        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: owner, expiresAfter: .seconds(5)) { _ in
            // Ghostty's action: the window appears and asks the shelf.
            claimed = shelf.claim(surfaces: [surface])
        }
        let token = TombstoneToken(tombstone([surface]))
        manager.registerUndo(withTarget: owner, expiresAfter: .seconds(5)) { _ in shelf.arm(token) }
        manager.endUndoGrouping()

        manager.undo()
        #expect(claimed != nil)
    }

    /// The undo closure is the only owner of the token: when Ghostty's undo expires, ExpiringTarget
    /// removes the actions of its target and the tombstone goes with them. Expiry is driven by
    /// `removeAllActions(withTarget:)`, the call its timer makes, so the test needs no clock.
    @Test func aTombstoneExpiresWithGhosttysUndo() {
        let manager = ExpiringUndoManager()
        manager.groupsByEvent = false
        let shelf = TombstoneShelf()
        let owner = NSObject()
        weak var weakToken: TombstoneToken?
        manager.beginUndoGrouping()
        do {
            let token = TombstoneToken(tombstone([UUID()]))
            weakToken = token
            manager.registerUndo(withTarget: owner, expiresAfter: .seconds(60)) { _ in shelf.arm(token) }
        }
        manager.endUndoGrouping()
        #expect(weakToken != nil)

        manager.removeAllActions(withTarget: owner)
        #expect(weakToken == nil)
        #expect(!manager.canUndo)
    }

    /// Closing a window closes its tabs one by one; the undo makes new tabs. The set, the
    /// names and the places come back, and no empty `Default` appears.
    @Test func aWindowUndoRestoresEveryWorkspaceWithoutAnEmptyDefault() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2], t[3]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[2]) { $0.join(t[2], to: work) }
        _ = book.edit(t[3]) { $0.join(t[3], to: work) }
        let original = book.set(of: t[0])?.id

        var order = Array(t[0...3])
        var closed: [WorkspaceBook.ClosedTab] = []
        for tab in t[0...3] {
            closed.append(book.closing(tab)!)
            order.removeAll { $0 == tab }
        }
        #expect(book.sets.isEmpty)

        for (new, old) in zip(t[4...7], closed) { book.reinsert(new, from: old) }
        let outcome = book.pass([Array(t[4...7])])
        #expect(outcome.reorders.isEmpty)
        #expect(book.sets.count == 1)
        #expect(book.set(of: t[4])?.id == original)
        #expect(book.names(Array(t[4...7])) == ["Default", "Work"])
        #expect(book.set(of: t[4])?.workspaces.count == 2)
    }

    /// The last tab of a workspace closed the workspace; the undo recreates it in its place.
    @Test func aTabUndoRecreatesItsClosedWorkspaceAtItsPlace() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[2]) { $0.join(t[2], to: work) }
        let closed = book.closing(t[2])!
        _ = book.pass([[t[0], t[1]]])
        #expect(book.names([t[0], t[1]]) == ["Default"])

        book.reinsert(t[3], from: closed)
        let outcome = book.pass([[t[0], t[1], t[3]]])
        #expect(outcome.reorders.isEmpty)
        #expect(book.names([t[0], t[1], t[3]]) == ["Default", "Work"])
        #expect(book.workspace(of: t[3])?.id == work)
    }
}
