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
        var (set, _, _) = twoGroups()
        let place = WorkspaceRegistry.place(of: t[1], in: t, members: set.members, to: nil, before: nil, behind: nil)
        set.remove(t[1])
        #expect(set.workspace(of: t[1]) == nil)
        #expect(place == 2, "order becomes t0 t2 t1 t3 t4: delta +1")
    }

    // spec: docs/specs/workspace-folder.md S61
    @Test func removingTheLastTabOfAGroupMovesNothing() {
        let (set, _, _) = twoGroups()
        #expect(WorkspaceRegistry.place(of: t[2], in: t, members: set.members, to: nil, before: nil, behind: nil) == 2)
    }

    // spec: docs/specs/workspace-folder.md S62
    @Test func moveToPutsTheTabAfterTheLastTabOfTheTargetGroup() {
        var (set, _, notes) = twoGroups()
        let place = WorkspaceRegistry.place(of: t[0], in: t, members: set.members, to: notes, before: nil, behind: nil)
        set.join(t[0], to: notes)
        #expect(set.workspace(of: t[0])?.name == "notes")
        #expect(place == 3, "order becomes t1 t2 t3 t0 t4: delta +3")
    }

    // spec: docs/specs/workspace-folder.md S43
    /// The only tab of a group leaves: the group is gone, the tab stays where it is.
    @Test func theLastTabLeavingRemovesItsGroupAndStaysInPlace() {
        var (set, _, notes) = twoGroups()
        #expect(WorkspaceRegistry.place(of: t[3], in: t, members: set.members, to: nil, before: nil, behind: nil) == 3)
        set.remove(t[3])
        #expect(set.workspace(notes) == nil)
    }

    // spec: docs/specs/workspace-folder.md S43
    /// Dropped below all rows: after the last tab of the window.
    @Test func aDropBelowAllRowsGoesAfterTheLastTab() {
        let (set, _, _) = twoGroups()
        let place = WorkspaceRegistry.place(of: t[0], in: t, members: set.members, to: nil, before: nil, behind: Set(t))
        #expect(place == 4)
    }
}
