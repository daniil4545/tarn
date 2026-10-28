import AppKit
import Testing
@testable import Ghostty

/// `tarn new`: the command line and the split that keeps the focus (`docs/specs/agent-cli.md` 4.2-4.4, B1, B2).
@Suite
struct NewPaneTests {
    /// Expected values are the output of Python `shlex.join` on the same arguments.
    @Test func argumentsAreQuotedAsShlexJoin() {
        let cases: [([String], String)] = [
            (["npm", "test"], "npm test"),
            (["sh", "-c", "a && b"], "sh -c 'a && b'"),
            (["echo", "it's"], "echo 'it'\"'\"'s'"),
            (["x", ""], "x ''"),
            (["café"], "'café'"),
            (["a=b", "@%+=:,./-_"], "a=b @%+=:,./-_"),
        ]
        for (argv, line) in cases {
            #expect(ShellQuote.join(argv) == line, "\(argv)")
        }
    }

    /// spec: agent-cli B2 - a newline or a carriage return would press Enter.
    @Test @MainActor func aCommandOfMoreThanOneLineIsRefused() {
        for argument in ["a\nb", "a\rb", "a\r\nb"] {
            #expect(ShellQuote.join(["echo", argument]) == nil)
        }
        let caller = PaneRow(pane: UUID(), tab: UUID(), workspace: UUID())
        let scope = AgentScope(caller: caller, panes: [caller])
        let refusal = NewPane.run(["argv": ["echo", "a\nb"]], scope)
        #expect(throws: NewPane.notOneLine) { try refusal.get() }
    }

    /// spec: agent-cli B1 - the split goes below the caller and the first responder stays. A focused view
    /// outside the tree keeps its focus in a hidden window either way, so only a pane is tested here.
    @Test @MainActor func theSplitGoesBelowAndKeepsTheFocus() async throws {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty)
        // Not shown: the window tests that count visible windows are not disturbed.
        let controller = TerminalController(app)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let caller = try #require(controller.surfaceTree.first)
        let deadline = ContinuousClock.now + .seconds(5)
        while caller.window !== window, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        window.makeFirstResponder(caller)
        try #require(window.firstResponder === caller, "the caller never took the focus")
        let active = NSApp.isActive
        let key = NSApp.keyWindow

        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/cat"
        let pane = try #require(NewPane.split(controller, at: caller, direction: .down, config: config))

        #expect(Array(controller.surfaceTree).map(\.id) == [caller.id, pane.id])
        guard case .split(let split) = controller.surfaceTree.root else {
            Issue.record("no split")
            return
        }
        #expect(split.direction == .vertical)
        try await Task.sleep(for: .milliseconds(400))
        #expect(window.firstResponder === caller)
        #expect(NSApp.isActive == active)
        #expect(NSApp.keyWindow === key)
    }

    /// spec: T-218 - the pane runs under Ghostty's login; `ls` names the command and its folder, not login's.
    @Test @MainActor func aNewPaneShowsItsCommandAndFolder() async throws {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty)
        let controller = TerminalController(app)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let caller = try #require(controller.surfaceTree.first)

        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/sleep 30"
        config.workingDirectory = "/tmp"
        let pane = try #require(NewPane.split(controller, at: caller, direction: .down, config: config))

        var process = ""
        // The CI runner runs 4 test jobs at once; the shell there took over 5 s to exec the command.
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline {
            process = pane.surfaceModel?.foregroundPID
                .flatMap { AgentProcess.comm(pid: AgentProcess.foreground(group: pid_t($0))) } ?? ""
            if process == "sleep" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(process == "sleep")
        #expect(pane.workingDirectory == "/private/tmp")
    }
}
