import Foundation
import Testing
@testable import Ghostty

/// Following a tab order Ghostty changed. After each case the sidebar rows, top to
/// bottom, are the native tabs in order, so cmd+N lands on row N.
@Suite
struct ReconcileTests {
    private let a = Workspace(name: "A")
    private let b = Workspace(name: "B")
    private let t = (0..<5).map { _ in TabKey() }

    /// A: t0 t1; B: t2 t3.
    private func twoWorkspaces() -> WorkspaceSet {
        let owners = [a, a, b, b]
        return WorkspaceSet(
            workspaces: [a, b],
            members: Dictionary(uniqueKeysWithValues: zip(t, owners.map(\.id)))
        )
    }

    private func rows(_ set: WorkspaceSet, _ order: [TabKey]) -> [TabKey] {
        set.runs(order: order).flatMap(\.tabs)
    }

    @Test func movedDownIntoAnotherWorkspaceJoinsTheUpperNeighbour() {
        var set = twoWorkspaces()
        let order = [t[1], t[2], t[0], t[3]]
        let moves = set.reconcile(previous: [t[0], t[1], t[2], t[3]], current: order, target: a.id)
        #expect(moves.isEmpty)
        #expect(set.members[t[0]] == b.id)
        #expect(set.isContiguous(order))
        #expect(rows(set, order) == order)
    }

    @Test func movedToTheTopJoinsTheLowerNeighbour() {
        var set = twoWorkspaces()
        let order = [t[3], t[0], t[1], t[2]]
        _ = set.reconcile(previous: [t[0], t[1], t[2], t[3]], current: order, target: a.id)
        #expect(set.members[t[3]] == a.id)
        #expect(rows(set, order) == order)
    }

    @Test func movingAWholeEdgeTabKeepsMembership() {
        var set = twoWorkspaces()
        let order = [t[1], t[0], t[2], t[3]]
        _ = set.reconcile(previous: [t[0], t[1], t[2], t[3]], current: order, target: a.id)
        #expect(set.members[t[0]] == a.id)
        #expect(set.members[t[1]] == a.id)
        #expect(rows(set, order) == order)
    }

    @Test func tabMovedToTheEndOfTheOtherWorkspaceStaysTheSameWorkspaceRun() {
        var set = twoWorkspaces()
        let order = [t[1], t[2], t[3], t[0]]
        _ = set.reconcile(previous: [t[0], t[1], t[2], t[3]], current: order, target: a.id)
        #expect(set.members[t[0]] == b.id)
        #expect(rows(set, order) == order)
    }

    @Test func nativeDragIsTheSameAsAMove() {
        var set = twoWorkspaces()
        // Dragging t2 up between t0 and t1.
        let order = [t[0], t[2], t[1], t[3]]
        _ = set.reconcile(previous: [t[0], t[1], t[2], t[3]], current: order, target: a.id)
        #expect(set.members[t[2]] == a.id)
        #expect(set.isContiguous(order))
        #expect(rows(set, order) == order)
    }

    @Test func brokenRunsWithAnUnchangedOrderEndContiguous() {
        var set = twoWorkspaces()
        // Membership changed but the native order did not (the move was late or lost).
        set.join(t[0], to: b.id)
        let order = Array(t[0...3])
        _ = set.reconcile(previous: order, current: order, target: a.id)
        #expect(set.isContiguous(order))
        #expect(rows(set, order) == order)
    }

    @Test func twoChangesAtOnceEndContiguous() {
        var set = twoWorkspaces()
        // Two tabs hop at once: no single mover heals the order.
        let order = [t[2], t[0], t[3], t[1]]
        _ = set.reconcile(previous: [t[0], t[1], t[2], t[3]], current: order, target: a.id)
        #expect(set.isContiguous(order))
        #expect(rows(set, order) == order)
        #expect(set.members.count == 4)
    }

    @Test func aNewTabJoinsTheTargetAndMovesToTheEndOfItsRun() {
        var set = twoWorkspaces()
        // Ghostty put the new tab after the last one; the target is A.
        let order = [t[0], t[1], t[2], t[3], t[4]]
        let moves = set.reconcile(previous: Array(t[0...3]), current: order, target: a.id)
        #expect(set.members[t[4]] == a.id)
        #expect(moves == [.init(tab: t[4], delta: -2)])
    }

    @Test func aNewTabAlreadyAtTheEndOfItsRunNeedsNoMove() {
        var set = twoWorkspaces()
        let order = [t[0], t[1], t[4], t[2], t[3]]
        let moves = set.reconcile(previous: Array(t[0...3]), current: order, target: a.id)
        #expect(moves.isEmpty)
        #expect(rows(set, order) == order)
    }

    @Test func aNewTabOfAnEmptyWorkspaceGoesToTheEnd() {
        var set = twoWorkspaces()
        let fresh = set.create(name: "C")!
        let order = [t[0], t[4], t[1], t[2], t[3]]
        let moves = set.reconcile(previous: Array(t[0...3]), current: order, target: fresh)
        #expect(set.members[t[4]] == fresh)
        #expect(moves == [.init(tab: t[4], delta: 3)])
    }

    @Test func aMissingTargetFallsBackToAWorkspaceInsteadOfDroppingTheTab() {
        var set = twoWorkspaces()
        _ = set.reconcile(previous: Array(t[0...3]), current: Array(t[0...4]), target: UUID())
        #expect(set.members[t[4]] != nil)
    }

    @Test func anEmptySetGetsHomeForTheFirstTabs() {
        var set = WorkspaceSet()
        _ = set.reconcile(previous: [], current: [t[0], t[1]], target: UUID())
        #expect(set.runs(order: [t[0], t[1]]).map(\.workspace.name) == [WorkspaceSet.homeName])
        #expect(set.runs(order: [t[0], t[1]]).first?.workspace.folder == nil)
    }

    @Test func nothingChangedChangesNothing() {
        var set = twoWorkspaces()
        let before = set
        let moves = set.reconcile(previous: Array(t[0...3]), current: Array(t[0...3]), target: a.id)
        #expect(moves.isEmpty)
        #expect(set == before)
    }
}
