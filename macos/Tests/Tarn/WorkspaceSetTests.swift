import Foundation
import Testing
@testable import Ghostty

/// The workspace model: ungroup, last tab, snapshot.
@Suite
struct WorkspaceSetTests {
    private let a = Workspace(name: "A")
    private let b = Workspace(name: "B")
    private let c = Workspace(name: "C")
    private let tabs = (0..<6).map { _ in TabKey() }

    /// A: tabs 0,1; B: tabs 2,3; C: tabs 4,5.
    private func threeWorkspaces() -> WorkspaceSet {
        var members: [TabKey: Workspace.ID] = [:]
        for (index, tab) in tabs.enumerated() {
            members[tab] = [a, a, b, b, c, c][index].id
        }
        return WorkspaceSet(workspaces: [a, b, c], members: members)
    }

    // spec: docs/specs/workspace-folder.md S45
    @Test func ungroupLeavesEveryTabWhereItStands() {
        var set = threeWorkspaces()
        let ungrouped = set.ungroup(b.id)
        let again = set.ungroup(b.id)
        #expect(ungrouped)
        let runs = set.runs(order: tabs)
        #expect(runs.map { $0.workspace?.name } == ["A", nil, "C"])
        #expect(runs[1].tabs == [tabs[2], tabs[3]])
        #expect(set.workspace(b.id) == nil)
        #expect(!again, "an unknown group changes nothing")
    }

    // spec: docs/specs/workspace-folder.md S56
    @Test func theOnlyGroupCanBeDeleted() {
        var set = WorkspaceSet()
        let id = set.create(name: "Only")!
        set.join(tabs[0], to: id)
        let ungrouped = set.ungroup(id)
        #expect(ungrouped)
        #expect(set.workspaces.isEmpty)
        #expect(set.runs(order: [tabs[0]]).map { $0.workspace?.name } == [nil])
    }

    @Test func closingTheLastTabClosesTheWorkspace() {
        var set = threeWorkspaces()
        let first = set.remove(tabs[0])
        let second = set.remove(tabs[1])
        let again = set.remove(tabs[1])
        #expect(first == .stayed)
        #expect(second == .workspaceClosed(a))
        #expect(again == .notMember)
        #expect(set.workspaces.map(\.name).sorted() == ["B", "C"])
    }

    @Test func closingTheLastTabOfTheLastWorkspaceEmptiesTheSet() {
        var set = WorkspaceSet()
        set.join(tabs[0], to: set.create(name: "Only")!)
        let closed = set.remove(tabs[0])
        guard case .workspaceClosed = closed else {
            Issue.record("workspace stayed")
            return
        }
        #expect(set.workspaces.isEmpty)
    }

    @Test func blankNamesAreRefused() {
        var set = threeWorkspaces()
        let blank = set.create(name: "  ")
        #expect(blank == nil)
        let empty = set.rename(a.id, to: "")
        let padded = set.rename(a.id, to: "  Work ")
        #expect(!empty)
        #expect(padded)
        #expect(set.workspace(a.id)?.name == "Work")
    }

    @Test func foldIsStoredOnTheWorkspace() {
        var set = threeWorkspaces()
        set.setCollapsed(b.id, true)
        #expect(set.runs(order: tabs).compactMap { $0.workspace?.collapsed } == [false, true, false])
    }

    @Test func runsFollowTheTabOrderNotTheStoredOrder() {
        let set = threeWorkspaces()
        let reversed = Array(tabs.reversed())
        #expect(set.runs(order: reversed).map { $0.workspace?.name } == ["C", "B", "A"])
    }

    /// A workspace stands where its first tab is and holds all its tabs; ungrouped tabs stand
    /// where they are, and two that only a later tab of a workspace parted make one block.
    @Test func runsDrawUngroupedTabsWhereTheyStand() {
        let set = WorkspaceSet(workspaces: [a, b], members: [tabs[1]: a.id, tabs[3]: a.id, tabs[4]: b.id])
        let runs = set.runs(order: tabs)
        #expect(runs.map { $0.workspace?.name } == [nil, "A", nil, "B", nil])
        #expect(runs.map(\.tabs) == [[tabs[0]], [tabs[1], tabs[3]], [tabs[2]], [tabs[4]], [tabs[5]]])

        let parted = WorkspaceSet(workspaces: [a], members: [tabs[0]: a.id, tabs[2]: a.id])
        let merged = parted.runs(order: Array(tabs[0...3]))
        #expect(merged.map { $0.workspace?.name } == ["A", nil])
        #expect(merged.last?.tabs == [tabs[1], tabs[3]])
    }

