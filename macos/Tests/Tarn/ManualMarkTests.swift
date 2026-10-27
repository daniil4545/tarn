import Foundation
import Testing
@testable import Ghostty

/// Manual marks (D22): a tab the user placed by hand never moves by folder.
@Suite
struct ManualMarkTests {
    private let a = Workspace(name: "A")
    private let b = Workspace(name: "B")
    private let t = (0..<6).map { _ in TabKey() }

    /// A: t0 t1; B: t2 t3.
    private func twoWorkspaces() -> WorkspaceSet {
        let owners = [a, a, b, b]
        return WorkspaceSet(
            workspaces: [a, b],
            members: Dictionary(uniqueKeysWithValues: zip(t, owners.map(\.id)))
        )
    }

    // spec: docs/specs/workspace-folder.md S16
    @Test func aUserMoveToAnotherWorkspaceMarksTheTab() {
        var set = twoWorkspaces()
        set.join(t[0], to: b.id, byUser: true)
        #expect(set.isManual(t[0]))
        #expect(!set.isManual(t[1]))
    }

    // spec: docs/specs/workspace-folder.md S16
    @Test func theSeamForAnArrivalMoveLeavesNoMark() {
        var set = twoWorkspaces()
        set.join(t[0], to: b.id)
        #expect(!set.isManual(t[0]))
    }

    // spec: docs/specs/workspace-folder.md S31
    @Test func aMoveInsideTheSameWorkspaceLeavesNoMark() {
        var set = twoWorkspaces()
        set.join(t[0], to: a.id, byUser: true)
        #expect(!set.isManual(t[0]))
    }

    // spec: docs/specs/workspace-folder.md S16
    @Test func aNativeReorderIntoAnotherWorkspaceMarksTheMover() {
        var set = twoWorkspaces()
        let order = [t[0], t[2], t[1], t[3]]
        _ = set.reconcile(previous: [t[0], t[1], t[2], t[3]], current: order, target: a.id)
        #expect(set.members[t[2]] == a.id)
        #expect(set.isManual(t[2]))
        #expect(set.manual.count == 1)
    }

    // spec: docs/specs/workspace-folder.md S31
    @Test func aReorderInsideOneWorkspaceLeavesNoMark() {
        var set = twoWorkspaces()
        let order = [t[1], t[0], t[2], t[3]]
        _ = set.reconcile(previous: [t[0], t[1], t[2], t[3]], current: order, target: a.id)
        #expect(set.manual.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S31
    @Test func theFallbackRepairLeavesNoMark() {
        var set = twoWorkspaces()
        // Two tabs hop at once: no single mover heals the order.
        let order = [t[2], t[0], t[3], t[1]]
        _ = set.reconcile(previous: [t[0], t[1], t[2], t[3]], current: order, target: a.id)
        #expect(set.isContiguous(order))
        #expect(set.manual.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S31
    @Test func aNewTabOpenedWithPlusLeavesNoMark() {
        var set = twoWorkspaces()
        _ = set.reconcile(previous: Array(t[0...3]), current: Array(t[0...4]), target: b.id)
        #expect(set.members[t[4]] == b.id)
        #expect(set.manual.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S31
    @Test func deletingAWorkspaceLeavesNoMark() {
        var set = twoWorkspaces()
        let order = Array(t[0...3])
        let deleted = set.delete(b.id, order: order)
        #expect(deleted)
        #expect(set.members[t[2]] == a.id)
        #expect(set.manual.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S31
    @Test func mergingWindowsAddsNoMark() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2], t[3]]])
        let other = book.newWorkspace("Other", in: t[2])
        _ = book.edit(t[3]) { $0.join(t[3], to: other) }
        _ = book.pass([Array(t[0...3])])
        #expect(book.set(of: t[0])?.manual.isEmpty == true)
    }

    // spec: docs/specs/workspace-folder.md S31
    @Test func absorbUnitesTheMarksOfBothSets() {
        var first = twoWorkspaces()
        first.markManual(t[0])
        var second = WorkspaceSet.makeDefault(tabs: [t[4], t[5]])
        second.markManual(t[5])
        first.absorb(second)
        #expect(first.manual == [t[0], t[5]])
    }

    @Test func aMarkNeedsAMemberAndGoesWithTheTab() {
        var set = twoWorkspaces()
        set.markManual(t[4])
        #expect(set.manual.isEmpty)
        set.markManual(t[1])
        set.remove(t[1])
        #expect(set.manual.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S16
    @Test func theMarkSurvivesASnapshotRoundTrip() throws {
        var set = twoWorkspaces()
        set.markManual(t[2])
        let order = Array(t[0...3])
        let snapshot = WorkspaceSnapshot(set: set, tabKey: t[0], order: order)
        let back = try WorkspaceSnapshot.decode(snapshot.encoded())
        #expect(back.makeSet().manual == [t[2]])
        #expect(back == snapshot)
    }

    // spec: docs/specs/workspace-folder.md S21
    @Test func aSnapshotSavedBeforeMarksDecodesWithNone() throws {
        let set = twoWorkspaces()
        let snapshot = WorkspaceSnapshot(set: set, tabKey: t[0], order: Array(t[0...3]))
        var json = try #require(JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        #expect(json.removeValue(forKey: "manual") != nil)
        let old = try JSONSerialization.data(withJSONObject: json)
        let back = try WorkspaceSnapshot.decode(old)
        #expect(back.manual.isEmpty)
        #expect(back.makeSet().manual.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S30
    @Test func theMarkSurvivesTheUndoOfAClose() throws {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[2]) { $0.join(t[2], to: work, byUser: true) }
        let taken = book.closing(t[2])
        let closed = try #require(taken)
        #expect(closed.manual)
        #expect(book.set(of: t[0])?.manual.isEmpty == true)

        book.reinsert(t[3], from: closed)
        #expect(book.set(of: t[3])?.isManual(t[3]) == true)
        #expect(book.set(of: t[3])?.isManual(t[2]) == false)
    }

    // spec: docs/specs/workspace-folder.md S30
    @Test func anUnmarkedTabStaysUnmarkedAfterUndo() throws {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let taken = book.closing(t[1])
        let closed = try #require(taken)
        book.reinsert(t[2], from: closed)
        #expect(book.set(of: t[2])?.manual.isEmpty == true)
    }
}
