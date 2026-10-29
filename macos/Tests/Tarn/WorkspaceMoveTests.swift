import AppKit
import Testing
@testable import Ghostty

@Suite(.serialized)
@MainActor
struct WorkspaceMoveTests {
    @Test(arguments: 0..<6, [false, true])
    func nativeBlockMovePreservesSelection(selectedIndex: Int, toEnd: Bool) throws {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty)
        let controllers = (0..<6).map { _ in TerminalController(app) }
        let windows = try controllers.map { try #require($0.window) }
        defer {
            for controller in controllers {
                controller.surfaceTree = .init()
                controller.window?.close()
            }
        }
        for window in windows {
            window.isReleasedWhenClosed = false
            window.tabbingMode = .preferred
        }
        for index in 1..<windows.count {
            try #require(windows[index - 1].addTabbedWindowSafely(windows[index], ordered: .above))
        }
        let native = try #require(windows[0].tabGroup)
        let selected = windows[selectedIndex]
        native.selectedWindow = selected
        let keyWindow = NSApp.keyWindow
        let active = NSApp.isActive
        let registry = WorkspaceRegistry.shared
        let keys = windows.map { _ in TabKey() }
        let groupA = Workspace(name: "A"), groupB = Workspace(name: "B")
        let set = WorkspaceSet(workspaces: [groupA, groupB], members: [
            keys[1]: groupA.id, keys[2]: groupA.id, keys[3]: groupB.id, keys[4]: groupB.id,
        ])
        for (window, key) in zip(windows, keys) {
            registry.restore(WorkspaceSnapshot(set: set, tabKey: key, order: keys), for: window)
        }

        registry.moveWorkspace(groupA.id, beforeTab: toEnd ? nil : keys[0], in: windows[0])
        let indices = toEnd ? [0, 3, 4, 5, 1, 2] : [1, 2, 0, 3, 4, 5]
        #expect(native.windows == indices.map { windows[$0] })
        #expect(native.selectedWindow === selected)
        #expect(NSApp.keyWindow === keyWindow)
        #expect(NSApp.isActive == active)
        for (index, window) in native.windows.enumerated() {
            let terminal = try #require(window as? TerminalWindow)
            #expect(terminal.keyEquivalent == app.config.keyboardShortcut(for: "goto_tab:\(index + 1)").map { "\($0)" } ?? "")
            let snapshot = try #require(registry.snapshot(for: window))
            let restored = try WorkspaceSnapshot.decode(snapshot.encoded())
            #expect(restored.workspaces.map(\.id) == (toEnd ? [groupB.id, groupA.id] : [groupA.id, groupB.id]))
            #expect(restored.workspaces.first { $0.id == groupA.id }?.tabKeys == [keys[1], keys[2]])
        }
        // Move back before B, then repeat the same drop (a no-op).
        for _ in 0..<2 {
            registry.moveWorkspace(groupA.id, before: groupB.id, in: windows[0])
            #expect(native.windows == [0, 1, 2, 3, 4, 5].map { windows[$0] })
            #expect(native.selectedWindow === selected)
        }
    }
}
