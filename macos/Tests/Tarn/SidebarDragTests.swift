import AppKit
import Testing
@testable import Ghostty

/// The lift and gap of a sidebar tab drag (T-236).
@MainActor
@Suite
struct SidebarDragTests {
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
}
