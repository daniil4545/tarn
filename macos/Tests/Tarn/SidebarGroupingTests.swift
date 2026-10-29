import Foundation
import Testing
@testable import Ghostty

/// The sidebar's workspace groups: the state a header shows, and where a drop lands
/// (scenarios S7 to S9 and S23 of `docs/specs/windows-workspaces.md`).
@Suite
struct SidebarGroupingTests {
    private func tab(_ index: Int, agent: AgentSession? = nil) -> SidebarModel.Tab {
        SidebarModel.Tab(
            id: ObjectIdentifier(NSObject()),
            key: TabKey(),
            index: index,
            title: "\(index)",
            agentProcess: nil,
            keyEquivalent: nil,
            color: .none,
            isSelected: false,
            agent: agent,
            workspace: "",
            folder: nil
        )
    }

    private func session(_ state: AgentState, seen: Bool = true) -> AgentSession {
        var session = AgentSession(surfaceID: UUID())
        session.state = state
        session.seen = seen
        return session
    }

    private func group(_ name: String, _ tabs: [SidebarModel.Tab]) -> SidebarModel.Group {
        .init(workspace: Workspace(name: name), tabs: tabs)
    }

    // MARK: Header state

    @Test func headerShowsTheMostUrgentState() {
        let tabs = [
            tab(1, agent: session(.working)),
            tab(2, agent: session(.permission)),
            tab(3, agent: session(.waiting, seen: false)),
        ]
        #expect(group("A", tabs).worstAgent?.state == .permission)
    }

    @Test func anUnseenDoneBeatsASeenDone() {
        let seen = session(.waiting)
        let unseen = session(.waiting, seen: false)
        let worst = group("A", [tab(1, agent: seen), tab(2, agent: unseen)]).worstAgent
        #expect(worst == unseen)
    }

    @Test func headerShowsNoStateWithoutAgents() {
        #expect(group("A", [tab(1), tab(2, agent: session(.idle))]).worstAgent == nil)
    }

    // MARK: Drop slots

    /// A: two tabs, B: three tabs, C: one tab.
    private func layout() -> (groups: [SidebarModel.Group], tabs: [SidebarModel.Tab]) {
        let tabs = (1...6).map { tab($0) }
        return (
            [group("A", Array(tabs[0...1])), group("B", Array(tabs[2...4])), group("C", [tabs[5]])],
            tabs
        )
    }

    @Test func aTabOnTheUpperHalfOfARowLandsBeforeIt() {
        let (groups, tabs) = layout()
        let slot = SidebarModel.dropSlot(dragging: .tab, over: .tab(tabs[3].key), lowerHalf: false, in: groups)
        #expect(slot == .beforeTab(tabs[3].key))
    }

    @Test func aTabOnTheLowerHalfLandsBeforeTheNextRowOrAtTheEnd() {
        let (groups, tabs) = layout()
        let middle = SidebarModel.dropSlot(dragging: .tab, over: .tab(tabs[2].key), lowerHalf: true, in: groups)
        #expect(middle == .beforeTab(tabs[3].key))
        let last = SidebarModel.dropSlot(dragging: .tab, over: .tab(tabs[4].key), lowerHalf: true, in: groups)
        #expect(last == .endOfWorkspace(groups[1].id))
    }

    @Test func aTabOnAHeaderGoesToTheEndOfItsWorkspace() {
        let (groups, _) = layout()
        let slot = SidebarModel.dropSlot(dragging: .tab, over: .header(groups[0].id), lowerHalf: false, in: groups)
        #expect(slot == .endOfWorkspace(groups[0].id))
    }

    @Test func aWorkspaceOnAHeaderLandsBeforeItOrBeforeTheNext() {
        let (groups, _) = layout()
        let upper = SidebarModel.dropSlot(dragging: .workspace, over: .header(groups[1].id), lowerHalf: false, in: groups)
        #expect(upper == .beforeWorkspace(groups[1].id))
        let lower = SidebarModel.dropSlot(dragging: .workspace, over: .header(groups[1].id), lowerHalf: true, in: groups)
        #expect(lower == .beforeWorkspace(groups[2].id))
    }

    @Test func aWorkspaceBelowTheLastHeaderGoesToTheEnd() {
        let (groups, _) = layout()
        let slot = SidebarModel.dropSlot(dragging: .workspace, over: .header(groups[2].id), lowerHalf: true, in: groups)
        #expect(slot == .end)
    }

