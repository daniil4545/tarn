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
        /// Nil when the tab was ungrouped.
        let workspace: Workspace?
    }

    private(set) var sets: [UUID: WorkspaceSet] = [:]
    /// Workspaces are off: a new tab stays ungrouped and no tab or workspace moves (`docs/modules/workspaces.md`).
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
            if oldTabs.isSubset(of: members), let loser = sets[old], var won = sets[winner] {
                // Merge All Windows, or the last tab of a window dropped in: the loser's workspaces
                // come whole, with their names, and its ungrouped tabs stay ungrouped (M4).
                won.absorb(loser)
                sets[winner] = won
                sets[old] = nil
                lastSelectedTab[old] = nil
                for moved in oldTabs { setOf[moved] = winner }
                touched.insert(old)
            } else {
                // One tab dragged in, or out: it is ungrouped in the new group (M1).
                remove(tab, from: old)
                touched.insert(old)
            }
        }

        // A tab no rule has placed is ungrouped (M1).
        let fresh = group.tabs.filter { setOf[$0] == nil }
        for tab in fresh { setOf[tab] = winner }
        if sets[winner] == nil { sets[winner] = WorkspaceSet(id: winner) }

        if live.filter({ setOf[$0] == winner }).isSubset(of: members) { settled.formUnion(members) }

        if !fresh.isEmpty { touched.insert(winner) }
        outcome.changed.formUnion(touched.filter { sets[$0] != nil })
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
        guard let id = setOf[tab], let set = sets[id] else { return nil }
        let closed = ClosedTab(tab: tab, set: set, workspace: set.workspace(of: tab))
        var outcome = Outcome()
        closeQuietly(tab, into: &outcome)
        live.remove(tab)
        return closed
    }

    /// Puts a reopened tab back where `closed` says: its set (recreated when gone) and its
    /// workspace (recreated when deleted), or ungrouped (M2). Like a restored tab, it stays
    /// unsettled until AppKit joins it to its native tab group.
    mutating func reinsert(_ tab: TabKey, from closed: ClosedTab) {
        let id = closed.set.id
        var set = sets[id] ?? WorkspaceSet(id: id, revision: closed.set.revision)
        if let workspace = closed.workspace {
            if set.workspace(workspace.id) == nil { set.add(workspace) }
            set.join(tab, to: workspace.id)
        }
        sets[id] = set
        setOf[tab] = id
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
        // A set lives while it has a tab, grouped or not.
        if setOf.values.contains(id) {
            sets[id] = set
        } else {
            sets[id] = nil
            lastSelectedTab[id] = nil
        }
    }

    // MARK: Sidebar commands

    /// M1: `tab`, which Ghostty just opened from `source`, takes the workspace of `source`
    /// and unfolds it; a source with no workspace gives none. Returns the sets that changed.
    mutating func opened(_ tab: TabKey, from source: TabKey) -> Set<UUID> {
        guard let id = setOf[source], var set = sets[id] else { return [] }
        var changed: Set<UUID> = [id]
        if let old = setOf[tab], old != id {
            remove(tab, from: old)
            changed.insert(old)
        }
        setOf[tab] = id
        if let workspace = set.workspace(of: source) {
            set.join(tab, to: workspace.id)
            set.setCollapsed(workspace.id, false)
        }
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
