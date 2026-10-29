import Foundation

/// The identity of one tab window, made by us and persisted in the snapshot. A key is
/// never an `ObjectIdentifier`: those are reused and do not survive a relaunch.
typealias TabKey = UUID

/// A named group of tabs in the sidebar.
struct Workspace: Equatable, Identifiable, Codable {
    var id = UUID()
    var name: String
    var collapsed = false
    /// The project folder (D19): absolute and standardized; nil for "No project".
    var folder: String?
}

/// The workspaces of one Ghostty window and which tab sits in which one.
///
/// Ghostty alone writes the order of tabs; this value stores only membership. Workspaces are
/// drawn in the order of their first tab, so their order is derived and never stored
/// (`docs/modules/workspaces.md`).
struct WorkspaceSet: Equatable {
    /// One block of the sidebar. Not part of the stored state: a workspace with its tabs, or
    /// the ungrouped tabs between two workspaces (`workspace` is nil, no header).
    struct Run: Equatable {
        let workspace: Workspace?
        fileprivate(set) var tabs: [TabKey]

        /// The workspace, or the first tab of an ungrouped run (as `SidebarModel.Group.id`).
        var id: UUID { workspace?.id ?? tabs[0] }
    }

    /// What closing a tab did to its workspace.
    enum Removal: Equatable {
        case notMember
        case stayed
        /// It was the last tab, so the workspace is gone.
        case workspaceClosed(Workspace)
    }

    let id: UUID
    /// Unordered. Use `runs(order:)` for the order on screen.
    private(set) var workspaces: [Workspace]
    private(set) var members: [TabKey: Workspace.ID]
    private(set) var revision: Int

    init(
        id: UUID = UUID(),
        workspaces: [Workspace] = [],
        members: [TabKey: Workspace.ID] = [:],
        revision: Int = 0
    ) {
        self.id = id
        self.workspaces = workspaces
        self.members = members
        self.revision = revision
    }

    // MARK: Queries

    func workspace(_ id: Workspace.ID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    func workspace(of tab: TabKey) -> Workspace? {
        members[tab].flatMap { workspace($0) }
    }

    func tabs(in workspace: Workspace.ID) -> [TabKey] {
        members.filter { $0.value == workspace }.map(\.key)
    }

    /// The blocks of `order` from top to bottom. A workspace stands where its first tab is and holds
    /// all its tabs; a tab with no workspace joins the ungrouped block it follows. A workspace
    /// without a tab in `order` is left out.
    func runs(order: [TabKey]) -> [Run] {
        var runs: [Run] = []
        var place: [Workspace.ID: Int] = [:]
        for tab in order {
            if let id = members[tab], let workspace = workspace(id) {
                if let at = place[id] {
                    runs[at].tabs.append(tab)
                } else {
                    place[id] = runs.count
                    runs.append(Run(workspace: workspace, tabs: [tab]))
                }
            } else if let last = runs.indices.last, runs[last].workspace == nil {
                runs[last].tabs.append(tab)
            } else {
                runs.append(Run(workspace: nil, tabs: [tab]))
            }
        }
        return runs
    }

    // MARK: Edits

    /// Adds an empty workspace and returns it, or nil for a blank name or a folder that is not
    /// an absolute path. The workspace gets its tab right after; until then it is in no run.
    mutating func create(name: String, folder: String? = nil) -> Workspace.ID? {
        guard let name = Self.cleaned(name) else { return nil }
        var workspace = Workspace(name: name)
        if let folder {
            guard let path = WorkspaceFolder.standardized(folder) else { return nil }
            workspace.folder = path
        }
        workspaces.append(workspace)
        revision += 1
        return workspace.id
    }

    @discardableResult
    mutating func rename(_ id: Workspace.ID, to name: String) -> Bool {
        guard let name = Self.cleaned(name), let index = workspaces.firstIndex(where: { $0.id == id }),
              workspaces[index].name != name
        else { return false }
        workspaces[index].name = name
        revision += 1
        return true
    }

    /// The first tab of the workspace that holds `folder` (Q1).
    func firstTab(inFolder folder: String, order: [TabKey]) -> TabKey? {
        runs(order: order).first { $0.workspace?.folder == folder }?.tabs.first
    }

    /// The last tab of workspace `id` in `order`: the parent of its "+" tab (S6).
    func lastTab(of id: Workspace.ID, order: [TabKey]) -> TabKey? {
        runs(order: order).last { $0.workspace?.id == id }?.tabs.last
    }

    mutating func setCollapsed(_ id: Workspace.ID, _ collapsed: Bool) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }),
              workspaces[index].collapsed != collapsed
        else { return }
        workspaces[index].collapsed = collapsed
        revision += 1
    }

    /// Adds a workspace that already has an identity, for an undone close.
    mutating func add(_ workspace: Workspace) {
        guard self.workspace(workspace.id) == nil else { return }
        workspaces.append(workspace)
        revision += 1
    }

    /// Puts `tab` in `workspace`, leaving the one it was in; a workspace left empty goes.
    mutating func join(_ tab: TabKey, to workspace: Workspace.ID) {
        guard self.workspace(workspace) != nil, members[tab] != workspace else { return }
        let old = members.updateValue(workspace, forKey: tab)
        if let old, !members.values.contains(old) { workspaces.removeAll { $0.id == old } }
        revision += 1
    }

    /// Removes the tab; the workspace closes with its last tab. A workspace that never
    /// had a tab is not touched.
    @discardableResult
    mutating func remove(_ tab: TabKey) -> Removal {
        guard let id = members.removeValue(forKey: tab) else { return .notMember }
        revision += 1
        guard !members.values.contains(id), let index = workspaces.firstIndex(where: { $0.id == id })
        else { return .stayed }
        return .workspaceClosed(workspaces.remove(at: index))
    }

    /// Deletes a workspace; its tabs go to the one above, or below when it is first.
    /// The last workspace is never deleted. Returns false when nothing changed.
    @discardableResult
    mutating func delete(_ id: Workspace.ID, order: [TabKey]) -> Bool {
        guard workspaces.count > 1, workspace(id) != nil else { return false }
        let runs = runs(order: order).filter { $0.workspace != nil }
        if let index = runs.firstIndex(where: { $0.workspace?.id == id }) {
            let neighbour = index > 0 ? runs[index - 1] : runs[safe: index + 1]
            if let heir = neighbour?.workspace?.id {
                for tab in runs[index].tabs { members[tab] = heir }
            }
        }
        // Members that are not on screen (a window still being restored) follow the same rule.
        let heir = workspaces.first { $0.id != id }?.id
        for (tab, owner) in members where owner == id {
            if let heir { members[tab] = heir }
        }
        workspaces.removeAll { $0.id == id }
        revision += 1
        return true
    }

    /// Appends every workspace and tab of `other` unchanged, for Merge All Windows.
    mutating func absorb(_ other: WorkspaceSet) {
        workspaces.append(contentsOf: other.workspaces)
        members.merge(other.members) { current, _ in current }
        revision += 1
    }

    static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
