import Foundation

/// The identity of one tab window, made by us and persisted in the snapshot. A key is
/// never an `ObjectIdentifier`: those are reused and do not survive a relaunch.
typealias TabKey = UUID

/// A named group of tabs in the sidebar.
struct Workspace: Equatable, Identifiable, Codable {
    var id = UUID()
    var name: String
    var collapsed = false
}

/// The workspaces of one Ghostty window and which tab sits in which one.
///
/// Ghostty alone writes the order of tabs; this value stores only membership. A workspace is
/// a contiguous run of the native tab order, so workspace order is derived from the order of
/// tabs and never stored (`docs/plans/s3-windows-contracts.md` section 1).
struct WorkspaceSet: Equatable {
    static let defaultName = "Default"

    /// One window's workspaces. Not part of the stored state.
    struct Run: Equatable {
        let workspace: Workspace
        let tabs: [TabKey]
    }

    /// A single native move Ghostty has to make so a new tab ends its workspace's run:
    /// `delta` is the amount of the `move_tab` action.
    struct Reorder: Equatable {
        let tab: TabKey
        let delta: Int
    }

    /// What closing a tab did to its workspace.
    enum Removal: Equatable {
        case notMember
        case stayed
        /// It was the last tab, so the workspace is gone (D12).
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

    /// A set with `Default` holding `tabs` (D1, D10).
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

    /// Each workspace of `order` forms one unbroken run.
    func isContiguous(_ order: [TabKey]) -> Bool {
        var closed = Set<Workspace.ID>()
        var current: Workspace.ID?
        for tab in order {
            guard let id = members[tab] else { continue }
            if id == current { continue }
            if closed.contains(id) { return false }
            if let current { closed.insert(current) }
            current = id
        }
        return true
    }

    // MARK: Edits

    /// Adds an empty workspace and returns it, or nil for a blank name (D3). The workspace
    /// gets its tab right after (S4); until then it is in no run.
    mutating func create(name: String) -> Workspace.ID? {
        guard let name = Self.cleaned(name) else { return nil }
        let workspace = Workspace(name: name)
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

    mutating func setCollapsed(_ id: Workspace.ID, _ collapsed: Bool) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }),
              workspaces[index].collapsed != collapsed
        else { return }
        workspaces[index].collapsed = collapsed
        revision += 1
    }

    /// Puts `tab` in `workspace`, leaving the one it was in.
    mutating func join(_ tab: TabKey, to workspace: Workspace.ID) {
        guard self.workspace(workspace) != nil, members[tab] != workspace else { return }
        members[tab] = workspace
        revision += 1
    }

    /// Removes the tab; the workspace closes with its last tab (D12). A workspace that never
    /// had a tab is not touched.
    @discardableResult
    mutating func remove(_ tab: TabKey) -> Removal {
        guard let id = members.removeValue(forKey: tab) else { return .notMember }
        revision += 1
        guard !members.values.contains(id), let index = workspaces.firstIndex(where: { $0.id == id })
        else { return .stayed }
        return .workspaceClosed(workspaces.remove(at: index))
    }

    /// Deletes a workspace; its tabs go to the one above, or below when it is first (D13).
    /// The last workspace is never deleted (D4). Returns false when nothing changed.
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

    /// Appends every workspace and tab of `other` unchanged, for Merge All Windows (C6).
    mutating func absorb(_ other: WorkspaceSet) {
        workspaces.append(contentsOf: other.workspaces)
        members.merge(other.members) { current, _ in current }
        revision += 1
    }

    /// Drops workspaces that hold no tab, except `keep`.
    mutating func removeEmpty(keeping keep: Workspace.ID? = nil) {
        let used = Set(members.values)
        let before = workspaces.count
        workspaces.removeAll { !used.contains($0.id) && $0.id != keep }
        if workspaces.count != before { revision += 1 }
    }

    // MARK: Following Ghostty

    /// Brings membership in line with a native order that changed behind our back
    /// (`docs/plans/s3-windows-contracts.md` section 3).
    ///
    /// - Parameters:
    ///   - previous: the relative order of the tabs at the last look.
    ///   - current: the native order now, new tabs included.
    ///   - target: where a tab with no workspace goes (section 4).
    /// - Returns: the native moves that put each new tab at the end of its workspace's run.
    ///   Membership is already final; the caller makes the moves.
    mutating func reconcile(previous: [TabKey], current: [TabKey], target: Workspace.ID) -> [Reorder] {
        let before = self
        let fresh = current.filter { members[$0] == nil }
        if !fresh.isEmpty {
            let heir = ensureWorkspace(target)
            for tab in fresh { members[tab] = heir }
        }

        let known = current.filter { !fresh.contains($0) }
        if !isContiguous(known) {
            repair(known, previous: previous.filter(known.contains))
        }

        var reorders: [Reorder] = []
        var order = current
        for tab in fresh {
            guard let index = order.firstIndex(of: tab), let id = members[tab] else { continue }
            order.remove(at: index)
            let lastPeer = order.lastIndex { members[$0] == id }
            let destination = lastPeer.map { $0 + 1 } ?? order.count
            order.insert(tab, at: destination)
            if destination != index { reorders.append(Reorder(tab: tab, delta: destination - index)) }
        }

        if members != before.members || workspaces != before.workspaces { revision = before.revision + 1 }
        return reorders
    }

    /// Makes the workspaces of `known` contiguous again. Ghostty moves one tab at a time, so
    /// first look for the tab whose removal leaves the others in their old order; it joins
    /// the workspace of its upper neighbour, or its lower one when it is first. If that does
    /// not heal the order, every tab outside the first run of its workspace joins the
    /// workspace above it.
    private mutating func repair(_ known: [TabKey], previous: [TabKey]) {
        if previous.count == known.count {
            let mover = known.first { tab in
                known.filter { $0 != tab } == previous.filter { $0 != tab }
            }
            if let mover, let index = known.firstIndex(of: mover) {
                let neighbour = index > 0 ? known[index - 1] : known[safe: index + 1]
                if let id = neighbour.flatMap({ members[$0] }) { members[mover] = id }
                if isContiguous(known) { return }
            }
        }

        var closed = Set<Workspace.ID>()
        var current: Workspace.ID?
        for (index, tab) in known.enumerated() {
            guard let id = members[tab] else { continue }
            if id == current { continue }
            if closed.contains(id), index > 0, let above = members[known[index - 1]] {
                members[tab] = above
                continue
            }
            if let current { closed.insert(current) }
            current = id
        }
    }

    /// `target` when it exists, else the first workspace, else a new `Default`.
    private mutating func ensureWorkspace(_ target: Workspace.ID) -> Workspace.ID {
        if workspace(target) != nil { return target }
        if let first = workspaces.first { return first.id }
        let created = Workspace(name: Self.defaultName)
        workspaces.append(created)
        return created.id
    }

    private static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
