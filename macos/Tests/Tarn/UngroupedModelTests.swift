import Foundation
import Testing
@testable import Ghostty

/// The ungrouped run, the mover rule, new tab placement and arrivals (stage 1a of
/// `docs/specs/workspace-folder.md`).
@Suite
struct UngroupedModelTests {
    private let t = (0..<8).map { _ in TabKey() }
    private let a = Workspace(name: "A")
    private let b = Workspace(name: "B")

    /// `owners` lists the group of each of t0, t1, ...; nil is the ungrouped group.
    private func make(_ owners: [Workspace?]) -> WorkspaceSet {
        var set = WorkspaceSet(workspaces: [a, b])
        let loose = set.ungroupedID()
        let members = zip(t, owners).map { ($0, $1?.id ?? loose) }
        return WorkspaceSet(id: set.id, workspaces: set.workspaces, members: Dictionary(uniqueKeysWithValues: members))
    }

    private func isUngrouped(_ set: WorkspaceSet, _ tab: TabKey) -> Bool {
        set.workspace(of: tab).map(set.isUngrouped) ?? false
    }

    // MARK: I1

    @Test func theUngroupedGroupIsTheSetIdAndOnlyOneIsMade() {
        var set = WorkspaceSet()
        let first = set.ungroupedID()
        let second = set.ungroupedID()
        #expect(first == set.id)
        #expect(second == first)
        #expect(set.workspaces.count == 1)
        #expect(set.workspaces[0].name == "~")
        set.add(Workspace(id: set.id, name: "Other"))
        #expect(set.workspaces.count == 1)
        #expect(set.workspaces[0].name == "~")
    }

    // MARK: S4, S42, S55 - where a new tab stands (G4)

