import AppKit
import Testing
@testable import Ghostty

/// `tarn read` and `tarn close` (`docs/specs/agent-cli.md` 4.7, 4.8, B1, B3, B5).
@Suite
struct ReadClosePaneTests {
    private final class Sink: WaitSink {
        var lines: [[String: Any]] = []
        func send(_ line: Data) {
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { lines.append(object) }
        }
        func watchPeer(_ handler: @escaping @Sendable () -> Void) {}
    }

    private func scope() -> (AgentScope, foreign: PaneRow) {
        let caller = PaneRow(pane: UUID(), tab: UUID(), workspace: UUID())
        let foreign = PaneRow(pane: UUID(), tab: UUID(), workspace: UUID())
        let scope = AgentScope(caller: caller, panes: [caller])
        return (scope, foreign)
    }

    /// A terminal window that is not shown, with its first pane focused once it is in the window.
    @MainActor
    private func window() async throws -> (TerminalController, NSWindow, Ghostty.SurfaceView) {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty)
        let controller = TerminalController(app)
        let window = try #require(controller.window)
        let caller = try #require(controller.surfaceTree.first)
        try await until { caller.window === window }
        window.makeFirstResponder(caller)
        return (controller, window, caller)
    }

    @MainActor
    private func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    }

    /// herdr `pane read --lines N`: the last lines, the empty rows below the output are not lines.
    @Test func lastLinesDropTheEmptyRowsBelow() {
        let screen = "$ ls\na  \nb\nc\t\n\n   \n\n"
        #expect(ReadPane.last(2, of: screen) == "b\nc\n")
        #expect(ReadPane.last(80, of: screen) == "$ ls\na\nb\nc\n")
        #expect(ReadPane.last(1, of: "a\n\nb") == "b\n")
        #expect(ReadPane.last(3, of: "a\n\nb") == "a\n\nb\n")
        #expect(ReadPane.last(5, of: "\n\n") == "")
    }

    /// The CLI refuses a bad `--lines` first; the app refuses one that reaches it the same way.
    @Test @MainActor func badLinesIsRefused() {
        let (scope, _) = scope()
        for value: Any in [0, -1, "x", 2.5] {
            let result = ReadPane.run(["lines": value, "pane": scope.caller.pane.uuidString], scope)
            #expect(throws: ReadPane.badLines) { try result.get() }
        }
    }

    /// spec: agent-cli B3, B5 - a foreign or missing pane is exit 4 and nothing is read or closed.
    @Test @MainActor func aPaneOutsideTheWorkspaceIsNoMatch() {
        let (scope, foreign) = scope()
        for id in [foreign.pane.uuidString, UUID().uuidString] {
            #expect(throws: AgentRefusal.noPane(id)) { try ReadPane.run(["pane": id], scope).get() }
            #expect(throws: AgentRefusal.noPane(id)) { try ClosePane.run(["pane": id], scope).get() }
        }
    }

    @Test @MainActor func readShowsTheLastLinesOfANewPane() async throws {
        let (controller, window, caller) = try await window()
        defer { window.close() }
        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/sh -c 'printf \"a\\nb\\nc\\n\"; sleep 30'"
        let pane = try #require(NewPane.split(controller, at: caller, direction: .down, config: config))
        // "Last login: ... Oct" has a "c" too: wait for the output itself.
        try await until { ReadPane.screenText(pane).contains("b\nc") }
        #expect(ReadPane.last(2, of: ReadPane.screenText(pane)) == "b\nc\n")
        #expect(window.firstResponder === caller)
    }

    /// spec: agent-cli 4.8, B1 - the pane closes without an alert, its wait answers `closed`
    /// and the caller keeps the focus.
    @Test @MainActor func closeEndsTheWaitAndKeepsTheFocus() async throws {
        let (controller, window, caller) = try await window()
        defer { window.close() }
        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/sleep 30"
        let pane = try #require(NewPane.split(controller, at: caller, direction: .down, config: config))
        PaneWaits.shared.marks[pane.id] = RunMark(kind: .new)
        let sink = Sink()
        #expect(PaneWaits.shared.begin(pane: pane.id, facts: PaneFacts(), timeout: nil, reply: sink) == nil)
        try await until { window.firstResponder === caller }

        ClosePane.close(pane, in: controller)

        #expect(Array(controller.surfaceTree).map(\.id) == [caller.id])
        try await until { !sink.lines.isEmpty }
        #expect(sink.lines.first?["state"] as? String == "closed")
        try await Task.sleep(for: .milliseconds(300))
        #expect(window.firstResponder === caller)
        #expect(window.attachedSheet == nil)
    }
}
