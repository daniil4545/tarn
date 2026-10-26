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

    // The lifted row takes no space: the slot before it is the slot after it, so the gap opens
    // where the row was and nothing moves.
    @Test func theGapBeforeTheLiftedRowIsTheGapAfterIt() {
        let (groups, tabs) = layout()
        #expect(SidebarModel.gapSlot(.beforeTab(tabs[2].key), lifted: tabs[2].key, in: groups) == .beforeTab(tabs[3].key))
        #expect(SidebarModel.gapSlot(.beforeTab(tabs[4].key), lifted: tabs[4].key, in: groups) == .endOfWorkspace(groups[1].id))
        #expect(SidebarModel.gapSlot(.beforeTab(tabs[0].key), lifted: tabs[2].key, in: groups) == .beforeTab(tabs[0].key))
        #expect(SidebarModel.gapSlot(nil, lifted: tabs[2].key, in: groups) == nil)
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
