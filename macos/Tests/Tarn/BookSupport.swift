import Foundation
@testable import Ghostty

extension WorkspaceBook {
    /// One pass over groups given as lists of keys; the first key of each is selected
    /// unless `selected` says otherwise.
    mutating func pass(_ groups: [[TabKey]], selected: [TabKey?]? = nil) -> Outcome {
        reconcile(groups.enumerated().map { index, tabs in
            Group(tabs: tabs, selected: selected.map { $0[index] } ?? tabs.first)
        })
    }

    /// Adds a workspace to the set of `tabs[0]` and puts `tabs` in it.
    @discardableResult
    mutating func group(_ name: String, _ tabs: [TabKey]) -> Workspace.ID {
        let id = newWorkspace(name, in: tabs[0])
        for tab in tabs { _ = edit(tab) { $0.join(tab, to: id) } }
        return id
    }

    /// Adds an empty workspace to the set of `tab`.
    mutating func newWorkspace(_ name: String, in tab: TabKey) -> Workspace.ID {
        var created: Workspace.ID?
        _ = edit(tab) { created = $0.create(name: name) }
        return created!
    }

    /// Restores one window as a saved set of a single folderless workspace (a set saved by an
    /// older build): `tabs` are its members, the first is the window's tab.
    mutating func restoreLegacy(_ tabs: [TabKey], name: String = "No project") {
        adopt(WorkspaceSnapshot(
            version: 1, setID: UUID(), revision: 1, tabKey: tabs[0],
            workspaces: [.init(id: UUID(), name: name, collapsed: false, tabKeys: tabs)]
        ))
    }

    /// The sidebar blocks of `group` top to bottom: a workspace name, or "-" for ungrouped tabs.
    func names(_ group: [TabKey]) -> [String] {
        runs(for: group).map { $0.workspace?.name ?? "-" }
    }
}
