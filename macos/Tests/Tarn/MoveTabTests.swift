import Foundation
import Testing
@testable import Ghostty

/// Where a dragged tab lands among the other tabs of its window.
@Suite
struct MoveTabTests {
    private let t = (0..<5).map { _ in TabKey() }

    @Test func aTabBeforeANeighbourTakesItsPlace() {
        let place = WorkspaceRegistry.destination(of: t[0], in: t, before: t[3], isMember: { _ in false })
        #expect(place == 2)
    }

    @Test func aTabGoesAfterTheLastMemberOfTheWorkspace() {
        let members: Set = [t[1], t[2]]
        let place = WorkspaceRegistry.destination(of: t[4], in: t, before: nil, isMember: members.contains)
        #expect(place == 3)
    }

    // A lone tab dropped on its own header or row moved its whole workspace to the end.
    @Test func theOnlyTabOfAWorkspaceStaysWhereItIs() {
        let place = WorkspaceRegistry.destination(of: t[1], in: t, before: nil, isMember: { _ in false })
        #expect(place == 1)
    }

    /// "tarn" holds t[0...2], "notes" holds t[3]; t[4] is ungrouped.
    private func twoGroups() -> (set: WorkspaceSet, tarn: Workspace.ID, notes: Workspace.ID) {
        var set = WorkspaceSet()
        let tarn = set.create(name: "tarn")!, notes = set.create(name: "notes")!
        for tab in t[0...2] { set.join(tab, to: tarn) }
        set.join(t[3], to: notes)
        return (set, tarn, notes)
    }

    // spec: docs/specs/workspace-folder.md S61
    /// Remove from group on the middle tab: ungrouped, one move to the place after the group's last tab.
    @Test func removingTheMiddleTabMovesItAfterTheLastTabOfItsGroup() {
        var (set, tarn, _) = twoGroups()
        set.remove(t[1])
        #expect(set.workspace(of: t[1]) == nil)
        let place = WorkspaceRegistry.destination(of: t[1], in: t, before: nil, isMember: { set.members[$0] == tarn })
        #expect(place == 2, "order becomes t0 t2 t1 t3 t4: delta +1")
    }

    // spec: docs/specs/workspace-folder.md S61
    @Test func removingTheLastTabOfAGroupMovesNothing() {
        var (set, tarn, _) = twoGroups()
        set.remove(t[2])
        #expect(WorkspaceRegistry.destination(of: t[2], in: t, before: nil, isMember: { set.members[$0] == tarn }) == 2)
    }

    // spec: docs/specs/workspace-folder.md S62
    @Test func moveToPutsTheTabAfterTheLastTabOfTheTargetGroup() {
        var (set, _, notes) = twoGroups()
        set.join(t[0], to: notes)
        #expect(set.workspace(of: t[0])?.name == "notes")
        let place = WorkspaceRegistry.destination(of: t[0], in: t, before: nil, isMember: { set.members[$0] == notes })
        #expect(place == 3, "order becomes t1 t2 t3 t0 t4: delta +3")
    }

    // spec: docs/specs/workspace-folder.md S43
    /// The only tab of a group leaves: the group is gone, the tab stays where it is.
    @Test func theLastTabLeavingRemovesItsGroupAndStaysInPlace() {
        var (set, _, notes) = twoGroups()
        set.remove(t[3])
        #expect(set.workspace(notes) == nil)
        #expect(WorkspaceRegistry.destination(of: t[3], in: t, before: nil, isMember: { set.members[$0] == notes }) == 3)
    }

    // spec: docs/specs/workspace-folder.md S43
    /// Dropped below all rows: after the last tab of the window.
    @Test func aDropBelowAllRowsGoesAfterTheLastTab() {
        let place = WorkspaceRegistry.destination(of: t[0], in: t, before: nil, isMember: { _ in true })
        #expect(place == 4)
    }
}
