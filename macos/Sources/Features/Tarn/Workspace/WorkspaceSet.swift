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
    static let defaultName = "No project"
    /// The name sets had before "No project"; restored sets keep it.
    static let legacyDefaultName = "Default"
    /// The start workspace of a fresh set and the target of Workspaces off. It has no folder, so
    /// its tabs and splits open where Ghostty opens them.
    static let homeName = "~"

    /// One window's workspaces. Not part of the stored state.
    struct Run: Equatable {
        let workspace: Workspace
        let tabs: [TabKey]
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

    /// A set with `No project` holding `tabs`.
    static func makeDefault(tabs: [TabKey]) -> WorkspaceSet {
        let workspace = Workspace(name: defaultName)
        return WorkspaceSet(
            workspaces: [workspace],
            members: Dictionary(uniqueKeysWithValues: tabs.map { ($0, workspace.id) })
        )
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

    /// The workspaces of `order` from top to bottom, each with its tabs in tab order.
    /// A workspace without a tab in `order` is left out; so is a tab without a workspace.
    func runs(order: [TabKey]) -> [Run] {
        var ids: [Workspace.ID] = []
        var byWorkspace: [Workspace.ID: [TabKey]] = [:]
        for tab in order {
            guard let id = members[tab], workspace(id) != nil else { continue }
            if byWorkspace[id] == nil { ids.append(id) }
            byWorkspace[id, default: []].append(tab)
        }
        return ids.compactMap { id in
            workspace(id).map { Run(workspace: $0, tabs: byWorkspace[id] ?? []) }
        }
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
        runs(order: order).first { $0.workspace.folder == folder }?.tabs.first
    }

    /// The last tab of workspace `id` in `order`: the parent of its "+" tab (S6).
    func lastTab(of id: Workspace.ID, order: [TabKey]) -> TabKey? {
        runs(order: order).last { $0.workspace.id == id }?.tabs.last
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
        let runs = runs(order: order)
        if let index = runs.firstIndex(where: { $0.workspace.id == id }) {
            let neighbour = index > 0 ? runs[index - 1] : runs[safe: index + 1]
            if let heir = neighbour?.workspace.id {
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

    // MARK: Following Ghostty

    /// A tab with no workspace joins "~"; a new "~" is made when the set has none. The order of
    /// the tabs is Ghostty's and decides nothing here.
    mutating func reconcile(current: [TabKey]) {
        let fresh = current.filter { members[$0].flatMap { workspace($0) } == nil }
        guard !fresh.isEmpty else { return }
        let target: Workspace.ID
        if let existing = workspaces.first(where: Self.isHome) {
            target = existing.id
        } else {
            let created = Self.makeHome()
            workspaces.append(created)
            target = created.id
        }
        for tab in fresh { members[tab] = target }
        revision += 1
    }

    static func makeHome() -> Workspace {
        Workspace(name: homeName)
    }

    static func isHome(_ workspace: Workspace) -> Bool {
        workspace.name == homeName && workspace.folder == nil
    }

    static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
