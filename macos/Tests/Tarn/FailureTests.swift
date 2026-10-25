import Foundation
import Testing
@testable import Ghostty

/// C8: what is not covered ends in a tab inside a workspace, never in a crash or a lost tab.
@Suite
struct FailureTests {
    private let t = (0..<4).map { _ in TabKey() }

    @Test func aBrokenSnapshotGivesDefaultWithAllTabs() {
        #expect(WorkspaceRestore.snapshot(from: Data("{\"version\":1,".utf8)) == nil)
        #expect(WorkspaceRestore.snapshot(from: Data("[]".utf8)) == nil)
        #expect(WorkspaceRestore.snapshot(from: nil) == nil)

        // The windows restore without a table: they are new tabs of one group.
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        #expect(book.names([t[0], t[1], t[2]]) == [WorkspaceSet.defaultName])
        #expect(book.runs(for: [t[0], t[1], t[2]])[0].tabs.count == 3)
    }

    @Test func aSnapshotOfAnotherVersionIsRefused() throws {
        var snapshot = WorkspaceSnapshot(
            version: 1, setID: UUID(), revision: 1, tabKey: t[0],
            workspaces: [.init(id: UUID(), name: "A", collapsed: false, tabKeys: [t[0]])]
        )
        snapshot.version = 9
        #expect(WorkspaceRestore.snapshot(from: try snapshot.encoded()) == nil)
    }

    @Test func aTabWhoseWorkspaceIsMissingIsPlacedAgain() {
        var set = WorkspaceSet(members: [t[0]: UUID(), t[1]: UUID()])
        _ = set.reconcile(previous: [], current: [t[0], t[1]], target: UUID())
        #expect(set.runs(order: [t[0], t[1]]).flatMap(\.tabs) == [t[0], t[1]])
    }

    @Test func aWindowThatVanishedWithoutAClosingNoticeLeavesItsSet() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        _ = book.pass([[t[0]]])
        #expect(book.set(of: t[1]) == nil)
        #expect(book.set(of: t[0])?.members.count == 1)
    }

    @Test func aTabNeverEndsOutsideAWorkspace() {
        var book = WorkspaceBook()
        // A table that lists tab 1 only; tab 0 and 2 are unknown to it.
        let id = UUID()
        let ws = Workspace(name: "Only")
        book.adopt(WorkspaceSnapshot(
            version: 1, setID: id, revision: 1, tabKey: t[1],
            workspaces: [.init(id: ws.id, name: "Only", collapsed: false, tabKeys: [t[1]])]
        ))
        _ = book.pass([[t[0], t[1], t[2]]])
        #expect(book.runs(for: [t[0], t[1], t[2]]).flatMap(\.tabs).count == 3)
    }
}
