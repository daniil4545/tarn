import Foundation
import Testing
@testable import Ghostty

/// Sets of ungrouped tabs, and what an older build saved (`docs/specs/workspace-folder.md` G1, G13).
@Suite
struct UngroupedTests {
    private let t = (0..<6).map { _ in TabKey() }
    private let home = NSHomeDirectory()

    private func snapshot(_ entries: [WorkspaceSnapshot.Entry], tab: TabKey? = nil) -> WorkspaceSnapshot {
        WorkspaceSnapshot(version: 1, setID: UUID(), revision: 1, tabKey: tab ?? t[0], workspaces: entries)
    }

    private func entry(_ name: String, folder: String? = nil, tabs: [TabKey]) -> WorkspaceSnapshot.Entry {
        .init(id: UUID(), name: name, collapsed: false, folder: folder, tabKeys: tabs)
    }

    /// spec: docs/specs/workspace-folder.md S50
    @Test func anOldHomeWorkspaceLoadsAsUngroupedTabsAndTheOthersStay() {
        let homeFolder = WorkspaceFolder.standardized(home)
        for folder in [nil, homeFolder] {
            let set = snapshot([
                entry("tarn", folder: "/p/tarn", tabs: [t[0]]),
                entry("~", folder: folder, tabs: [t[1], t[2]]),
            ]).makeSet(home: home)
            #expect(set.workspaces.map(\.name) == ["tarn"])
            #expect(set.runs(order: Array(t[0...2])).map { $0.workspace?.name } == ["tarn", nil])
            #expect(set.runs(order: Array(t[0...2])).last?.tabs == [t[1], t[2]])
        }
    }

    /// spec: docs/specs/workspace-folder.md S50
    @Test func aHomeWorkspaceThatIsNotTheStartOneStays() {
        let homeFolder = WorkspaceFolder.standardized(home)
        let set = snapshot([
            entry("~", folder: "/p/F", tabs: [t[0]]),
            entry("Home base", folder: homeFolder, tabs: [t[1]]),
        ]).makeSet(home: home)
        #expect(set.workspaces.map(\.name) == ["~", "Home base"])
        #expect(set.workspaces.map(\.folder) == ["/p/F", homeFolder])
    }

    /// spec: docs/specs/workspace-folder.md S50
    @Test func aSetOfOnlyAnOldHomeLoadsWithNoGroupAndTheBookKeepsItsTabs() {
        var book = WorkspaceBook()
        book.adopt(snapshot([entry("~", tabs: [t[0], t[1]])]))
        _ = book.pass([[t[0], t[1]]])
        #expect(book.names([t[0], t[1]]) == ["-"])
        #expect(book.set(of: t[0])?.workspaces.isEmpty == true)
    }

    @Test func noProjectAndDefaultStayPlainGroups() {
        for name in ["No project", "Default"] {
            var book = WorkspaceBook()
            book.restoreLegacy([t[0], t[1]], name: name)
            _ = book.pass([[t[0], t[1]]])
            #expect(book.names([t[0], t[1]]) == [name])
            // A tab no rule placed is ungrouped, next to the old group.
            _ = book.pass([[t[0], t[1], t[2]]])
            #expect(book.names([t[0], t[1], t[2]]) == [name, "-"], "\(name)")
        }
    }

    @Test func aLoneOldNoProjectWindowKeepsItsGroupOnMerge() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        book.restoreLegacy([t[2]])
        _ = book.pass([[t[0], t[1]], [t[2]]])
        _ = book.pass([[t[0], t[1], t[2]]])
        #expect(book.names([t[0], t[1], t[2]]) == ["-", "No project"])
        #expect(book.sets.count == 1)
    }
}
