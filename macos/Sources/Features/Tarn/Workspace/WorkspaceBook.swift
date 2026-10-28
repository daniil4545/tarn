import Foundation

/// The registry's state and rules without AppKit: which set a tab is in, where a new tab
/// goes, what happens when sets meet or part. `WorkspaceRegistry` feeds it the tab groups
/// AppKit reports and acts on what it returns, so every rule is a unit test.
///
/// Rules: `docs/modules/workspaces.md`.
struct WorkspaceBook {
    /// The tabs of one native tab group in tab order.
    struct Group {
        let tabs: [TabKey]
        let selected: TabKey?
    }

    /// What a pass over the groups decided.
    struct Outcome: Equatable {
        /// Sets whose table changed, so their windows must save their state again.
        var changed: Set<UUID> = []
        /// One line per case no rule covered (section 8).
        var notes: [String] = []
    }

    /// A tab that is closing: enough to put it back.
    struct ClosedTab: Equatable {
        let tab: TabKey
        /// The set as it was just before the tab left.
        let set: WorkspaceSet
        let workspace: Workspace
    }

    private(set) var sets: [UUID: WorkspaceSet] = [:]
    /// Workspaces are off: new tabs join "~" and no tab or workspace moves (`docs/modules/workspaces.md`).
    var frozen = false
    private var setOf: [TabKey: UUID] = [:]
    /// Tabs seen in a group that held every live tab of their set. A settled tab that shows
    /// up in a group without its set has left it. Restored tabs start unsettled: AppKit
    /// may put their windows into one group only later.
    private var settled = Set<TabKey>()
    private var live = Set<TabKey>()
    private var lastSelectedTab: [UUID: TabKey] = [:]

    // MARK: Queries

    func set(of tab: TabKey) -> WorkspaceSet? {
        setOf[tab].flatMap { sets[$0] }
    }

    func workspace(of tab: TabKey) -> Workspace? {
        set(of: tab)?.workspace(of: tab)
    }

    /// The workspaces of a group top to bottom.
    func runs(for group: [TabKey]) -> [WorkspaceSet.Run] {
        guard let id = group.lazy.compactMap({ setOf[$0] }).first, let set = sets[id] else { return [] }
        return set.runs(order: group)
    }

    /// The snapshot a window saves: its set table and its own key.
    func snapshot(of tab: TabKey, order: [TabKey]) -> WorkspaceSnapshot? {
        set(of: tab).map { WorkspaceSnapshot(set: $0, tabKey: tab, order: order) }
    }

    // MARK: Following AppKit

    /// Looks at every tab group once. Idempotent: a second call with the same groups changes
    /// nothing.
    mutating func reconcile(_ groups: [Group]) -> Outcome {
        var outcome = Outcome()
        let now = Set(groups.flatMap(\.tabs))
        for tab in live.subtracting(now) {
            closeQuietly(tab, into: &outcome)
        }
        live = now

        // Which set each group follows is decided from the state before this pass, so the result
        // does not depend on the order of the groups (AppKit lists windows front to back).
        let groups = groups.filter { !$0.tabs.isEmpty }
        let winners = winningSets(for: groups)
        for (group, winner) in zip(groups, winners) {
            reconcile(group, winner: winner, into: &outcome)
        }
        return outcome
    }

    private mutating func reconcile(_ group: Group, winner: UUID, into outcome: inout Outcome) {
        let members = Set(group.tabs)
        var touched = Set<UUID>()

        // A tab whose set is unknown (a lost table) is new again.
        for tab in group.tabs where setOf[tab].map({ sets[$0] == nil }) == true {
            outcome.notes.append(note("tab without a set", tab: tab, set: setOf[tab]))
            setOf[tab] = nil
        }

        for tab in group.tabs {
            guard let old = setOf[tab], old != winner else { continue }
            let oldTabs = live.filter { setOf[$0] == old }
            if oldTabs.isSubset(of: members), let loser = sets[old], var won = sets[winner], !isPlain(loser) {
                // Merge All Windows: the loser's workspaces come whole, with their names. A window
                // that holds only its stock "No project" has nothing to keep: it is the same as a tab
                // dragged in and joins "~".
                won.absorb(loser)
                sets[winner] = won
                sets[old] = nil
                lastSelectedTab[old] = nil
                for moved in oldTabs { setOf[moved] = winner }
                touched.insert(old)
            } else {
                // One tab dragged in, or out: it joins "~" of the new group.
                remove(tab, from: old)
                touched.insert(old)
            }
        }

        let before = sets[winner]?.revision
        var set = sets[winner] ?? WorkspaceSet(id: winner)
        let fresh = group.tabs.filter { setOf[$0] == nil }
        for tab in fresh { setOf[tab] = winner }

        set.reconcile(current: group.tabs)
        if !fresh.isEmpty, let id = set.workspace(of: fresh[0])?.id { set.setCollapsed(id, false) }
        sets[winner] = set

        if live.filter({ setOf[$0] == winner }).isSubset(of: members) { settled.formUnion(members) }

        if set.revision != before { touched.insert(winner) }
        outcome.changed.formUnion(touched.filter { sets[$0] != nil })
    }

    /// A set that is one unrenamed start workspace with no folder: "~", or the older "No project"
    /// or "Default". A window nobody has set up.
    func isPlain(_ set: WorkspaceSet) -> Bool {
        guard set.workspaces.count == 1 else { return false }
        let only = set.workspaces[0]
        return only.folder == nil
            && [WorkspaceSet.homeName, WorkspaceSet.defaultName, WorkspaceSet.legacyDefaultName].contains(only.name)
    }

