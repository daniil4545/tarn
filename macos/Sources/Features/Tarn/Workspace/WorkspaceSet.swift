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
/// Ghostty alone writes the order of tabs; this value stores only membership. A workspace is
/// a contiguous run of the native tab order, so workspace order is derived from the order of
/// tabs and never stored (`docs/modules/workspaces.md`).
struct WorkspaceSet: Equatable {
    /// The stored name of the ungrouped group (I1), so an older build rolls back to its start
    /// workspace. It has no folder: its tabs and splits open where Ghostty opens them.
    static let homeName = "~"

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

    /// The ungrouped group is the one whose id is the set's id (I1).
    func isUngrouped(_ workspace: Workspace) -> Bool {
        workspace.id == id
    }

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

    /// Each workspace of `order` forms one unbroken run and the ungrouped run is last.
    func isContiguous(_ order: [TabKey]) -> Bool {
        var closed = Set<Workspace.ID>()
        var current: Workspace.ID?
        for tab in order {
            guard let id = members[tab] else { continue }
            if id == current { continue }
            if closed.contains(id) { return false }
            // A tab of a group below the ungrouped run is a break (I2).
            if current == self.id { return false }
            if let current { closed.insert(current) }
            current = id
        }
        return true
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

    mutating func setCollapsed(_ id: Workspace.ID, _ collapsed: Bool) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }),
              workspaces[index].collapsed != collapsed
        else { return }
        workspaces[index].collapsed = collapsed
        revision += 1
    }

    /// The ungrouped group, made when missing. The only place that makes it (I1).
    @discardableResult
    mutating func ungroupedID() -> Workspace.ID {
        if workspace(id) == nil {
            workspaces.append(Workspace(id: id, name: Self.homeName))
            revision += 1
        }
        return id
    }

    /// Adds a workspace that already has an identity, for an undone close. A known id is
    /// refused, so a second ungrouped group cannot be added (I1).
    mutating func add(_ workspace: Workspace) {
        guard self.workspace(workspace.id) == nil else { return }
        workspaces.append(workspace)
        revision += 1
    }

    /// Puts `tab` in `workspace`, leaving the one it was in.
    mutating func join(_ tab: TabKey, to workspace: Workspace.ID) {
        guard self.workspace(workspace) != nil, members[tab] != workspace else { return }
        members[tab] = workspace
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

    /// Appends every group and tab of `other` for Merge All Windows; its ungrouped tabs join
    /// the ungrouped group of this set (I1).
    mutating func absorb(_ other: WorkspaceSet) {
        workspaces.append(contentsOf: other.workspaces.filter { !other.isUngrouped($0) })
        for (tab, owner) in other.members where members[tab] == nil {
            members[tab] = owner == other.id ? ungroupedID() : owner
        }
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
    /// (`docs/modules/workspaces.md`).
    ///
    /// - Parameters:
    ///   - previous: the relative order of the tabs at the last look.
    ///   - current: the native order now, new tabs included.
    ///   - target: where a tab with no workspace goes (section 4); the ungrouped group when it is gone.
    ///   - selected: the selected tab, the mover of a swap of neighbours (I2).
    ///   - explicit: a sidebar command named `target`, so a new tab goes to the end of its run (G4).
    ///   - arrivals: tabs dragged in from another window; they join the group of their neighbour (G5a).
    ///   - repairs: false after a merge, which settles the ungrouped run instead of the mover rule.
    /// - Returns: the native moves for new tabs and for the ungrouped run. Membership is already
    ///   final; the caller makes the moves.
    mutating func reconcile(
        previous: [TabKey], current: [TabKey], target: Workspace.ID,
        selected: TabKey? = nil, explicit: Bool = false, arrivals: Set<TabKey> = [], repairs: Bool = true
    ) -> [Reorder] {
        let before = self
        let fresh = current.filter { members[$0].flatMap { workspace($0) } == nil }
        if !fresh.isEmpty {
            let heir = workspace(target) == nil ? ungroupedID() : target
            for tab in fresh {
                let owner = arrivals.contains(tab) ? neighbourGroup(of: tab, in: current) : nil
                members[tab] = owner ?? (arrivals.contains(tab) ? ungroupedID() : heir)
            }
        }

        let known = current.filter { !fresh.contains($0) }
        if repairs, !isContiguous(known) {
            repair(known, previous: previous.filter(known.contains), selected: selected)
        }

        var reorders: [Reorder] = []
        var order = current
        for tab in fresh where !arrivals.contains(tab) {
            guard let index = order.firstIndex(of: tab), let owner = members[tab] else { continue }
            order.remove(at: index)
            let peers = order.indices.filter { members[order[$0]] == owner }
            let destination: Int
            if let first = peers.first, let last = peers.last {
                // Ghostty's own place stands when it touches the run of the group (G4).
                destination = !explicit && index >= first && index <= last + 1 ? index : last + 1
            } else {
                // The first tab of a new group goes before the first ungrouped tab (G8).
                destination = owner == id ? order.count : order.firstIndex { members[$0] == id } ?? order.count
            }
            order.insert(tab, at: destination)
            if destination != index { reorders.append(Reorder(tab: tab, delta: destination - index)) }
        }
        reorders += settleUngrouped(order: order)

        if members != before.members || workspaces != before.workspaces { revision = before.revision + 1 }
        return reorders
    }

    /// Workspaces are off: a tab with no workspace is ungrouped. Nothing else moves, whatever
    /// the order of the tabs.
    mutating func joinUngrouped(current: [TabKey]) {
        let fresh = current.filter { members[$0].flatMap { workspace($0) } == nil }
        guard !fresh.isEmpty else { return }
        let loose = ungroupedID()
        for tab in fresh { members[tab] = loose }
        revision += 1
    }

    /// Workspaces are on again: the native moves that make every group one run, in the order of
    /// first appearance, the ungrouped run last. Membership does not change.
    func regroup(order: [TabKey]) -> [Reorder] {
        let runs = runs(order: order)
        let target = (runs.filter { $0.workspace.id != id } + runs.filter { $0.workspace.id == id }).flatMap(\.tabs)
        return moves(from: order, to: target)
    }

    /// I2: the native moves that put the ungrouped run last, the groups and the order inside
    /// each run unchanged. Membership does not change.
    func settleUngrouped(order: [TabKey]) -> [Reorder] {
        moves(from: order, to: order.filter { members[$0] != id } + order.filter { members[$0] == id })
    }

    private func moves(from order: [TabKey], to target: [TabKey]) -> [Reorder] {
        var current = order
        var moves: [Reorder] = []
        for (place, tab) in target.enumerated() {
            guard let at = current.firstIndex(of: tab), at != place else { continue }
            current.remove(at: at)
            current.insert(tab, at: place)
            moves.append(Reorder(tab: tab, delta: place - at))
        }
        return moves
    }

    /// The group of the tab above `tab`, or below it when it is first.
    private func neighbourGroup(of tab: TabKey, in order: [TabKey]) -> Workspace.ID? {
        guard let index = order.firstIndex(of: tab) else { return nil }
        return [index - 1, index + 1].filter(order.indices.contains).lazy.compactMap { members[order[$0]] }.first
    }

    /// Makes the workspaces of `known` contiguous again. Ghostty moves one tab at a time, so
    /// first look for the tab whose removal leaves the others in their old order; it joins
    /// the workspace of its upper neighbour, or its lower one when it is first. When two
    /// neighbours swap both fit: the mover is the selected tab, else the tab of a group. If that
    /// does not heal the order, every tab outside the first run of its workspace joins the
    /// workspace above it, never into or out of the ungrouped group (`settleUngrouped` heals those).
    private mutating func repair(_ known: [TabKey], previous: [TabKey], selected: TabKey?) {
        if previous.count == known.count, previous != known {
            let fits = known.filter { tab in known.filter { $0 != tab } == previous.filter { $0 != tab } }
            let mover = fits.first { $0 == selected } ?? fits.first { members[$0] != id } ?? fits.first
            if let mover, let index = known.firstIndex(of: mover) {
                let neighbour = index > 0 ? known[index - 1] : known[safe: index + 1]
                if let owner = neighbour.flatMap({ members[$0] }) {
                    members[mover] = owner
                }
                if isContiguous(known) { return }
            }
        }

        var closed = Set<Workspace.ID>()
        var current: Workspace.ID?
        for (index, tab) in known.enumerated() {
            guard let owner = members[tab] else { continue }
            if owner == current { continue }
            if closed.contains(owner), index > 0, let above = members[known[index - 1]], owner != id, above != id {
                members[tab] = above
                continue
            }
            if let current { closed.insert(current) }
            current = owner
        }
    }

    private static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
