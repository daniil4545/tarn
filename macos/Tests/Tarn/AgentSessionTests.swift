import Foundation
import Testing
@testable import Ghostty

/// The agent state machine of `docs/spec.md` section 8, fed with hook events as Claude Code sends them.
@Suite
struct AgentSessionTests {
    private func session(after events: [[String: Any]]) -> AgentSession {
        var session = AgentSession(surfaceID: UUID())
        for event in events {
            session.handle(event["hook_event_name"] as! String, event)
        }
        return session
    }

    private let prompt: [String: Any] = ["hook_event_name": "UserPromptSubmit"]
    private let ask: [String: Any] = [
        "hook_event_name": "PermissionRequest",
        "tool_name": "Bash",
        "tool_input": ["command": "make test"],
    ]
    private let toolDone: [String: Any] = ["hook_event_name": "PostToolUse", "tool_name": "Bash"]

    @Test func permissionRequestNeedsTheUserUntilTheToolRuns() {
        let asked = session(after: [prompt, ask])
        #expect(asked.state == .permission)
        #expect(asked.request?.detail == "make test")

        let approved = session(after: [prompt, ask, toolDone])
        #expect(approved.state == .working)
        #expect(approved.request == nil)
    }

    @Test func stopWithBackgroundTasksKeepsWorking() {
        let stop: [String: Any] = ["hook_event_name": "Stop", "background_tasks": [["id": "a1"]]]
        #expect(session(after: [prompt, stop]).state == .working)

        let done: [String: Any] = ["hook_event_name": "Stop", "background_tasks": [Any]()]
        #expect(session(after: [prompt, done]).state == .waiting)
    }

    @Test func subagentEventsOnlyRaiseOrClearPermission() {
        let finished: [String: Any] = ["hook_event_name": "Stop"]
        let subTool: [String: Any] = ["hook_event_name": "PostToolUse", "agent_id": "s1"]
        let subStop: [String: Any] = ["hook_event_name": "Stop", "agent_id": "s1"]
        #expect(session(after: [prompt, finished, subTool]).state == .waiting)
        #expect(session(after: [prompt, subStop]).state == .working)

        var subAsk = ask
        subAsk["agent_id"] = "s1"
        #expect(session(after: [prompt, subAsk]).state == .permission)
        #expect(session(after: [prompt, subAsk, subTool]).state == .working)
    }

    @Test func latePermissionPromptAfterAnsweredRequestIsIgnored() {
        let late: [String: Any] = ["hook_event_name": "Notification", "notification_type": "permission_prompt"]
        #expect(session(after: [prompt, ask, toolDone, late]).state == .working)
        #expect(session(after: [prompt, late]).state == .permission)
    }

    @Test func idlePromptDoesNotEndATurn() {
        let idle: [String: Any] = ["hook_event_name": "Notification", "notification_type": "idle_prompt"]
        #expect(session(after: [prompt, idle]).state == .working)
    }

    @Test func apiErrorMarksFailedUntilTheNextPrompt() {
        let failure: [String: Any] = ["hook_event_name": "StopFailure", "error": "rate_limit"]
        let failed = session(after: [prompt, failure])
        #expect(failed.state == .waiting)
        #expect(failed.failed)
        #expect(!session(after: [prompt, failure, prompt]).failed)
    }

    @Test func clearKeepsTheAgentOtherExitsEndIt() {
        let clear: [String: Any] = ["hook_event_name": "SessionEnd", "reason": "clear"]
        let exit: [String: Any] = ["hook_event_name": "SessionEnd", "reason": "prompt_input_exit"]
        #expect(session(after: [prompt, clear]).state == .waiting)
        #expect(session(after: [prompt, exit]).state == .idle)
    }

    @Test func questionWithOneSingleChoiceGetsQuickAnswers() {
        func question(multiSelect: Bool) -> [String: Any] {
            [
                "hook_event_name": "PermissionRequest",
                "tool_name": "AskUserQuestion",
                "tool_input": ["questions": [[
                    "question": "Which base?",
                    "multiSelect": multiSelect,
                    "options": [["label": "PR"], ["label": "Scratch"]],
                ]]],
            ]
        }
        let single = session(after: [prompt, question(multiSelect: false)]).request
        #expect(single?.kind == .question)
        #expect(single?.options == ["PR", "Scratch"])
        #expect(session(after: [prompt, question(multiSelect: true)]).request?.options == [])
    }
}
