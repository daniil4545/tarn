import AppKit
import Testing
@testable import Ghostty

/// The lift and gap of a sidebar tab drag (T-236).
@MainActor
@Suite
struct SidebarDragTests {
    @Test(arguments: [false, true])
    func aGroupLiftsOpensOnlyBlockGapsAndCancels(collapsed: Bool) {
        let (_, tab, _) = lifted()
        let (_, loose, _) = lifted()
        var source = Workspace(name: "Source")
        source.collapsed = collapsed
        let target = Workspace(name: "Target")
        let groups: [SidebarModel.Group] = [
            .init(workspace: source, tabs: []), .init(workspace: target, tabs: [tab]),
            .init(workspace: nil, tabs: [loose]),
        ]
        let model = SidebarModel(groups: groups)
        let height: CGFloat = collapsed ? 28 : 80
        model.dragBegan(source, height: height)
        #expect(model.liftedWorkspace == source.id && model.liftedHeight == height + 8 && model.gapSlot == nil)
        // Before Target is the source's own slot, so no gap opens there.
        for (half, expected) in [(false, SidebarDropSlot?.none), (true, .beforeWorkspace(loose.key))] {
            #expect(model.dragOver(.workspace, value: source.id.uuidString, over: .tab(tab.key), lowerHalf: half))
            #expect(model.gapSlot == expected)
        }
        #expect(model.dragOver(.workspace, value: source.id.uuidString, over: .tab(loose.key), lowerHalf: true))
        #expect(model.gapSlot == .end)
        model.dragExit(at: .zero)
        #expect(model.gapSlot == nil && model.liftedWorkspace == source.id)
        model.groupDragEnded()
        #expect(model.liftedWorkspace == nil && model.dropSlot == nil && model.groups == groups)
    }

    @Test func aGroupStandsBetweenTwoUngroupedTabsByTheirHalves() {
        let (_, first, _) = lifted()
        let (_, second, _) = lifted()
        let (_, inGroup, _) = lifted()
        let loose = SidebarModel.Group(workspace: nil, tabs: [first, second])
        let groups = [loose, .init(workspace: Workspace(name: "G"), tabs: [inGroup])]
        let slot = { (key: TabKey, lower: Bool) in
            SidebarModel.dropSlot(dragging: .workspace, over: .tab(key), lowerHalf: lower, in: groups)
        }
        #expect(slot(first.key, false) == .beforeWorkspace(loose.id))
        #expect(slot(first.key, true) == .beforeTab(second.key))
        #expect(slot(second.key, false) == .beforeTab(second.key))
        #expect(slot(second.key, true) == .beforeWorkspace(groups[1].id))
        #expect(slot(inGroup.key, false) == .beforeWorkspace(groups[1].id))
    }

    private func lifted() -> (SidebarModel, SidebarModel.Tab, NSWindow) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.orderFront(nil)
        let model = SidebarModel()
        model.window = window
        let tab = SidebarModel.Tab(
            id: ObjectIdentifier(NSObject()), key: TabKey(), index: 1, title: "one", agentProcess: nil,
            keyEquivalent: nil, color: .none, isSelected: false, agent: nil, workspace: "", folder: nil
        )
        model.dragBegan(tab, height: 24)
        model.dropSlot = .tail
        return (model, tab, window)
    }

    // spec: docs/specs/workspace-folder.md S58
    @Test func aReleaseOverTheTerminalClosesTheGapAndMovesNothing() {
        let (model, tab, window) = lifted()
        #expect(model.gapSlot == .tail)
        model.dragEnded(tab, at: NSPoint(x: window.frame.midX, y: window.frame.midY), accepted: false)
        #expect(model.liftedTab == nil)
        #expect(model.dropSlot == nil)
        #expect(model.gapSlot == nil)
    }

    @Test func aDropLeavesNoGapBehindEvenWhenItIsRefused() {
        let (model, tab, _) = lifted()
        #expect(!model.drop(.tab, value: tab.key.uuidString, at: nil))
        #expect(model.liftedTab == nil)
        #expect(model.dropSlot == nil)
    }

    @Test(arguments: [false, true])
    func aHeaderKeepsTheGapWhereItIs(collapsed: Bool) {
        let (_, tab, _) = lifted()
        var workspace = Workspace(name: "Target")
        workspace.collapsed = collapsed
        let model = SidebarModel(groups: [.init(workspace: workspace, tabs: [tab])])
        model.dragBegan(tab, height: 24)
        #expect(model.dragOver(.tab, value: tab.key.uuidString, over: .margin(workspace.id), lowerHalf: false))
        #expect(model.dropSlot == .beforeWorkspace(workspace.id))
        for half in [false, true] {
            #expect(model.dragOver(.tab, value: tab.key.uuidString, over: .header(workspace.id), lowerHalf: half))
            #expect(model.dropSlot == .beforeWorkspace(workspace.id))
            #expect(model.gapSlot == model.dropSlot)
        }
        model.dragExit(at: .zero)
        #expect(model.dropSlot == nil && model.gapSlot == nil && model.liftedTab == tab.key)
        #expect(!model.dragOver(.tab, value: tab.key.uuidString, over: .header(workspace.id), lowerHalf: false))
        #expect(model.dropSlot == nil)
        model.dragEnded(tab, at: .zero, accepted: true)
        #expect(model.liftedTab == nil && model.dropSlot == nil)
    }

    @Test func onlyLeavingTheWholeSidebarClosesTheGap() {
        let (model, tab, window) = lifted()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 200))
        window.contentView?.addSubview(anchor)
        model.sidebarAnchor = WeakView(view: anchor)
        model.dragExit(at: window.convertPoint(toScreen: NSPoint(x: 50, y: 50)))
        #expect(model.gapSlot == .tail)
        model.dragExit(at: window.convertPoint(toScreen: NSPoint(x: 150, y: 50)))
        #expect(model.dropSlot == nil && model.gapSlot == nil)
        #expect(model.liftedTab == tab.key)
    }

    @Test func refreshClearsAStaleLiftAndDropTarget() {
        let (model, _, _) = lifted()
        model.refresh()
        #expect(model.liftedTab == nil && model.dropSlot == nil && model.gapSlot == nil)
    }
}