    // spec: docs/specs/workspace-folder.md S4
    @Test func cmdTInAGroupStaysRightAfterItsSourceInTheSameGroup() {
        var set = make([a, a, a, nil])
        let order = [t[0], t[4], t[1], t[2], t[3]]
        let moves = set.reconcile(previous: Array(t[0...3]), current: order, target: a.id)
        #expect(set.members[t[4]] == a.id)
        #expect(moves.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S42
    @Test func cmdTInAnUngroupedTabAddsAnUngroupedTab() {
        var set = make([a, nil, nil])
        let order = [t[0], t[1], t[3], t[2]]
        let moves = set.reconcile(previous: Array(t[0...2]), current: order, target: set.id)
        #expect(isUngrouped(set, t[3]))
        #expect(moves.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S42 - the end of the run, the only tab of the set
    @Test func cmdTInAnUngroupedTabAtTheEndStaysThere() {
        var set = make([a, nil])
        let moves = set.reconcile(previous: [t[0], t[1]], current: [t[0], t[1], t[2]], target: set.id)
        #expect(isUngrouped(set, t[2]))
        #expect(moves.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S55
    @Test func cmdTWithNewTabPositionEndGoesToTheEndOfTheGroup() {
        var set = make([a, a, nil, nil])
        let order = [t[0], t[1], t[2], t[3], t[4]]
        let moves = set.reconcile(previous: Array(t[0...3]), current: order, target: a.id)
        #expect(set.members[t[4]] == a.id)
        #expect(moves == [.init(tab: t[4], delta: -2)])
    }

    // spec: docs/specs/workspace-folder.md G4 - the "+" names its group: end of the run
    @Test func anExplicitTargetGoesToTheEndOfTheRunWhereverGhosttyPutIt() {
        var set = make([a, a, a, nil])
        let order = [t[0], t[4], t[1], t[2], t[3]]
        let moves = set.reconcile(previous: Array(t[0...3]), current: order, target: a.id, explicit: true)
        #expect(moves == [.init(tab: t[4], delta: 2)])
    }

    // spec: docs/specs/workspace-folder.md G8 - the first tab of a new group
    @Test func theFirstTabOfANewGroupStandsBeforeTheFirstUngroupedTab() {
        var set = make([a, nil, nil])
        let fresh = set.create(name: "B2")!
        let order = [t[0], t[1], t[2], t[3]]
        let moves = set.reconcile(previous: Array(t[0...2]), current: order, target: fresh, explicit: true)
        #expect(set.members[t[3]] == fresh)
        #expect(moves == [.init(tab: t[3], delta: -2)])
    }

    @Test func theFirstTabOfANewGroupWithNoUngroupedTabGoesToTheEnd() {
        var set = make([a, a])
        let fresh = set.create(name: "B2")!
        let moves = set.reconcile(previous: [t[0], t[1]], current: [t[2], t[0], t[1]], target: fresh, explicit: true)
        #expect(moves == [.init(tab: t[2], delta: 2)])
    }

    // MARK: I2 - the mover rule (B1)

    private func bookWithGroupAndLoose() -> WorkspaceBook {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        let notes = book.newWorkspace("notes", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: notes) }
        return book
    }

    // spec: docs/specs/workspace-folder.md S52
    @Test func theOnlyTabOfAGroupDraggedPastTheUngroupedTabsBecomesUngrouped() {
        var book = bookWithGroupAndLoose()
        let outcome = book.pass([[t[1], t[2], t[0]]], selected: [t[0]])
        let set = book.set(of: t[0])!
        #expect(isUngrouped(set, t[0]))
        #expect(set.workspaces.count == 1)
        #expect(outcome.reorders.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S52 - a swap of neighbours: both fit, the selected one moves
    @Test func aSwapOfNeighboursMovesTheSelectedTab() {
        var viaGroupTab = bookWithGroupAndLoose()
        _ = viaGroupTab.pass([[t[0], t[1]]])
        _ = viaGroupTab.pass([[t[1], t[0]]], selected: [t[0]])
        #expect(isUngrouped(viaGroupTab.set(of: t[0])!, t[0]))
        #expect(isUngrouped(viaGroupTab.set(of: t[0])!, t[1]))

        var viaLoose = bookWithGroupAndLoose()
        _ = viaLoose.pass([[t[0], t[1]]])
        _ = viaLoose.pass([[t[1], t[0]]], selected: [t[1]])
        // The ungrouped tab was dragged to the top: it joins the group below it (first tab).
        #expect(viaLoose.workspace(of: t[1])?.name == "notes")
    }

    // spec: docs/specs/workspace-folder.md S52 - no selected tab: the tab of a group moves
    @Test func aSwapWithoutASelectedMoverMovesTheGroupTab() {
        var book = bookWithGroupAndLoose()
        _ = book.pass([[t[0], t[1]]])
        _ = book.pass([[t[1], t[0]]], selected: [nil])
        #expect(isUngrouped(book.set(of: t[0])!, t[0]))
        #expect(isUngrouped(book.set(of: t[0])!, t[1]))
    }

    @Test func aGroupTabBelowAnUngroupedTabIsABreak() {
        let set = make([a, nil, a])
        #expect(!set.isContiguous([t[0], t[1], t[2]]))
        #expect(!make([a, nil, b]).isContiguous([t[0], t[1], t[2]]))
        #expect(make([a, b, nil]).isContiguous([t[0], t[1], t[2]]))
    }

    @Test func theSecondBranchOfRepairNeverMovesATabIntoOrOutOfTheUngroupedGroup() {
        var set = make([a, nil, a, nil])
        // Two changes at once: no single mover. The groups keep their members, settle moves the tabs.
        let order = [t[0], t[1], t[2], t[3]]
        let moves = set.reconcile(previous: [t[3], t[2], t[1], t[0]], current: order, target: a.id)
        #expect(set.members[t[1]] == set.id)
        #expect(set.members[t[3]] == set.id)
        #expect(set.members[t[2]] == a.id)
        #expect(moves == [.init(tab: t[2], delta: -1)])
    }

    // MARK: settleUngrouped

    @Test func settleUngroupedPutsTheUngroupedRunLastAndKeepsTheRest() {
        let set = make([nil, a, nil, b])
        let order = Array(t[0...3])
        var native = order
        for move in set.settleUngrouped(order: order) {
            let at = native.firstIndex(of: move.tab)!
            native.remove(at: at)
            native.insert(move.tab, at: at + move.delta)
        }
        #expect(native == [t[1], t[3], t[0], t[2]])
        #expect(set.settleUngrouped(order: native).isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S51
    @Test func workspacesOnAgainRegroupsAndPutsTheUngroupedRunLast() {
        let set = make([nil, a, b, a, nil])
        var native = Array(t[0...4])
        for move in set.regroup(order: native) {
            let at = native.firstIndex(of: move.tab)!
            native.remove(at: at)
            native.insert(move.tab, at: at + move.delta)
        }
        #expect(native == [t[1], t[3], t[2], t[0], t[4]])
    }

    // spec: docs/specs/workspace-folder.md S51 - off: the new tab is ungrouped, membership stays
    @Test func workspacesOffKeepsMembershipAndMakesNewTabsUngrouped() {
        var book = bookWithGroupAndLoose()
        _ = book.pass([[t[0], t[1], t[2]]])
        book.frozen = true
        let outcome = book.pass([[t[0], t[1], t[2], t[3]]])
        #expect(outcome.reorders.isEmpty)
        #expect(book.workspace(of: t[0])?.name == "notes")
        #expect(isUngrouped(book.set(of: t[0])!, t[3]))
        book.frozen = false
        book.regroupPending = true
        #expect(book.pass([[t[0], t[1], t[2], t[3]]]).reorders.isEmpty)
        #expect(book.workspace(of: t[0])?.name == "notes")
    }

    // MARK: G5a - a tab from another window

    // spec: docs/specs/workspace-folder.md S53
    @Test func aTabDroppedAmongTheTabsOfAGroupJoinsItAndOneAmongUngroupedTabsIsUngrouped() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[5], t[6], t[7]], [t[2], t[3], t[4]]])
        let tarn = book.newWorkspace("tarn", in: t[2])
        _ = book.edit(t[2]) { $0.join(t[2], to: tarn); $0.join(t[3], to: tarn) }
        let outcome = book.pass([[t[0], t[6], t[7]], [t[2], t[1], t[3], t[4], t[5]]])
        let set = book.set(of: t[2])!
        #expect(set.members[t[1]] == tarn)
        #expect(isUngrouped(set, t[5]))
        #expect(outcome.reorders.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S53 - dropped first: the group of the tab below
    @Test func aTabDroppedFirstJoinsTheGroupOfTheTabBelow() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[4], t[5]], [t[2], t[3]]])
        let tarn = book.newWorkspace("tarn", in: t[2])
        _ = book.edit(t[2]) { $0.join(t[2], to: tarn) }
        _ = book.pass([[t[0], t[4], t[5]], [t[1], t[2], t[3]]])
        #expect(book.workspace(of: t[1])?.id == tarn)
    }

    // spec: docs/specs/workspace-folder.md G5a - an arrival with no neighbour is ungrouped
    @Test func anArrivalWithNoNeighbourIsUngrouped() {
        var book = bookWithGroupAndLoose()
        _ = book.pass([[t[0], t[1], t[2]]])
        _ = book.pass([[t[1], t[2]], [t[0]]])
        #expect(isUngrouped(book.set(of: t[0])!, t[0]))
    }

    // MARK: Undo and restore

    // spec: docs/specs/workspace-folder.md S50
    @Test func anOldHomeIsRestoredUngroupedBelowTheGroups() {
        let setID = UUID()
        let tarn = UUID()
        func snap(_ key: TabKey) -> WorkspaceSnapshot {
            WorkspaceSnapshot(
                version: 1, setID: setID, revision: 1, tabKey: key,
                workspaces: [
                    .init(id: UUID(), name: "~", collapsed: false, folder: NSHomeDirectory(), tabKeys: [t[1]]),
                    .init(id: tarn, name: "tarn", collapsed: false, folder: "/p/F", tabKeys: [t[0]]),
                ]
            )
        }
        var book = WorkspaceBook()
        book.adopt(snap(t[0]))
        book.adopt(snap(t[1]))
        let outcome = book.pass([[t[1], t[0]]])
        #expect(book.workspace(of: t[0])?.id == tarn)
        #expect(isUngrouped(book.set(of: t[1])!, t[1]))
        #expect(outcome.reorders == [.init(tab: t[0], delta: -1)])
        #expect(book.pass([[t[0], t[1]]]).reorders.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S21 - the snapshot with the key restores as saved
    @Test func aSnapshotWithTheUngroupedKeyRestoresTheUngroupedGroup() throws {
        let set = make([a, nil])
        let snapshot = WorkspaceSnapshot(set: set, tabKey: t[0], order: [t[0], t[1]])
        let copy = try WorkspaceSnapshot.decode(snapshot.encoded()).makeSet()
        #expect(isUngrouped(copy, t[1]))
        #expect(copy.workspace(of: t[0])?.name == "A")
    }

    // spec: docs/specs/workspace-folder.md S54 - absorb puts the other ungrouped tabs into ours
    @Test func absorbJoinsTheUngroupedTabsOfTheOtherSet() {
        var ours = make([a, nil])
        var theirs = WorkspaceSet()
        theirs.join(t[2], to: theirs.ungroupedID())
        ours.absorb(theirs)
        #expect(isUngrouped(ours, t[2]))
        #expect(ours.workspaces.filter(ours.isUngrouped).count == 1)

        var bare = make([a, a])
        bare.absorb(theirs)
        #expect(isUngrouped(bare, t[2]))
        #expect(bare.workspaces.count == 3)
    }
}
