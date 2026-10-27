import Foundation
import Testing
@testable import Ghostty

/// `tarn run`: the login shell gets the line typed and never submitted (`docs/specs/agent-cli.md` 4.5, B2).
@Suite
struct RunPaneTests {
    /// spec: agent-cli 4.5 - no command, so Ghostty starts the login shell; the line is typed input.
    @Test func theLineIsTypedIntoTheLoginShell() {
        let run = NewPane.configuration(.run, command: "sudo make install")
        #expect(run.command == nil)
        #expect(run.initialInput == "sudo make install")
        let new = NewPane.configuration(.new, command: "npm test")
        #expect(new.command == "npm test")
        #expect(new.initialInput == nil)
    }

    /// spec: agent-cli B2 - typed input carries no newline, carriage return or other key.
    @Test @MainActor func aKeyInTheLineIsRefused() {
        let caller = PaneRow(pane: UUID(), tab: UUID(), workspace: UUID())
        let scope = AgentScope(caller: caller, panes: [caller])
        let cases: [(String, AgentRefusal)] = [
            ("a\nb", NewPane.notOneLine),
            ("a\rb", NewPane.notOneLine),
            ("a\u{0F}", RunPane.controlCharacter),
            ("a\tb", RunPane.controlCharacter),
            ("\u{1B}[A", RunPane.controlCharacter),
            ("a\u{7F}", RunPane.controlCharacter),
        ]
        for (argument, refusal) in cases {
            let result = RunPane.run(["argv": ["echo", argument]], scope)
            #expect(throws: refusal, "\(argument.debugDescription)") { try result.get() }
        }
    }

    /// The caller is not a live surface here, so a printable line passes the key check and stops at the tab.
    @Test @MainActor func aPrintableLineReachesTheSplit() {
        let caller = PaneRow(pane: UUID(), tab: UUID(), workspace: UUID())
        let scope = AgentScope(caller: caller, panes: [caller])
        let result = RunPane.run(["argv": ["echo", "it's café"]], scope)
        #expect(throws: AgentRefusal.notInTab) { try result.get() }
    }
}