    @Test func snapshotRoundTrips() throws {
        var set = threeWorkspaces()
        set.setCollapsed(c.id, true)
        let snapshot = WorkspaceSnapshot(set: set, tabKey: tabs[2], order: tabs)
        let restored = try WorkspaceSnapshot.decode(snapshot.encoded())

        #expect(restored == snapshot)
        let copy = restored.makeSet()
        #expect(copy.id == set.id)
        #expect(copy.revision == set.revision)
        #expect(copy.runs(order: tabs) == set.runs(order: tabs))
    }

    // spec: docs/specs/workspace-folder.md S21 - a snapshot saved with manual marks still restores
    @Test func aSnapshotWithTheDroppedManualKeyDecodes() throws {
        let set = threeWorkspaces()
        let snapshot = WorkspaceSnapshot(set: set, tabKey: tabs[0], order: tabs)
        var json = try #require(JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        json["manual"] = [tabs[0].uuidString]
        let restored = try WorkspaceSnapshot.decode(JSONSerialization.data(withJSONObject: json))
        #expect(restored == snapshot)
    }

    /// spec: docs/specs/workspace-folder.md S21
    @Test func anUngroupedTabIsInNoWorkspaceOfTheSnapshotAndComesBackUngrouped() throws {
        let set = WorkspaceSet(workspaces: [a], members: [tabs[0]: a.id])
        let order = [tabs[0], tabs[1]]
        let snapshot = WorkspaceSnapshot(set: set, tabKey: tabs[1], order: order)
        #expect(snapshot.workspaces.flatMap(\.tabKeys) == [tabs[0]])
        let copy = try WorkspaceSnapshot.decode(snapshot.encoded()).makeSet()
        #expect(copy.workspace(of: tabs[1]) == nil)
        #expect(copy.runs(order: order) == set.runs(order: order))
        #expect(copy.runs(order: order).map { $0.workspace?.name } == ["A", nil])
    }

    @Test func snapshotKeepsTabsThatHaveNoWindowYet() {
        let set = threeWorkspaces()
        let snapshot = WorkspaceSnapshot(set: set, tabKey: tabs[0], order: Array(tabs[0...2]))
        let copy = snapshot.makeSet()
        #expect(copy.members == set.members)
        #expect(snapshot.workspaces.map(\.name) == ["A", "B", "C"])
    }

    @Test func unknownVersionAndGarbageDoNotDecode() throws {
        var snapshot = WorkspaceSnapshot(set: threeWorkspaces(), tabKey: tabs[0], order: tabs)
        snapshot.version = 2
        let data = try snapshot.encoded()
        #expect(throws: WorkspaceSnapshot.DecodeError.unknownVersion(2)) { try WorkspaceSnapshot.decode(data) }
        #expect(throws: (any Error).self) { try WorkspaceSnapshot.decode(Data("nope".utf8)) }
    }

    @Test func snapshotDropsEmptyWorkspacesAndDuplicateTabs() {
        let id = UUID()
        let snapshot = WorkspaceSnapshot(
            version: 1, setID: id, revision: 3, tabKey: tabs[0],
            workspaces: [
                .init(id: a.id, name: "A", collapsed: false, tabKeys: [tabs[0]]),
                .init(id: b.id, name: "B", collapsed: false, tabKeys: []),
                .init(id: c.id, name: "C", collapsed: false, tabKeys: [tabs[0], tabs[1]]),
            ]
        )
        let set = snapshot.makeSet()
        #expect(set.workspaces.map(\.name) == ["A", "C"])
        #expect(set.members[tabs[0]] == a.id)
        #expect(set.members[tabs[1]] == c.id)
    }
}

/// The New Group dialog's result (G2).
struct NewGroupChoiceTests {
    // spec: docs/specs/workspace-folder.md S41
    @Test func aGroupTakesItsNameAndABlankNameBecomesGroup() {
        #expect(NewGroupChoice.make(confirmed: true, isWorkspace: false, name: " notes ", folder: "/x") == .group(name: "notes"))
        #expect(NewGroupChoice.make(confirmed: true, isWorkspace: false, name: "  ", folder: "") == .group(name: "Group"))
    }

    // spec: docs/specs/workspace-folder.md S1
    @Test func aWorkspaceTakesItsFolderAndNeedsOne() {
        #expect(NewGroupChoice.make(confirmed: true, isWorkspace: true, name: "n", folder: "/p/tarn") == .workspace(folder: "/p/tarn"))
        #expect(NewGroupChoice.make(confirmed: true, isWorkspace: true, name: "n", folder: " ") == nil)
    }

    // spec: docs/specs/workspace-folder.md S2
    @Test func cancelChoosesNothing() {
        #expect(NewGroupChoice.make(confirmed: false, isWorkspace: false, name: "notes", folder: "") == nil)
        #expect(NewGroupChoice.make(confirmed: false, isWorkspace: true, name: "", folder: "/p") == nil)
    }
}
