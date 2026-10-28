import Foundation
import Testing
@testable import Ghostty

/// The ungrouped group (I1): every fresh set starts with one, the id of the set, stored as "~"
/// with no folder. Restored sets keep their saved plain groups.
@Suite
struct HomeStartTests {
    private let t = (0..<6).map { _ in TabKey() }
    private func expectUngroupedOnly(_ book: WorkspaceBook, _ tab: TabKey, sourceLocation: SourceLocation = #_sourceLocation) {
        let set = book.set(of: tab)
        #expect(set?.workspaces.count == 1, sourceLocation: sourceLocation)
        #expect(set?.workspaces.first?.name == "~", sourceLocation: sourceLocation)
        #expect(set?.workspaces.first?.folder == nil, sourceLocation: sourceLocation)
        #expect(set?.workspaces.first?.id == set?.id, sourceLocation: sourceLocation)
    }

    // MARK: The places that make a fresh set

    // spec: windows-workspaces D1, S1
    @Test func launchGivesTheUngroupedGroup() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        expectUngroupedOnly(book, t[0])
    }

    // spec: docs/specs/workspace-folder.md T-255 - Cmd+N opens a window whose tab is ungrouped
    @Test func aNewWindowGetsItsOwnUngroupedGroup() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: work) }
        _ = book.pass([[t[0]], [t[1]]])
        #expect(book.set(of: t[0])?.id != book.set(of: t[1])?.id)
        expectUngroupedOnly(book, t[1])
    }

    // spec: windows-workspaces D12, S18
    @Test func theNextWindowAfterTheLastTabClosedStartsUngrouped() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        _ = book.closing(t[0])
        _ = book.pass([])
        #expect(book.sets.isEmpty)

        _ = book.pass([[t[1]]])
        expectUngroupedOnly(book, t[1])
    }

    // docs/modules/workspaces.md "Windows"
    @Test func aTabDroppedOutsideEveryWindowIsUngrouped() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[2]) { $0.join(t[2], to: work) }
        _ = book.pass([[t[0], t[1]], [t[2]]])
        #expect(book.set(of: t[2])?.id != book.set(of: t[0])?.id)
        expectUngroupedOnly(book, t[2])
    }

    @Test func aMissingTargetOfAnEmptySetFallsBackToTheUngroupedGroup() {
        var set = WorkspaceSet()
        _ = set.reconcile(previous: [], current: [t[0]], target: UUID())
        #expect(set.workspaces.count == 1)
        #expect(set.workspaces[0].name == "~")
        #expect(set.workspaces[0].folder == nil)
        #expect(set.isUngrouped(set.workspaces[0]))
        #expect(set.workspace(of: t[0])?.id == set.id)
    }

    @Test func aSnapshotOfAnotherVersionGivesTheUngroupedGroupWithAllTabs() throws {
        var snapshot = WorkspaceSnapshot(
            version: 1, setID: UUID(), revision: 1, tabKey: t[0],
            workspaces: [.init(id: UUID(), name: "A", collapsed: false, tabKeys: [t[0]])]
        )
        snapshot.version = 9
        #expect(WorkspaceRestore.snapshot(from: try snapshot.encoded()) == nil)

        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        expectUngroupedOnly(book, t[0])
        #expect(book.runs(for: [t[0], t[1]])[0].tabs.count == 2)
    }

    // spec: docs/specs/workspace-folder.md S59 (I1). The undo of a window of one ungrouped tab
    // recreates the ungrouped group and no second group.
    @Test func theUndoOfAnUngroupedWindowRecreatesTheUngroupedGroupOnly() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        let closed = book.closing(t[0])!
        #expect(book.sets.isEmpty)

        book.reinsert(t[1], from: closed)
        _ = book.pass([[t[1]]])
        expectUngroupedOnly(book, t[1])
        #expect(book.set(of: t[1])?.id == closed.set.id)
        #expect(book.sets.count == 1)
    }

    // spec: docs/specs/workspace-folder.md S59
    @Test func anUndoAfterTheUngroupedRunWentJoinsTheOneUngroupedRun() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: work) }
        // t1 and t2 are ungrouped. Close t2, then take t1 out of the ungrouped group, then undo.
        let closed = book.closing(t[2])!
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.pass([[t[0], t[1]]])
        #expect(book.set(of: t[0])?.workspace(book.set(of: t[0])!.id) == nil)

        book.reinsert(t[3], from: closed)
        _ = book.pass([[t[0], t[1], t[3]]])
        #expect(book.set(of: t[3])?.isUngrouped(book.workspace(of: t[3])!) == true)
        #expect(book.set(of: t[0])?.workspaces.count == 2)
        #expect(book.set(of: t[0])?.workspaces.filter { book.set(of: t[0])!.isUngrouped($0) }.count == 1)
    }

    // MARK: Restored sets keep their plain groups

    @Test func aRestoredNoProjectStaysNoProject() {
        var book = WorkspaceBook()
        book.restoreLegacy([t[0], t[1]])
        _ = book.pass([[t[0], t[1]]])
        #expect(book.names([t[0], t[1]]) == ["No project"])
        #expect(book.workspace(of: t[0])?.folder == nil)
        // A new tab joins it; the ungrouped group is not added next to it.
        _ = book.pass([[t[0], t[1], t[2]]], selected: [t[0]])
        #expect(book.names([t[0], t[1], t[2]]) == ["No project"])
    }

    @Test func aRestoredDefaultStaysDefault() {
        var book = WorkspaceBook()
        book.restoreLegacy([t[0]], name: WorkspaceSet.legacyDefaultName)
        _ = book.pass([[t[0]]])
        #expect(book.names([t[0]]) == ["Default"])
    }

    // spec: docs/specs/workspace-folder.md S50, G13
    @Test func aRestoredHomeWithTheHomeFolderOrNoFolderIsUngrouped() {
        let home = NSHomeDirectory()
        let homeFolder = WorkspaceFolder.standardized(home)
        let setID = UUID()
        let snapshot = WorkspaceSnapshot(
            version: 1, setID: setID, revision: 1, tabKey: t[0],
            workspaces: [
                .init(id: UUID(), name: "~", collapsed: false, folder: homeFolder, tabKeys: [t[0]]),
                .init(id: UUID(), name: "Home base", collapsed: false, folder: homeFolder, tabKeys: [t[1]]),
                .init(id: UUID(), name: "~", collapsed: false, tabKeys: [t[2]]),
            ]
        )
        let set = snapshot.makeSet(home: home)
        // Two "~" entries merge into the one ungrouped group.
        #expect(set.workspaces.count == 2)
        #expect(set.members[t[0]] == setID)
        #expect(set.members[t[2]] == setID)
        #expect(set.workspace(of: t[1])?.folder == homeFolder)
        let elsewhere = WorkspaceSnapshot(
            version: 1, setID: UUID(), revision: 1, tabKey: t[4],
            workspaces: [.init(id: UUID(), name: "~", collapsed: false, folder: "/p/F", tabKeys: [t[4]])]
        )
        let kept = elsewhere.makeSet(home: home)
        #expect(kept.workspaces.first?.folder == "/p/F")
        #expect(kept.workspaces.first.map(kept.isUngrouped) == false)

        var book = WorkspaceBook()
        book.adopt(snapshot)
        book.frozen = true
        _ = book.pass([[t[0], t[1], t[2], t[3]]])
        #expect(book.workspace(of: t[3])?.id == book.workspace(of: t[0])?.id)
    }

    // spec: docs/specs/workspace-folder.md S21, G13 - the key is written and read back
    @Test func theUngroupedKeyRoundTripsAndANamedTildeSurvivesIt() throws {
        var set = WorkspaceSet()
        let tilde = set.create(name: "~")!
        set.join(t[0], to: tilde)
        set.join(t[1], to: set.ungroupedID())
        let snapshot = WorkspaceSnapshot(set: set, tabKey: t[0], order: [t[0], t[1]])
        #expect(snapshot.workspaces.map(\.ungrouped) == [false, true])
        let back = try WorkspaceSnapshot.decode(snapshot.encoded()).makeSet()
        #expect(back.members[t[1]] == set.id)
        #expect(back.members[t[0]] == tilde)
    }

    // MARK: Workspaces off

    @Test func workspacesOffOnAFreshSetDoesNotMakeASecondUngroupedGroup() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        book.frozen = true
        _ = book.pass([[t[0], t[1]]])
        #expect(book.workspace(of: t[1])?.id == book.workspace(of: t[0])?.id)
        #expect(book.set(of: t[0])?.workspaces.count == 1)
        expectUngroupedOnly(book, t[0])
    }

    @Test func workspacesOffFromTheFirstPassMakesOneUngroupedGroup() {
        var book = WorkspaceBook()
        book.frozen = true
        _ = book.pass([[t[0]]])
        _ = book.pass([[t[0], t[1]]])
        expectUngroupedOnly(book, t[1])
    }
}
