import Foundation
import Testing
@testable import Ghostty

/// `tarn run`: the login shell gets the line typed and never submitted (`docs/specs/agent-cli.md` 4.5, B2).
@Suite
struct RunPaneTests {
    // spec: docs/specs/agent-cli.md U5
    @Test @MainActor func anUngroupedRunCannotOpenATab() {
        let caller = PaneRow(pane: UUID(), tab: UUID(), workspace: nil)
        let result = NewPane.open(["tab": true, "argv": ["echo", "hi"]], AgentScope(caller: caller, panes: [caller]), kind: .run)
        #expect(throws: AgentRefusal(text: "put this tab in a group first")) { try result.get() }
    }

    // spec: docs/specs/agent-cli.md U5
    @Test func frozenWorkspacesRefuseEvenAGroupedCaller() {
        #expect(NewTab.refusal(group: UUID(), frozen: true) == AgentRefusal(text: "put this tab in a group first"))
        #expect(NewTab.refusal(group: nil, frozen: false) == AgentRefusal(text: "put this tab in a group first"))
        #expect(NewTab.refusal(group: UUID(), frozen: false) == nil)
    }

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
            ("a\u{0F}", NewPane.controlCharacter),
            ("a\tb", NewPane.controlCharacter),
            ("\u{1B}[A", NewPane.controlCharacter),
            ("a\u{7F}", NewPane.controlCharacter),
            ("a\u{85}b", NewPane.controlCharacter),
        ]
        for (argument, refusal) in cases {
            let result = NewPane.open(["argv": ["echo", argument]], scope, kind: .run)
            #expect(throws: refusal, "\(argument.debugDescription)") { try result.get() }
        }
    }

    /// The caller is not a live surface here, so a printable line passes the key check and stops at the tab.
    @Test @MainActor func aPrintableLineReachesTheSplit() {
        let caller = PaneRow(pane: UUID(), tab: UUID(), workspace: UUID())
        let scope = AgentScope(caller: caller, panes: [caller])
        let result = NewPane.open(["argv": ["echo", "it's café"]], scope, kind: .run)
        #expect(throws: AgentRefusal.notInTab) { try result.get() }
    }
}