    /// The set each group follows. A set belongs to the group that holds most of its live tabs; a
    /// tie goes to the group with more settled tabs (a restore still joining its windows), then to the group with the smallest tab key, so no group order matters. A group takes
    /// the set it owns with most tabs in it (the earliest tab wins a tie, so with Merge All Windows
    /// the first window's set wins). With none, tabs that were never settled (a restore in
    /// progress) keep their first set; otherwise the group starts a new set.
    private func winningSets(for groups: [Group]) -> [UUID] {
        func count(_ set: UUID, in group: Group) -> Int { group.tabs.filter { setOf[$0] == set }.count }
        func settledCount(_ set: UUID, in group: Group) -> Int {
            group.tabs.filter { setOf[$0] == set && settled.contains($0) }.count
        }
        func rank(_ group: Group) -> String { group.tabs.map(\.uuidString).min() ?? "" }
        var owner: [UUID: Int] = [:]
        for set in Set(groups.flatMap(\.tabs).compactMap { setOf[$0] }) {
            owner[set] = groups.indices.max { lhs, rhs in
                let (a, b) = (count(set, in: groups[lhs]), count(set, in: groups[rhs]))
                if a != b { return a < b }
                let (x, y) = (settledCount(set, in: groups[lhs]), settledCount(set, in: groups[rhs]))
                return x != y ? x < y : rank(groups[lhs]) > rank(groups[rhs])
            }
        }
        return groups.enumerated().map { index, group in
            let owned = group.tabs.compactMap { setOf[$0] }.filter { owner[$0] == index }
            var best: UUID?
            for id in owned where best == nil || count(id, in: group) > count(best!, in: group) { best = id }
            if let best { return best }
            if let loose = group.tabs.first(where: { setOf[$0] != nil && !settled.contains($0) }), let id = setOf[loose] {
                return id
            }
            return UUID()
        }
    }

    // MARK: Closing and coming back

    /// Notes a tab that is about to close. Returns what is needed to put it back.
    mutating func closing(_ tab: TabKey) -> ClosedTab? {
        guard let id = setOf[tab], let set = sets[id], let workspace = set.workspace(of: tab) else { return nil }
        let closed = ClosedTab(tab: tab, set: set, workspace: workspace)
        var outcome = Outcome()
        closeQuietly(tab, into: &outcome)
        live.remove(tab)
        return closed
    }

    /// Puts a reopened tab back where `closed` says: its set (recreated when gone, with the
    /// names and fold kept but no empty "No project") and its workspace (recreated when deleted).
    mutating func reinsert(_ tab: TabKey, from closed: ClosedTab) {
        let id = closed.set.id
        var set = sets[id] ?? WorkspaceSet(id: id, revision: closed.set.revision)
        if set.workspace(closed.workspace.id) == nil {
            set.add(closed.workspace)
        }
        set.join(tab, to: closed.workspace.id)
        sets[id] = set
        setOf[tab] = id
        settled.insert(tab)
    }

    private mutating func closeQuietly(_ tab: TabKey, into outcome: inout Outcome) {
        guard let id = setOf[tab] else { return }
        remove(tab, from: id)
        outcome.changed.insert(id)
        outcome.changed = outcome.changed.filter { sets[$0] != nil }
    }

    private mutating func remove(_ tab: TabKey, from id: UUID) {
        setOf[tab] = nil
        settled.remove(tab)
        guard var set = sets[id] else { return }
        set.remove(tab)
        if set.workspaces.isEmpty {
            sets[id] = nil
            lastSelectedTab[id] = nil
        } else {
            sets[id] = set
        }
    }

    // MARK: Sidebar commands

    /// M1: `tab`, which Ghostty just opened from `source`, takes the workspace of `source`
    /// and unfolds it. Returns the sets that changed.
    mutating func opened(_ tab: TabKey, from source: TabKey) -> Set<UUID> {
        guard let id = setOf[source], var set = sets[id], let workspace = set.workspace(of: source) else { return [] }
        var changed: Set<UUID> = [id]
        if let old = setOf[tab], old != id {
            remove(tab, from: old)
            changed.insert(old)
        }
        setOf[tab] = id
        set.join(tab, to: workspace.id)
        set.setCollapsed(workspace.id, false)
        sets[id] = set
        return changed.filter { sets[$0] != nil }
    }

    /// The selection moved to `tab`. A collapsed workspace opens when the selection enters
    /// it. Returns the set when its table changed.
    mutating func selected(_ tab: TabKey) -> UUID? {
        guard let id = setOf[tab], var set = sets[id], let workspace = set.workspace(of: tab) else { return nil }
        let entered = lastSelectedTab[id] != tab
        lastSelectedTab[id] = tab
        guard entered, workspace.collapsed else { return nil }
        set.setCollapsed(workspace.id, false)
        sets[id] = set
        return id
    }

    /// Runs `edit` on the set of `tab`. Returns the set id when the table changed.
    mutating func edit(_ tab: TabKey, _ edit: (inout WorkspaceSet) -> Void) -> UUID? {
        guard let id = setOf[tab], var set = sets[id] else { return nil }
        let before = set
        edit(&set)
        guard set != before else { return nil }
        sets[id] = set
        return id
    }

    // MARK: Restore

    /// Takes the table a restored window carries. The higher revision wins (section 6).
    mutating func adopt(_ snapshot: WorkspaceSnapshot) {
        if let current = sets[snapshot.setID], current.revision >= snapshot.revision {
            setOf[snapshot.tabKey] = snapshot.setID
            return
        }
        sets[snapshot.setID] = snapshot.makeSet()
        setOf[snapshot.tabKey] = snapshot.setID
    }

    private func note(_ reason: String, tab: TabKey, set: UUID?) -> String {
        "workspace: \(reason) window=\(tab) set=\(set.map(\.uuidString) ?? "none")"
    }
}
