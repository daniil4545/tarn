import Foundation
import Testing
@testable import Ghostty

/// The agent state machine of `docs/spec.md` section 8, fed with hook events as Claude Code sends them.
@Suite
struct AgentSessionTests {
    private func session(after events: [[String: Any]]) -> AgentSession {
        var session = AgentSession(surfaceID: UUID())
        for event in events {
            session.handle(event["hook_event_name"] as? String ?? "", event)
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

    @Test func parallelSubagentToolDoesNotClearAnotherAgentsPermission() {
        let otherTool: [String: Any] = ["hook_event_name": "PostToolUse", "agent_id": "s2"]
        #expect(session(after: [prompt, ask, otherTool]).state == .permission)

        var subAsk = ask
        subAsk["agent_id"] = "s1"
        #expect(session(after: [prompt, subAsk, toolDone]).state == .permission)
        #expect(session(after: [prompt, subAsk, otherTool]).state == .permission)
    }

    private func decision(_ data: Data?) -> [String: Any]? {
        guard let data, data.last == UInt8(ascii: "\n"),
              let output = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let specific = output["hookSpecificOutput"] as? [String: Any],
              specific["hookEventName"] as? String == "PermissionRequest"
        else { return nil }
        return specific["decision"] as? [String: Any]
    }

    @Test func cardAllowsOrDeniesATool() {
        let request = AgentRequest(kind: .tool, tool: "Bash", detail: "make test", options: [])
        let allow = decision(SessionRegistry.decision(for: request, input: [:], option: 0))
        let deny = decision(SessionRegistry.decision(for: request, input: [:], option: 1))
        #expect(allow?["behavior"] as? String == "allow")
        #expect(deny?["behavior"] as? String == "deny")
        let message = deny?["message"] as? String
        #expect(message?.isEmpty == false)
    }

    @Test func cardAnswersAQuestionWithTheChosenLabel() {
        let request = AgentRequest(kind: .question, tool: "AskUserQuestion", detail: "Ship it now?", options: ["Yes", "Later"])
        let input: [String: Any] = ["questions": [["question": "Ship it now?"]]]
        let answer = decision(SessionRegistry.decision(for: request, input: input, option: 1))
        let updated = answer?["updatedInput"] as? [String: Any]
        #expect(answer?["behavior"] as? String == "allow")
        #expect(updated?["answers"] as? [String: String] == ["Ship it now?": "Later"])
        #expect(updated?["questions"] != nil)
        #expect(SessionRegistry.decision(for: request, input: input, option: 2) == nil)
    }

    private final class Hook {}
    private let make: [String: Any] = ["command": "make test"]
    private let remove: [String: Any] = ["command": "rm -rf build"]

    private func waiting(_ inputs: [[String: Any]]) -> [PendingAnswer<Hook>] {
        inputs.map {
            PendingAnswer(request: AgentRequest(kind: .tool, tool: "Bash", detail: $0["command"] as? String ?? "", options: []),
                          input: $0, reply: Hook())
        }
    }

    @Test(arguments: [
        // A finished call drops only its own request.
        ("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "make test"]], ["rm -rf build"]),
        ("PostToolUseFailure", ["tool_name": "Bash", "tool_input": ["command": "rm -rf build"]], ["make test"]),
        // Another tool's call, or a parallel one, leaves both waiting.
        ("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "ls"]], ["make test", "rm -rf build"]),
        // The end of a turn drops all; a subagent's end or work left in the background does not.
        ("Stop", [:], []),
        ("Stop", ["background_tasks": [["id": "a1"]]], ["make test", "rm -rf build"]),
        ("Stop", ["agent_id": "s1"], ["make test", "rm -rf build"]),
        ("StopFailure", [:], []),
        ("SessionEnd", [:], []),
        ("UserPromptSubmit", [:], []),
        ("Notification", ["notification_type": "permission_prompt"], ["make test", "rm -rf build"]),
    ] as [(String, [String: Any], [String])])
    func waitingHookEndsWithItsCallOrTheTurn(name: String, event: [String: Any], left: [String]) {
        let rest = PendingAnswer.remaining(waiting([make, remove]), after: name, event)
        #expect(rest.map(\.request.detail) == left)
    }

    // A question answered in the agent's own dialog finishes with its answers added to the input;
    // a call without a field of the wait, with another value, or of an empty wait leaves it.
    @Test(arguments: [
        (["questions": [["question": "Which?"]], "answers": ["Which?": "A"], "annotations": [String: Any]()], true),
        (["answers": ["Which?": "A"]], false),
        (["questions": [["question": "Other?"]], "answers": ["Other?": "A"]], false),
    ] as [([String: Any], Bool)])
    func questionAnsweredInTheDialogEndsItsWait(finished: [String: Any], ends: Bool) {
        let card = PendingAnswer(request: AgentRequest(kind: .question, tool: "AskUserQuestion", detail: "Which?", options: ["A"]),
                                 input: ["questions": [["question": "Which?"]]], reply: Hook())
        let event: [String: Any] = ["tool_name": "AskUserQuestion", "tool_input": finished]
        #expect(PendingAnswer.remaining([card], after: "PostToolUse", event).isEmpty == ends)
    }

    // A parallel call whose input holds another's ends its own wait, not the other.
    @Test func exactCallEndsItsOwnWaitFirst() {
        let plain: [String: Any] = ["command": "ls"]
        var background = plain
        background["run_in_background"] = true
        let event: [String: Any] = ["tool_name": "Bash", "tool_input": background]
        let rest = PendingAnswer.remaining(waiting([plain, background]), after: "PostToolUse", event)
        #expect(rest.map { $0.input.count } == [1])

        let empty = waiting([[:]])
        #expect(PendingAnswer.remaining(empty, after: "PostToolUse", event).count == 1)
    }

    @Test func waitingHookHoldsThePermissionCard() {
        let first = AgentRequest(kind: .tool, tool: "Bash", detail: "make test", options: [])
        var shown = session(after: [prompt, toolDone])
        shown.show(waiting: first)
        #expect(shown.state == .permission)
        #expect(shown.request == first)
        #expect(shown.answerable)

        // Without a waiting hook the card shows no buttons; the agent's own dialog answers.
        var dialog = session(after: [prompt, ask])
        dialog.show(waiting: nil)
        #expect(dialog.state == .permission)
        #expect(!dialog.answerable)
    }

    @Test func permissionOwnerResetsWithTheNextTurn() {
        var subAsk = ask
        subAsk["agent_id"] = "s1"
        let subTool: [String: Any] = ["hook_event_name": "PostToolUse", "agent_id": "s1"]
        let late: [String: Any] = ["hook_event_name": "Notification", "notification_type": "permission_prompt"]
        #expect(session(after: [prompt, subAsk, subTool, prompt, late, toolDone]).state == .working)
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
