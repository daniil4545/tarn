import Foundation
import Testing
@testable import Ghostty

/// Following a tab order Ghostty changed: membership never follows the order
/// (`docs/specs/workspace-folder.md` M3).
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

    /// spec: docs/specs/workspace-folder.md S60
    @Test func aNativeReorderChangesNoMembership() {
        var set = twoWorkspaces()
        let before = set
        for order in [[t[1], t[2], t[0], t[3]], [t[3], t[0], t[1], t[2]], [t[2], t[0], t[3], t[1]]] {
            set.reconcile(current: order, target: a.id)
        }
        #expect(set == before)
    }

    @Test func aNewTabJoinsTheTargetWhereGhosttyPutIt() {
        var set = twoWorkspaces()
        set.reconcile(current: [t[0], t[4], t[1], t[2], t[3]], target: b.id)
        #expect(set.members[t[4]] == b.id)
    }

    @Test func aMissingTargetFallsBackToAWorkspaceInsteadOfDroppingTheTab() {
        var set = twoWorkspaces()
        set.reconcile(current: Array(t[0...4]), target: UUID())
        #expect(set.members[t[4]] != nil)
    }

    @Test func anEmptySetGetsHomeForTheFirstTabs() {
        var set = WorkspaceSet()
        set.reconcile(current: [t[0], t[1]], target: UUID())
        #expect(set.runs(order: [t[0], t[1]]).map(\.workspace.name) == [WorkspaceSet.homeName])
        #expect(set.runs(order: [t[0], t[1]]).first?.workspace.folder == nil)
    }

    @Test func nothingChangedChangesNothing() {
        var set = twoWorkspaces()
        let before = set
        set.reconcile(current: Array(t[0...3]), target: a.id)
        #expect(set == before)
    }
}
