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

    @Test(arguments: [
        // The card's command is on screen: the key goes.
        ("Bash command\n  make test\n❯ 1. Yes\n  2. No", true),
        // Another command's dialog: no key.
        ("Bash command\n  rm -rf build\n❯ 1. Yes\n  2. No", false),
        // No dialog at all.
        ("make test\n> ", false),
        // The card's command is in the transcript far above another command's dialog.
        ("⏺ Bash(make test)\n" + String(repeating: "  output\n", count: 14)
            + "Bash command\n  rm -rf build\n❯ 1. Yes\n  2. No", false),
        // The first option is not a plain yes.
        ("Bash command\n  make test\n❯ 1. Yes, and always allow access to tmp/\n  2. No", false),
    ])
    func quickAnswerNeedsTheCardsDialogOnScreen(screen: String, sends: Bool) {
        let request = AgentRequest(kind: .tool, tool: "Bash", detail: "make test", options: [])
        #expect((SessionRegistry.key(answering: request, option: 0, screen: screen) != nil) == sends)
    }

    @Test func questionAnswerNeedsTheQuestionsOwnDialog() {
        let request = AgentRequest(kind: .question, tool: "AskUserQuestion", detail: "Ship it now?", options: ["Yes", "No"])
        let question = "Ship it now?\n❯ 1. Yes\n  2. No"
        // A permission dialog also has "1. Yes"; its "2." would approve for good.
        let permission = "Bash command\n  make test\n❯ 1. Yes\n  2. Yes, and don't ask again\n  3. No"
        #expect(SessionRegistry.key(answering: request, option: 1, screen: question) != nil)
        #expect(SessionRegistry.key(answering: request, option: 1, screen: permission) == nil)
    }

    @Test func absoluteCommandIsMatchedByItsStartNotItsLastWord() {
        let request = AgentRequest(kind: .tool, tool: "Bash", detail: "/bin/rm -rf /x/data", options: [])
        let other = "Bash command\n  cp data backup/data\n❯ 1. Yes\n  2. No"
        #expect(SessionRegistry.key(answering: request, option: 0, screen: other) == nil)
    }

    @Test func permissionOwnerResetsWithTheNextTurn() {
        var subAsk = ask
        subAsk["agent_id"] = "s1"
        let subTool: [String: Any] = ["hook_event_name": "PostToolUse", "agent_id": "s1"]
        let late: [String: Any] = ["hook_event_name": "Notification", "notification_type": "permission_prompt"]
        #expect(session(after: [prompt, subAsk, subTool, prompt, late, toolDone]).state == .working)
    }

    @Test func jumpSkipsClosedSurfaces() {
        // The closed one waits longer, so it would win if it counted.
        let closed = AgentSession(surfaceID: UUID(), state: .waiting, since: .distantPast, seen: false)
        let open = AgentSession(surfaceID: UUID(), state: .waiting, since: Date(), seen: false)
        #expect(SessionRegistry.nextWaiting([closed, open], alive: [open.surfaceID]) == open.surfaceID)
        #expect(SessionRegistry.nextWaiting([closed, open], alive: [closed.surfaceID, open.surfaceID]) == closed.surfaceID)
    }

    @Test func quickAnswerMatchesAFileByItsName() {
        let request = AgentRequest(kind: .tool, tool: "Edit", detail: "/u/dev/tarn/docs/spec.md", options: [], detailIsPath: true)
        let screen = "Edit file\n  docs/spec.md\n❯ 1. Yes\n  2. No"
        #expect(SessionRegistry.key(answering: request, option: 0, screen: screen) != nil)
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
