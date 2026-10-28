import AppKit
import Testing
@testable import Ghostty

/// Cmd+W with several tabs in several workspaces closes the pane's tab only (D7, S15, S16), and
/// closing windows does not loop through the workspace registry.
@Suite(.serialized)
@MainActor
struct CloseTabTests {

    /// The visible tabs of the test's own window: other suites run in parallel with their own windows.
    private func live(_ first: NSWindow) -> [NSWindow] {
        (first.tabGroup?.windows ?? [first]).filter(\.isVisible)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// A redraw that publishes again (the sidebar calls `sync`, `sync` publishes) must not stack
    /// one post on another: the posts run one after the other, a few at most.
    @Test func aRedrawThatPublishesAgainDoesNotNestPosts() {
        let registry = WorkspaceRegistry.shared
        var depth = 0
        var deepest = 0
        var posts = 0
        let token = NotificationCenter.default.addObserver(forName: .terminalTabsDidChange, object: registry, queue: nil) { _ in
            MainActor.assumeIsolated {
                depth += 1
                posts += 1
                deepest = max(deepest, depth)
                registry.publish([UUID()])
                depth -= 1
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        registry.publish([UUID()])
        #expect(deepest == 1, "posts nested \(deepest) deep")
        #expect(posts == 3, "a publish that never settles stops after 3 rounds, got \(posts)")
    }

    // spec: docs/specs/workspace-folder.md S1, S3, Q1
    /// A folder makes a workspace named after it with one new tab; the same folder again selects
    /// that workspace and opens nothing.
    @Test func aFolderOpensItsWorkspaceOnceAndThenSelectsIt() async throws {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty)
        let registry = WorkspaceRegistry.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tarn-ws-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = TerminalController.newWindow(app)
        let firstWindow = try #require(first.window)
        try await wait { firstWindow.isVisible }
        registry.sync()

        #expect(registry.createWorkspace(folder: folder.path, from: firstWindow))
        try await wait { live(firstWindow).count == 2 }
        // The new group's tab stands before the ungrouped tab (G8).
        let runs = registry.runs(for: firstWindow).map { "\($0.workspace.name):\($0.windows.count)" }
        let opened = try #require(live(firstWindow).first { registry.workspace(of: $0)?.name == "proj" }, "runs \(runs)")
        let workspace = try #require(registry.workspace(of: opened))
        #expect(workspace.name == "proj")
        #expect(workspace.folder == WorkspaceFolder.standardized(folder.path))

        #expect(registry.createWorkspace(folder: folder.path + "/", from: firstWindow))
        try await Task.sleep(for: .milliseconds(300))
        #expect(live(firstWindow).count == 2, "the same folder opens no second tab")

        for window in live(firstWindow) {
            (window.windowController as? TerminalController)?.closeWindowImmediately()
        }
        try await wait { live(firstWindow).isEmpty }
    }

    /// The first-day report: four tabs, Cmd+W on the 4th and then on the 3rd took the app down; the test goes on to the last tab.
    @Test func cmdWOnTheFourthAndThirdTabClosesOnlyThem() async throws {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty)
        let registry = WorkspaceRegistry.shared
        let first = TerminalController.newWindow(app)
        let firstWindow = try #require(first.window)
        try await wait { firstWindow.isVisible }
        registry.sync()

        // Tabs in tab order: B, B, "~", "~". The group B opens first, before the one ungrouped tab
        // (G8): one native move of one place. Longer moves abort inside AppKit in a hidden test host.
        let defaultID = try #require(registry.workspace(of: firstWindow)?.id)
        #expect(registry.createWorkspace(named: "B", from: firstWindow))
        try await wait { live(firstWindow).count == 2 }
        let third = try #require(live(firstWindow).first { registry.workspace(of: $0)?.name == "B" })
        let bID = try #require(registry.workspace(of: third)?.id)
        registry.newTab(in: bID, from: third)
        try await wait { live(firstWindow).count == 3 }
        registry.newTab(in: defaultID, from: firstWindow)
        try await wait { live(firstWindow).count == 4 }
        #expect(live(firstWindow).count == 4)
        #expect(Set(live(firstWindow).compactMap { $0.tabGroup?.windows.count }) == [4])

        // Cmd+W: the menu item "Close" sends `close:` to the window controller of the selected tab.
        for expected in [3, 2] {
            let tabs = live(firstWindow)
            let target = try #require(tabs.last { registry.workspace(of: $0)?.name == "B" } ?? tabs.last)
            target.makeKeyAndOrderFront(nil)
            let controller = try #require(target.windowController as? TerminalController)
            controller.close(self)
            // A shell that has not settled yet asks "Close Tab?"; the user answers Close.
            try await wait {
                if let sheet = target.attachedSheet { target.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
                return live(firstWindow).count == expected
            }
            #expect(live(firstWindow).count == expected)
            #expect(Set(live(firstWindow).compactMap { $0.tabGroup?.windows.count }) == [expected])
        }
        for window in live(firstWindow) {
            (window.windowController as? TerminalController)?.closeWindowImmediately()
        }
        try await wait { live(firstWindow).isEmpty }
    }

    /// The real Cmd+T path: the new tab is seen alone in its own window, then AppKit tabs it in.
    /// The native moves that follow wait one main-queue turn, outside AppKit's addTabbedWindow.
    @Test func cmdTInAGroupKeepsTheNewTabInThatGroup() async throws {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty)
        let registry = WorkspaceRegistry.shared
        let first = TerminalController.newWindow(app)
        let firstWindow = try #require(first.window)
        try await wait { firstWindow.isVisible }
        registry.sync()
        #expect(registry.createWorkspace(named: "B", from: firstWindow))
        try await wait { live(firstWindow).count == 2 }
        // spec: docs/specs/workspace-folder.md S4
        let b = try #require(live(firstWindow).first { registry.workspace(of: $0)?.name == "B" })
        b.makeKeyAndOrderFront(nil)
        (b.windowController as? TerminalController)?.newTab(nil)
        try await wait { live(firstWindow).count == 3 }
        let names = { live(firstWindow).map { registry.workspace(of: $0)?.name ?? "?" } }
        try? await wait { names() == ["B", "B", "~"] }
        #expect(names() == ["B", "B", "~"], "\(names())")
        for window in live(firstWindow) {
            (window.windowController as? TerminalController)?.closeWindowImmediately()
        }
        try await wait { live(firstWindow).isEmpty }
    }
}
