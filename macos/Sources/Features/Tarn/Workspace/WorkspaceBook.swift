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
        /// Native moves for the registry to make: new tabs go to the end of their run.
        var reorders: [WorkspaceSet.Reorder] = []
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
    /// Workspaces are off: new tabs are ungrouped and no tab or workspace moves (`docs/modules/workspaces.md`).
    var frozen = false
    /// Workspaces came back on: the next pass regroups the tabs instead of repairing membership.
    var regroupPending = false
    private var setOf: [TabKey: UUID] = [:]
    /// Tabs seen in a group that held every live tab of their set. A settled tab that shows
    /// up in a group without its set has left it. Restored tabs start unsettled: AppKit
    /// may put their windows into one group only later.
    private var settled = Set<TabKey>()
    private var live = Set<TabKey>()
    private var seenOrder: [UUID: [TabKey]] = [:]
    private var pendingTarget: [UUID: Workspace.ID] = [:]
    private var lastSelected: [UUID: Workspace.ID] = [:]
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
        let regroup = regroupPending && !frozen
        regroupPending = false
        for (group, winner) in zip(groups, winners) {
            reconcile(group, winner: winner, regroup: regroup, into: &outcome)
        }
        return outcome
    }

    private mutating func reconcile(_ group: Group, winner: UUID, regroup: Bool, into outcome: inout Outcome) {
        let members = Set(group.tabs)
        var touched = Set<UUID>()
        var merged = false
        var arrivals = Set<TabKey>()

        // A tab whose set is unknown (a lost table) is new again.
        for tab in group.tabs where setOf[tab].map({ sets[$0] == nil }) == true {
            outcome.notes.append(note("tab without a set", tab: tab, set: setOf[tab]))
            setOf[tab] = nil
        }

        for tab in group.tabs {
            guard let old = setOf[tab], old != winner else { continue }
            let oldTabs = live.filter { setOf[$0] == old }
            if oldTabs.isSubset(of: members), let loser = sets[old], var won = sets[winner],
               !(isNewTab(loser, old: old, tab: tab, group: group) || (isLoneTab(loser) && pendingTarget[winner] != nil)) {
                // Merge All Windows: the loser's groups come whole, its ungrouped tabs join ours (I1).
                won.absorb(loser)
                merged = true
                sets[winner] = won
                sets[old] = nil
                seenOrder[old] = nil
                pendingTarget[old] = nil
                lastSelected[old] = nil
                lastSelectedTab[old] = nil
                for moved in oldTabs { setOf[moved] = winner }
                touched.insert(old)
            } else {
                // One tab dragged in, or out: it joins the group of its neighbour (G5a), or the
                // group a sidebar command named.
                let lone = sets[old].map { isNewTab($0, old: old, tab: tab, group: group) } == true
                if pendingTarget[winner] == nil, !lone { arrivals.insert(tab) }
                remove(tab, from: old)
                touched.insert(old)
            }
        }

        let before = sets[winner]?.revision
        var set = sets[winner] ?? WorkspaceSet(id: winner)
        let fresh = group.tabs.filter { setOf[$0] == nil }
        let target = targetWorkspace(in: set, group: group, winner: winner)
        for tab in fresh { setOf[tab] = winner }

        let previous = (seenOrder[winner] ?? []).filter(members.contains)
        if frozen {
            set.joinUngrouped(current: group.tabs)
        } else if regroup {
            set.joinUngrouped(current: group.tabs)
            outcome.reorders += set.regroup(order: group.tabs)
        } else {
            outcome.reorders += set.reconcile(
                previous: previous, current: group.tabs, target: target, selected: group.selected,
                explicit: pendingTarget[winner] != nil, arrivals: arrivals, repairs: !merged
            )
        }
        if !fresh.isEmpty {
            if let id = set.workspace(of: fresh[0])?.id { set.setCollapsed(id, false) }
            pendingTarget[winner] = nil
        }
        set.removeEmpty(keeping: pendingTarget[winner])
        sets[winner] = set

        seenOrder[winner] = (seenOrder[winner] ?? []).filter { !members.contains($0) } + group.tabs
        if live.filter({ setOf[$0] == winner }).isSubset(of: members) { settled.formUnion(members) }
        if lastSelected[winner] == nil, let selected = group.selected, let id = set.workspace(of: selected)?.id {
            lastSelected[winner] = id
        }

        if set.revision != before { touched.insert(winner) }
        outcome.changed.formUnion(touched.filter { sets[$0] != nil })
    }

    /// A window of one ungrouped tab. A new tab is seen alone in its own window before AppKit tabs
    /// it (a title change posts in between), and on the stand the pass runs before Ghostty selects
    /// it (`TerminalController.swift:493`) except for the first Cmd+T. So a one-tab window is a new
    /// tab (Cmd+T, takes the target) when it is selected in the group, or when it was never selected
    /// before: `lastSelectedTab` is written when a window becomes key (`WorkspaceRegistry.windowDidBecomeKey`
    /// calls `selected(_:)`), and a Cmd+N window is key when shown. A one-tab window that was key
    /// is a window merged in (`absorb`).
    private func isNewTab(_ set: WorkspaceSet, old: UUID, tab: TabKey, group: Group) -> Bool {
        isLoneTab(set) && (group.selected == tab || lastSelectedTab[old] == nil)
    }

    private func isLoneTab(_ set: WorkspaceSet) -> Bool {
        set.members.count == 1 && set.workspaces.count == 1 && set.isUngrouped(set.workspaces[0])
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

    /// Where a new tab goes: the workspace the sidebar named, else the one of the selected
    /// tab, else the ungrouped group (section 4).
    private func targetWorkspace(in set: WorkspaceSet, group: Group, winner: UUID) -> Workspace.ID {
        if let id = pendingTarget[winner], set.workspace(id) != nil { return id }
        if let id = lastSelected[winner], set.workspace(id) != nil { return id }
        if let selected = group.selected, let id = set.workspace(of: selected)?.id { return id }
        return winner
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

    /// Puts a reopened tab back where `closed` says: its set (recreated when gone) and its group
    /// (recreated when deleted); a closed ungrouped group maps to the set's ungrouped group (I1).
    mutating func reinsert(_ tab: TabKey, from closed: ClosedTab) {
        let id = closed.set.id
        var set = sets[id] ?? WorkspaceSet(id: id, revision: closed.set.revision)
        let owner = closed.set.isUngrouped(closed.workspace) ? set.ungroupedID() : closed.workspace.id
        if set.workspace(owner) == nil {
            set.add(closed.workspace)
        }
        set.join(tab, to: owner)
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
        seenOrder[id] = seenOrder[id]?.filter { $0 != tab }
        guard var set = sets[id] else { return }
        set.remove(tab)
        if set.workspaces.isEmpty {
            sets[id] = nil
            seenOrder[id] = nil
            pendingTarget[id] = nil
            lastSelected[id] = nil
            lastSelectedTab[id] = nil
        } else {
            sets[id] = set
        }
    }

    // MARK: Sidebar commands

    /// The next new tab of the window's set goes to `workspace`.
    mutating func setPendingTarget(_ workspace: Workspace.ID, for tab: TabKey) {
        guard let id = setOf[tab] else { return }
        pendingTarget[id] = workspace
    }

    /// Forgets a target that nobody used. True when there was one.
    mutating func clearPendingTarget(for tab: TabKey) -> Bool {
        guard let id = setOf[tab] else { return false }
        return pendingTarget.removeValue(forKey: id) != nil
    }

    /// The selection moved to `tab`. A collapsed workspace opens when the selection enters
    /// it. Returns the set when its table changed.
    mutating func selected(_ tab: TabKey) -> UUID? {
        guard let id = setOf[tab], var set = sets[id], let workspace = set.workspace(of: tab) else { return nil }
        lastSelected[id] = workspace.id
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
