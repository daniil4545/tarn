import Foundation
@testable import Ghostty

extension WorkspaceSet {
    /// The names plain groups had before the ungrouped group; restored sets keep them.
    static let defaultName = "No project"
    static let legacyDefaultName = "Default"

    /// A set with one plain group "No project" holding `tabs`.
    static func makeDefault(tabs: [TabKey]) -> WorkspaceSet {
        let workspace = Workspace(name: defaultName)
        return WorkspaceSet(
            workspaces: [workspace],
            members: Dictionary(uniqueKeysWithValues: tabs.map { ($0, workspace.id) })
        )
    }
}

extension WorkspaceBook {
    /// One pass over groups given as lists of keys; the first key of each is selected
    /// unless `selected` says otherwise.
    mutating func pass(_ groups: [[TabKey]], selected: [TabKey?]? = nil) -> Outcome {
        reconcile(groups.enumerated().map { index, tabs in
            Group(tabs: tabs, selected: selected.map { $0[index] } ?? tabs.first)
        })
    }

    /// Adds an empty workspace to the set of `tab`.
    mutating func newWorkspace(_ name: String, in tab: TabKey) -> Workspace.ID {
        var created: Workspace.ID?
        _ = edit(tab) { created = $0.create(name: name) }
        return created!
    }

    /// Restores one window as a saved set of a single plain group (a set saved before the
    /// ungrouped group): `tabs` are its members, the first is the window's tab.
    mutating func restoreLegacy(_ tabs: [TabKey], name: String = WorkspaceSet.defaultName) {
        adopt(WorkspaceSnapshot(
            version: 1, setID: UUID(), revision: 1, tabKey: tabs[0],
            workspaces: [.init(id: UUID(), name: name, collapsed: false, tabKeys: tabs)]
        ))
    }

    func names(_ group: [TabKey]) -> [String] {
        runs(for: group).map(\.workspace.name)
    }
}
