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

    /// Adds an empty workspace to the set of `tab`.
    mutating func newWorkspace(_ name: String, in tab: TabKey) -> Workspace.ID {
        var created: Workspace.ID?
        _ = edit(tab) { created = $0.create(name: name) }
        return created!
    }

    func names(_ group: [TabKey]) -> [String] {
        runs(for: group).map(\.workspace.name)
    }
}
