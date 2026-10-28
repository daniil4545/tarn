import Foundation
import Testing
@testable import Ghostty

/// Sets across merge, restore and undo.
@Suite
struct MergeTests {
    private let t = (0..<6).map { _ in TabKey() }

    // spec: docs/specs/workspace-folder.md S54, I1
    @Test func mergeAllWindowsKeepsTheFirstSetAndPutsAllUngroupedTabsInOneRunLast() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2], t[3]]])
        let first = book.newWorkspace("First", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: first) }
        let other = book.newWorkspace("Other", in: t[2])
        _ = book.edit(t[2]) { $0.join(t[2], to: other) }
        let set = book.set(of: t[0])?.id

        // Merge All Windows appends the second window: [First, ~ | Other, ~].
        let outcome = book.pass([[t[0], t[1], t[2], t[3]]])
        #expect(book.set(of: t[3])?.id == set)
        #expect(book.sets.count == 1)
        #expect(book.set(of: t[0])?.workspaces.filter { book.set(of: t[0])!.isUngrouped($0) }.count == 1)
        #expect(book.workspace(of: t[1])?.id == book.workspace(of: t[3])?.id)
        #expect(book.workspace(of: t[0])?.id == first)
        #expect(book.workspace(of: t[2])?.id == other)
        // t2 (Other) has to move above the ungrouped t1: one native move.
        #expect(outcome.reorders == [.init(tab: t[2], delta: -1)])
    }

    // spec: docs/specs/workspace-folder.md S4, G4. Cmd+T: the new tab is seen alone in its window
    // first, then enters the group of the window selected (Ghostty selects the new tab).
    @Test func aNewTabSeenAloneAndSelectedTakesTheTargetNotAMerge() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[3]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: work) }
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.selected(t[0])
        _ = book.pass([[t[0], t[1], t[3]], [t[2]]])
        // In the app Ghostty has selected the new tab by this pass. It stands right after the source t0.
        let outcome = book.pass([[t[0], t[2], t[1], t[3]]], selected: [t[2]])
        #expect(book.workspace(of: t[2])?.id == work)
        #expect(outcome.reorders.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S55 through the book: `end` puts the tab last, it goes to the end of its group
    @Test func aNewTabAtTheEndSeenAloneGoesToTheEndOfItsGroup() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[3]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: work) }
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.selected(t[0])
        _ = book.pass([[t[0], t[1], t[3]], [t[2]]])
        let outcome = book.pass([[t[0], t[1], t[3], t[2]]], selected: [t[2]])
        #expect(book.workspace(of: t[2])?.id == work)
        #expect(outcome.reorders == [.init(tab: t[2], delta: -1)])
    }

    // spec: docs/specs/workspace-folder.md S54 through the book: windows made by Cmd+N merge into a
    // window that has ungrouped tabs; the selected tab is the receiving window's.
    @Test func lonelyWindowsMergedIntoAWindowWithUngroupedTabsStayUngrouped() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[4]], [t[2]], [t[3]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: work) }
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        let outcome = book.pass([[t[0], t[1], t[4], t[2], t[3]]], selected: [t[0]])
        let set = book.set(of: t[0])!
        #expect(book.sets.count == 1)
        #expect(set.members[t[0]] == work)
        #expect(set.members[t[1]] == work)
        #expect(set.members[t[2]] == set.id)
        #expect(set.members[t[3]] == set.id)
        #expect(outcome.reorders.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S54, the receiving window has groups only (Cmd+N, then Merge)
    @Test func aLonelyWindowMergedIntoGroupsOnlyStaysUngrouped() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: work) }
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.pass([[t[0], t[1], t[2]]], selected: [t[0]])
        #expect(book.workspace(of: t[0])?.id == work)
        #expect(book.set(of: t[2]).map { $0.isUngrouped(book.workspace(of: t[2])!) } == true)
    }

    // G5a, the price of the rule: a whole one-tab window dropped into the middle of another group joins it.
    @Test func aSelectedOneTabWindowDroppedInsideAGroupJoinsThatGroup() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[3]], [t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: work) }
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.pass([[t[0], t[2], t[1], t[3]]], selected: [t[2]])
        #expect(book.workspace(of: t[2])?.id == work)
    }

    // spec: docs/specs/workspace-folder.md S54 - a window of groups only with one of ungrouped tabs only
    @Test func mergeOfGroupsOnlyWithUngroupedOnlyKeepsEveryGroupAbove() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2], t[3]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: work) }
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.pass([[t[2], t[3], t[0], t[1]]])
        #expect(book.workspace(of: t[0])?.id == work)
        #expect(book.workspace(of: t[1])?.id == work)
        #expect(book.set(of: t[2])?.isUngrouped(book.workspace(of: t[2])!) == true)
        #expect(book.set(of: t[3])?.isUngrouped(book.workspace(of: t[3])!) == true)
        #expect(book.sets.count == 1)
        // The other way round: groups first, no move.
        var again = WorkspaceBook()
        _ = again.pass([[t[0], t[1]], [t[2], t[3]]])
        let w2 = again.newWorkspace("Work", in: t[0])
        _ = again.edit(t[0]) { $0.join(t[0], to: w2) }
        _ = again.edit(t[1]) { $0.join(t[1], to: w2) }
        #expect(again.pass([[t[0], t[1], t[2], t[3]]]).reorders.isEmpty)
    }

    @Test func aReopenedTabGoesBackToItsWorkspace() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: work) }
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        let closed = book.closing(t[1])
        #expect(closed?.workspace.name == "Work")

        book.reinsert(t[3], from: closed!)
        #expect(book.workspace(of: t[3])?.id == work)
        let outcome = book.pass([[t[0], t[3], t[2]]])
        #expect(outcome.reorders.isEmpty)
        #expect(book.names([t[0], t[3], t[2]]) == ["Work", "~"])
    }

    @Test func aReopenedWindowRecreatesItsSetAndGroupWithoutAnEmptyUngroupedGroup() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        let solo = book.newWorkspace("Solo", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: solo) }
        _ = book.pass([[t[0]]])
        let closed = book.closing(t[0])!
        #expect(book.sets.isEmpty)

        book.reinsert(t[1], from: closed)
        _ = book.pass([[t[1]]])
        #expect(book.names([t[1]]) == ["Solo"])
        #expect(book.sets.count == 1)
        #expect(book.set(of: t[1])?.id == closed.set.id)
    }

    @Test func closingTheLastTabOfAWorkspaceClosesIt() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.closing(t[1])
        _ = book.pass([[t[0]]])
        #expect(book.names([t[0]]) == ["~"])
        #expect(book.set(of: t[0])?.workspaces.count == 1)
    }

    @Test func theHigherRevisionTableWinsOnRestore() throws {
        var book = WorkspaceBook()
        let setID = UUID()
        let ws = Workspace(name: "Old")
        let older = WorkspaceSnapshot(
            version: 1, setID: setID, revision: 2, tabKey: t[0],
            workspaces: [.init(id: ws.id, name: "Old", collapsed: false, tabKeys: [t[0], t[1]])]
        )
        var newer = older
        newer.revision = 5
        newer.tabKey = t[1]
        newer.workspaces[0].name = "New"

        book.adopt(older)
        book.adopt(newer)
        book.adopt(older)
        #expect(book.set(of: t[0])?.workspace(ws.id)?.name == "New")
        #expect(book.set(of: t[1])?.id == setID)
    }

    @Test func restoredWindowsInSeparateGroupsKeepTheirSharedSet() {
        var book = WorkspaceBook()
        let setID = UUID()
        let ws = Workspace(name: "Work")
        func snap(_ key: TabKey) -> WorkspaceSnapshot {
            WorkspaceSnapshot(
                version: 1, setID: setID, revision: 1, tabKey: key,
                workspaces: [.init(id: ws.id, name: "Work", collapsed: false, tabKeys: [t[0], t[1]])]
            )
        }
        book.adopt(snap(t[0]))
        book.adopt(snap(t[1]))

        // AppKit has not joined the two windows yet; two passes must not split the set.
        _ = book.pass([[t[0]], [t[1]]])
        _ = book.pass([[t[0]], [t[1]]])
        #expect(book.set(of: t[0])?.id == setID)
        #expect(book.set(of: t[1])?.id == setID)

        _ = book.pass([[t[0], t[1]]])
        #expect(book.names([t[0], t[1]]) == ["Work"])
        #expect(book.set(of: t[0])?.id == setID)
    }

    // MARK: Same result for any order of the groups

    private func workWindowSplit(_ groups: [[TabKey]]) -> WorkspaceBook {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.edit(t[2]) { $0.join(t[2], to: work) }
        // t2 leaves for its own window.
        _ = book.pass(groups)
        return book
    }

    @Test func aTabTakenOutOfANamedWorkspaceGivesTheSameResultInAnyGroupOrder() {
        for groups in [[[t[0], t[1]], [t[2]]], [[t[2]], [t[0], t[1]]]] {
            let book = workWindowSplit(groups)
            #expect(book.names([t[0], t[1]]) == ["~", "Work"])
            #expect(book.names([t[2]]) == ["~"])
            #expect(book.set(of: t[2])?.id != book.set(of: t[0])?.id)
        }
    }

    @Test func aRestoreSeenOneWindowAtATimeKeepsTheSetInAnyGroupOrder() {
        for order in [[0, 1], [1, 0]] {
            var book = WorkspaceBook()
            let setID = UUID()
            let ws = Workspace(name: "Work")
            func snap(_ key: TabKey) -> WorkspaceSnapshot {
                WorkspaceSnapshot(
                    version: 1, setID: setID, revision: 1, tabKey: key,
                    workspaces: [.init(id: ws.id, name: "Work", collapsed: false, tabKeys: [t[0], t[1]])]
                )
            }
            book.adopt(snap(t[0]))
            _ = book.pass([[t[0]]])
            book.adopt(snap(t[1]))
            _ = book.pass(order.map { [t[$0]] })
            #expect(book.set(of: t[0])?.id == setID)
            #expect(book.set(of: t[1])?.id == setID)
            #expect(book.names([t[0], t[1]]) == ["Work"])
        }
    }

    // MARK: A window of one tab

    @Test func mergeAllKeepsTheNameOfAOneTabWindowsWorkspace() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2]]])
        let docs = book.newWorkspace("Docs", in: t[2])
        _ = book.edit(t[2]) { $0.join(t[2], to: docs) }
        _ = book.pass([[t[0], t[1], t[2]]])
        #expect(book.names([t[0], t[1], t[2]]) == ["~", "Docs"])
        #expect(book.sets.count == 1)
    }

    @Test func aStockDefaultWindowOfOneTabJoinsTheTargetInsteadOfAddingASecondDefault() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2]]])
        _ = book.pass([[t[0], t[1], t[2]]])
        #expect(book.names([t[0], t[1], t[2]]) == ["~"])
    }
}
