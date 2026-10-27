import Foundation
import Testing
@testable import Ghostty

/// T-245: every fresh set starts in workspace "~" with no folder, the same "~" that
/// Workspaces off creates. Restored sets keep their saved names.
@Suite
struct HomeStartTests {
    private let t = (0..<6).map { _ in TabKey() }
    private func expectHomeOnly(_ book: WorkspaceBook, _ tab: TabKey, sourceLocation: SourceLocation = #_sourceLocation) {
        let set = book.set(of: tab)
        #expect(set?.workspaces.count == 1, sourceLocation: sourceLocation)
        #expect(set?.workspaces.first?.name == "~", sourceLocation: sourceLocation)
        #expect(set?.workspaces.first?.folder == nil, sourceLocation: sourceLocation)
    }

    // MARK: The places that make a fresh set

    // spec: windows-workspaces D1, S1
    @Test func launchGivesHomeWithTheFolder() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        expectHomeOnly(book, t[0])
    }

    // spec: windows-workspaces D10
    @Test func aNewWindowGetsItsOwnHome() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        _ = book.pass([[t[0]], [t[1]]])
        #expect(book.set(of: t[0])?.id != book.set(of: t[1])?.id)
        expectHomeOnly(book, t[0])
        expectHomeOnly(book, t[1])
    }

    // spec: windows-workspaces D12, S18
    @Test func theNextWindowAfterTheLastTabClosedStartsInHome() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        _ = book.edit(t[0]) { $0.rename($0.workspaces[0].id, to: "Work") }
        _ = book.closing(t[0])
        _ = book.pass([])
        #expect(book.sets.isEmpty)

        _ = book.pass([[t[1]]])
        expectHomeOnly(book, t[1])
    }

    // docs/modules/workspaces.md "Windows"
    @Test func aTabDroppedOutsideEveryWindowStartsAHomeSet() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[2]) { $0.join(t[2], to: work) }
        _ = book.pass([[t[0], t[1]], [t[2]]])
        #expect(book.set(of: t[2])?.id != book.set(of: t[0])?.id)
        expectHomeOnly(book, t[2])
    }

    @Test func aMissingTargetOfAnEmptySetFallsBackToHome() {
        var set = WorkspaceSet()
        _ = set.reconcile(previous: [], current: [t[0]], target: UUID())
        #expect(set.workspaces.count == 1)
        #expect(set.workspaces[0].name == "~")
        #expect(set.workspaces[0].folder == nil)
        #expect(set.workspace(of: t[0])?.id == set.workspaces[0].id)
    }

    @Test func aSnapshotOfAnotherVersionGivesHomeWithAllTabs() throws {
        var snapshot = WorkspaceSnapshot(
            version: 1, setID: UUID(), revision: 1, tabKey: t[0],
            workspaces: [.init(id: UUID(), name: "A", collapsed: false, tabKeys: [t[0]])]
        )
        snapshot.version = 9
        #expect(WorkspaceRestore.snapshot(from: try snapshot.encoded()) == nil)

        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        expectHomeOnly(book, t[0])
        #expect(book.runs(for: [t[0], t[1]])[0].tabs.count == 2)
    }

    // The undo of a window of one "~" tab recreates "~" and no second workspace.
    @Test func theUndoOfAHomeWindowRecreatesHomeAndNoEmptyOne() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        let closed = book.closing(t[0])!
        #expect(book.sets.isEmpty)

        book.reinsert(t[1], from: closed)
        _ = book.pass([[t[1]]])
        expectHomeOnly(book, t[1])
        #expect(book.set(of: t[1])?.id == closed.set.id)
        #expect(book.sets.count == 1)
    }

    // MARK: Restored sets keep their names

    @Test func aRestoredNoProjectStaysNoProject() {
        var book = WorkspaceBook()
        book.restoreLegacy([t[0], t[1]])
        _ = book.pass([[t[0], t[1]]])
        #expect(book.names([t[0], t[1]]) == ["No project"])
        #expect(book.workspace(of: t[0])?.folder == nil)
        // A new tab joins it; "~" is not added next to it.
        _ = book.pass([[t[0], t[1], t[2]]], selected: [t[0]])
        #expect(book.names([t[0], t[1], t[2]]) == ["No project"])
    }

    @Test func aRestoredDefaultStaysDefault() {
        var book = WorkspaceBook()
        book.restoreLegacy([t[0]], name: WorkspaceSet.legacyDefaultName)
        _ = book.pass([[t[0]]])
        #expect(book.names([t[0]]) == ["Default"])
    }

    // spec: workspace-folder D24 - a "~" saved with the home folder loads as a plain "~"
    @Test func aRestoredHomeWithTheHomeFolderLoadsWithoutIt() {
        let home = NSHomeDirectory()
        let snapshot = WorkspaceSnapshot(
            version: 1, setID: UUID(), revision: 1, tabKey: t[0],
            workspaces: [
                .init(id: UUID(), name: "~", collapsed: false, folder: WorkspaceFolder.standardized(home), tabKeys: [t[0]]),
                .init(id: UUID(), name: "Home base", collapsed: false, folder: WorkspaceFolder.standardized(home), tabKeys: [t[1]]),
            ]
        )
        let set = snapshot.makeSet(home: home)
        #expect(set.workspaces.map(\.folder) == [nil, WorkspaceFolder.standardized(home)])
        var book = WorkspaceBook()
        book.adopt(snapshot)
        book.frozen = true
        _ = book.pass([[t[0], t[1], t[2]]])
        #expect(book.workspace(of: t[2])?.id == book.workspace(of: t[0])?.id)
    }

    // MARK: Merge All Windows

    @Test func aLoneUnrenamedHomeWindowJoinsTheTargetWithoutASecondHome() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.pass([[t[0], t[1], t[2]]])
        #expect(book.names([t[0], t[1], t[2]]) == ["~", "Work"])
        #expect(book.sets.count == 1)
        #expect(book.set(of: t[0])?.workspaces.count == 2)
    }

    @Test func aRenamedHomeWindowKeepsItsNameOnMerge() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2]]])
        _ = book.edit(t[2]) { $0.rename($0.workspaces[0].id, to: "Docs") }
        _ = book.pass([[t[0], t[1], t[2]]])
        #expect(book.names([t[0], t[1], t[2]]) == ["~", "Docs"])
    }

    @Test func aLegacyLoneNoProjectWindowStillJoinsTheTarget() {
        for name in [WorkspaceSet.defaultName, WorkspaceSet.legacyDefaultName] {
            var book = WorkspaceBook()
            _ = book.pass([[t[0], t[1]]])
            book.restoreLegacy([t[2]], name: name)
            _ = book.pass([[t[0], t[1]], [t[2]]])
            _ = book.pass([[t[0], t[1], t[2]]])
            #expect(book.names([t[0], t[1], t[2]]) == ["~"], "\(name)")
            #expect(book.sets.count == 1, "\(name)")
        }
    }

    @Test func isPlainTakesAFreshHomeAndTheLegacyNames() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        let fresh = book.set(of: t[0])!
        #expect(book.isPlain(fresh))
        var renamed = fresh
        let renamedOK = renamed.rename(renamed.workspaces[0].id, to: "Work")
        #expect(renamedOK)
        #expect(!book.isPlain(renamed))
        var second = fresh
        _ = second.create(name: "Second")
        #expect(!book.isPlain(second))
    }

    // MARK: Workspaces off

    @Test func workspacesOffOnAFreshHomeDoesNotMakeASecondHome() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        book.frozen = true
        _ = book.pass([[t[0], t[1]]])
        #expect(book.workspace(of: t[1])?.id == book.workspace(of: t[0])?.id)
        #expect(book.set(of: t[0])?.workspaces.count == 1)
        expectHomeOnly(book, t[0])
    }

    @Test func workspacesOffFromTheFirstPassMakesOneHome() {
        var book = WorkspaceBook()
        book.frozen = true
        _ = book.pass([[t[0]]])
        _ = book.pass([[t[0], t[1]]])
        expectHomeOnly(book, t[1])
    }
}
