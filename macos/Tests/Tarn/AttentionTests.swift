import Foundation
import Testing
@testable import Ghostty

/// The jump order, the notification gate and the suppression rule of `docs/spec.md` R4.
@Suite
struct AttentionTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ state: AgentState, failed: Bool = false, seen: Bool = false, age: TimeInterval = 0,
        note: String = ""
    ) -> AgentSession {
        var session = AgentSession(surfaceID: UUID())
        session.state = state
        session.failed = failed
        session.seen = seen
        session.since = base.addingTimeInterval(-age)
        session.note = note
        session.noteSince = base.addingTimeInterval(-age)
        return session
    }

    private func ids(_ sessions: [AgentSession]) -> [UUID] { sessions.map(\.surfaceID) }

    // MARK: Jump order

    @Test func failedThenPermissionThenWaiting() {
        let waiting = session(.waiting, age: 300)
        let permission = session(.permission, age: 10)
        let failed = session(.waiting, failed: true, age: 1)
        let order = AttentionJump.order([waiting, permission, failed])
        #expect(ids(order) == ids([failed, permission, waiting]))
    }

    @Test func failedFirstThenTheUnseenWaitingThatStartedEarlier() {
        let failed = session(.waiting, failed: true, age: 5)
        let late = session(.waiting, age: 60)
        let early = session(.waiting, age: 600)
        let order = AttentionJump.order([late, failed, early])
        #expect(ids(order) == ids([failed, early, late]))
    }

    @Test func unseenBeforeSeenInsideAGroup() {
        let seenOld = session(.waiting, seen: true, age: 900)
        let unseenNew = session(.waiting, seen: false, age: 5)
        #expect(ids(AttentionJump.order([seenOld, unseenNew])) == ids([unseenNew, seenOld]))
    }

    @Test func idleAndWorkingWithoutNoteAreSkipped() {
        let order = AttentionJump.order([session(.idle), session(.working), session(.waiting)])
        #expect(order.count == 1)
    }

    @Test func aNoteMakesAnIdleSessionACandidateOrderedByWhenItWasSet() {
        let waiting = session(.waiting, age: 100)
        let older = session(.idle, seen: true, age: 500, note: "look")
        let newer = session(.idle, seen: true, age: 1, note: "again")
        let failed = session(.waiting, failed: true)
        let order = AttentionJump.order([newer, waiting, older, failed])
        #expect(ids(order) == ids([failed, older, waiting, newer]))
    }

    @Test func cursorStepsAfterTheFocusedSessionAndWraps() {
        let a = session(.waiting, age: 300)
        let b = session(.waiting, age: 200)
        let c = session(.waiting, age: 100)
        let ordered = AttentionJump.order([c, a, b])
        #expect(AttentionJump.next(in: ordered, focused: nil)?.surfaceID == a.surfaceID)
        #expect(AttentionJump.next(in: ordered, focused: a.surfaceID)?.surfaceID == b.surfaceID)
        #expect(AttentionJump.next(in: ordered, focused: c.surfaceID)?.surfaceID == a.surfaceID)
        #expect(AttentionJump.next(in: ordered, focused: UUID())?.surfaceID == a.surfaceID)
    }

    @Test func seenFailedKeepsCyclingAndNothingLeftMeansNil() {
        let failed = session(.waiting, failed: true, seen: true)
        let waiting = session(.waiting, age: 50)
        let ordered = AttentionJump.order([waiting, failed])
        #expect(AttentionJump.next(in: ordered, focused: failed.surfaceID)?.surfaceID == waiting.surfaceID)
        #expect(AttentionJump.next(in: ordered, focused: waiting.surfaceID)?.surfaceID == failed.surfaceID)
        #expect(AttentionJump.next(in: [failed], focused: failed.surfaceID) == nil)
        #expect(AttentionJump.next(in: [], focused: nil) == nil)
    }

    // MARK: Gate

    @Test func raisesOncePerNeed() {
        let idle = session(.idle, seen: true)
        var permission = idle
        permission.state = .permission
        permission.seen = false
        #expect(Attention.body(old: idle, new: permission, focused: false) == "Needs your permission")
        #expect(Attention.body(old: permission, new: permission, focused: false) == nil)

        var waiting = permission
        waiting.state = .waiting
        #expect(Attention.body(old: permission, new: waiting, focused: false) == "Waiting for you")

        var failed = waiting
        failed.failed = true
        #expect(Attention.body(old: waiting, new: failed, focused: false) == "Failed, see the session")
    }

    @Test func aNewPermissionRequestIsANewNeed() {
        var first = session(.permission)
        first.request = AgentRequest(kind: .tool, tool: "Bash", detail: "make", options: [])
        var second = first
        second.request = AgentRequest(kind: .tool, tool: "Bash", detail: "rm x", options: [])
        #expect(Attention.body(old: first, new: second, focused: false) == "Needs your permission")
        #expect(Attention.body(old: first, new: first, focused: false) == nil)
    }

    @Test func focusedAndSeenSurfacesRaiseNothing() {
        let idle = session(.idle, seen: true)
        let waiting = session(.waiting)
        #expect(Attention.body(old: idle, new: waiting, focused: true) == nil)
        var escaped = waiting
        escaped.seen = true
        #expect(Attention.body(old: idle, new: escaped, focused: false) == nil)
    }

    @Test func workingAndIdleNeedNothing() {
        #expect(session(.working).need == nil)
        #expect(session(.idle).need == nil)
    }

    @Test func stopFailureMakesTheNeedFailed() {
        var record = AgentSession(surfaceID: UUID())
        record.handle("Stop", ["hook_event_name": "Stop"])
        #expect(record.need == .waiting)
        record.handle("StopFailure", ["hook_event_name": "StopFailure"])
        #expect(record.need == .failed)
    }

    // MARK: Notes

    @Test func noteTextIsTrimmedAndCut() {
        #expect(Attention.trimmed(note: "  hi \n") == "hi")
        #expect(Attention.trimmed(note: " \n").isEmpty)
        let long = String(repeating: "a", count: 900)
        #expect(Attention.trimmed(note: long).count == Attention.maxNote)
    }

    @Test func focusClearsTheNoteOfASeenSession() {
        var noted = session(.idle, seen: true, note: "look")
        let changed = noted.markFocused()
        let again = noted.markFocused()
        #expect(changed)
        #expect(noted.note.isEmpty)
        #expect(!again)
    }

    // MARK: Suppression key

    @Test func eventsSetAndSessionEndClearsTheAgentSessionID() {
        var record = AgentSession(surfaceID: UUID())
        record.handle("UserPromptSubmit", ["hook_event_name": "UserPromptSubmit", "session_id": "abc"])
        #expect(record.agentSessionID == "abc")
        record.handle("SessionEnd", ["hook_event_name": "SessionEnd", "reason": "clear", "session_id": "abc"])
        #expect(record.agentSessionID == "abc")
        record.handle("SessionEnd", ["hook_event_name": "SessionEnd", "reason": "logout"])
        #expect(record.agentSessionID.isEmpty)
    }
}