    @Test(arguments: [
        // row index in B (3 rows), lower half, expected: before B (true) or after B (false)
        (0, false, true), (0, true, true), (1, false, true), (1, true, false), (2, false, false), (2, true, false),
    ] as [(Int, Bool, Bool)])
    func aWorkspaceOnARowLandsByTheHalfOfItsWorkspace(row: Int, lowerHalf: Bool, beforeB: Bool) {
        let (groups, _) = layout()
        let key = groups[1].tabs[row].key
        let slot = SidebarModel.dropSlot(dragging: .workspace, over: .tab(key), lowerHalf: lowerHalf, in: groups)
        #expect(slot == (beforeB ? .beforeWorkspace(groups[1].id) : .beforeWorkspace(groups[2].id)))
    }

    // spec: docs/specs/windows-workspaces.md S9. The empty sidebar below the last row takes drops after everything.
    @Test func belowTheLastRowAWorkspaceGoesToTheEndAndATabToTheLastWorkspace() {
        let (groups, _) = layout()
        #expect(SidebarModel.dropSlot(dragging: .workspace, over: .tail, lowerHalf: true, in: groups) == .end)
        #expect(SidebarModel.dropSlot(dragging: .tab, over: .tail, lowerHalf: true, in: groups) == .endOfWorkspace(groups[2].id))
        #expect(SidebarModel.dropSlot(dragging: .workspace, over: .tail, lowerHalf: true, in: []) == nil)
    }

    // The slot before the lifted row and the slot after it are one slot: the row's own.
    @Test func theSlotBeforeTheLiftedRowIsTheSlotAfterIt() {
        let (groups, tabs) = layout()
        #expect(SidebarModel.gapSlot(.beforeTab(tabs[2].key), lifted: tabs[2].key, in: groups) == .beforeTab(tabs[3].key))
        #expect(SidebarModel.gapSlot(.beforeTab(tabs[4].key), lifted: tabs[4].key, in: groups) == .endOfWorkspace(groups[1].id))
        #expect(SidebarModel.gapSlot(.beforeTab(tabs[0].key), lifted: tabs[2].key, in: groups) == .beforeTab(tabs[0].key))
        #expect(SidebarModel.gapSlot(nil, lifted: tabs[2].key, in: groups) == nil)
    }

    // A gap above a header with rows below it stays put: moved to the end of that workspace it
    // would pull the header up and put a row under the pointer.
    @Test func aHeaderBelowTheGapKeepsTheGapOnlyWhileRowsStandUnderIt() {
        let (groups, tabs) = layout()
        let a = groups[0].id, b = groups[1].id
        #expect(SidebarModel.gapPullsUp(b, gap: .beforeTab(tabs[1].key), in: groups))
        #expect(SidebarModel.gapPullsUp(b, gap: .endOfWorkspace(a), in: groups))
        // From below, or with no gap open, the header stays under the pointer.
        #expect(!SidebarModel.gapPullsUp(b, gap: .beforeTab(tabs[3].key), in: groups))
        #expect(!SidebarModel.gapPullsUp(b, gap: nil, in: groups))
        // A folded or empty workspace shows nothing below its header: the new gap comes under the pointer.
        var workspace = groups[1].workspace!
        workspace.collapsed = true
        var folded = groups
        folded[1] = SidebarModel.Group(workspace: workspace, tabs: groups[1].tabs)
        #expect(!SidebarModel.gapPullsUp(b, gap: .endOfWorkspace(a), in: folded))
        let empty = group("D", [])
        #expect(!SidebarModel.gapPullsUp(empty.id, gap: .endOfWorkspace(a), in: groups + [empty]))
    }

    /// A: two tabs, ungrouped: one tab, B: two tabs.
    private func withUngrouped() -> (groups: [SidebarModel.Group], tabs: [SidebarModel.Tab]) {
        let tabs = (1...5).map { tab($0) }
        return (
            [group("A", Array(tabs[0...1])), .init(workspace: nil, tabs: [tabs[2]]), group("B", Array(tabs[3...4]))],
            tabs
        )
    }

