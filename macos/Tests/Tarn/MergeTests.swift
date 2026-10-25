import Foundation
import Testing
@testable import Ghostty

/// C6: sets across merge, restore and undo.
@Suite
struct MergeTests {
    private let t = (0..<6).map { _ in TabKey() }

    @Test func mergeAllWindowsKeepsTheFirstSetAndAppendsTheOthersWhole() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2], t[3]]])
        let other = book.newWorkspace("Other", in: t[2])
        _ = book.edit(t[3]) { $0.join(t[3], to: other) }
        let first = book.set(of: t[0])?.id

        _ = book.pass([[t[0], t[1], t[2], t[3]]])
        #expect(book.names(Array(t[0...3])) == ["Default", "Default", "Other"])
        #expect(book.set(of: t[3])?.id == first)
        #expect(book.sets.count == 1)
    }

    @Test func aReopenedTabGoesBackToItsWorkspace() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.edit(t[2]) { $0.join(t[2], to: work) }
        let closed = book.closing(t[2], order: [t[0], t[1], t[2]])
        #expect(closed?.workspace.name == "Work")
        #expect(closed?.runIndex == 1)

        book.reinsert(t[3], from: closed!)
        #expect(book.workspace(of: t[3])?.id == work)
        let outcome = book.pass([[t[0], t[1], t[3]]])
        #expect(outcome.reorders.isEmpty)
        #expect(book.names([t[0], t[1], t[3]]) == ["Default", "Work"])
    }

    @Test func aReopenedWindowRecreatesItsSetAndWorkspaceWithoutAnEmptyDefault() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        _ = book.edit(t[0]) { $0.rename($0.workspaces[0].id, to: "Solo") }
        let closed = book.closing(t[0], order: [t[0]])!
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
        _ = book.closing(t[1], order: [t[0], t[1]])
        _ = book.pass([[t[0]]])
        #expect(book.names([t[0]]) == ["Default"])
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
}