    /// spec: docs/specs/workspace-folder.md S51
    /// A row without a group takes a tab drag like any row (native order only), also in the flat list
    /// of Workspaces off.
    @Test func aTabDraggedOverAnUngroupedRowLandsByTheHalfOfThatRow() {
        let (groups, tabs) = withUngrouped()
        let key = tabs[2].key
        #expect(SidebarModel.dropSlot(dragging: .tab, over: .tab(key), lowerHalf: false, in: groups) == .beforeTab(key))
        // The lone row of its block: the lower half is the end of the block.
        #expect(SidebarModel.dropSlot(dragging: .tab, over: .tab(key), lowerHalf: true, in: groups) == .endOfWorkspace(groups[1].id))

        let flat = [SidebarModel.Group(workspace: nil, tabs: Array(tabs[0...2]))]
        #expect(SidebarModel.dropSlot(dragging: .tab, over: .tab(tabs[0].key), lowerHalf: true, in: flat) == .beforeTab(tabs[1].key))
        #expect(SidebarModel.dropSlot(dragging: .tab, over: .tab(tabs[2].key), lowerHalf: true, in: flat) == .endOfWorkspace(flat[0].id))
        #expect(SidebarModel.dropSlot(dragging: .tab, over: .tail, lowerHalf: true, in: flat) == .endOfWorkspace(flat[0].id))
    }

    @Test func anUngroupedBlockTakesNoWorkspaceDragAndHasNoHeader() {
        let (groups, tabs) = withUngrouped()
        let key = tabs[2].key
        for lowerHalf in [false, true] {
            #expect(SidebarModel.dropSlot(dragging: .workspace, over: .tab(key), lowerHalf: lowerHalf, in: groups) == nil)
        }
        // The ungrouped block has no header; its id is its first tab, no workspace's.
        #expect(groups[1].id == key)
        #expect(!groups.contains { $0.workspace?.id == key })
        #expect(SidebarModel.dropSlot(dragging: .tab, over: .header(key), lowerHalf: false, in: groups) == nil)
    }

    @Test func aWorkspaceDroppedBelowAnotherLandsBeforeTheNextWorkspaceNotTheUngroupedBlock() {
        let (groups, _) = withUngrouped()
        let a = groups[0].id, b = groups[2].id
        let lower = SidebarModel.dropSlot(dragging: .workspace, over: .header(a), lowerHalf: true, in: groups)
        #expect(lower == .beforeWorkspace(b))
        let end = SidebarModel.dropSlot(dragging: .workspace, over: .header(b), lowerHalf: true, in: groups)
        #expect(end == .end)
    }

    @Test func belowAnUngroupedLastBlockATabGoesToTheEndOfThatBlock() {
        let (groups, tabs) = withUngrouped()
        let ungroupedLast = Array(groups[0...1])
        #expect(SidebarModel.dropSlot(dragging: .tab, over: .tail, lowerHalf: true, in: ungroupedLast) == .endOfWorkspace(groups[1].id))
        #expect(SidebarModel.dropSlot(dragging: .tab, over: .tail, lowerHalf: true, in: groups) == .endOfWorkspace(groups[2].id))
        // A gap in the ungrouped block pulls no header up: it belongs to no workspace.
        #expect(!SidebarModel.gapPullsUp(groups[2].id, gap: .beforeTab(tabs[2].key), in: groups))
        #expect(SidebarModel.gapPullsUp(groups[2].id, gap: .endOfWorkspace(groups[0].id), in: groups))
    }

    @Test func unknownTargetsGiveNoSlot() {
        let (groups, _) = layout()
        #expect(SidebarModel.dropSlot(dragging: .tab, over: .tab(TabKey()), lowerHalf: false, in: groups) == nil)
        #expect(SidebarModel.dropSlot(dragging: .workspace, over: .header(UUID()), lowerHalf: false, in: groups) == nil)
    }

    // A tab split into several agents names the pane whose state its dot shows.
    @Test func rowTextFollowsTheMostUrgentPane() {
        let working = session(.working), asking = session(.permission)
        let panes = [UUID(), working.surfaceID, asking.surfaceID]
        let sessions = [working.surfaceID: working, asking.surfaceID: asking]
        #expect(SidebarModel.textPane(panes, agents: [nil, "claude", "claude"], sessions: sessions) == 2)
        // With no agent state the first pane running an agent names the row.
        #expect(SidebarModel.textPane(panes, agents: [nil, "claude", "claude"], sessions: [:]) == 1)
        #expect(SidebarModel.textPane(panes, agents: [nil, nil, nil], sessions: [:]) == nil)
    }
}
