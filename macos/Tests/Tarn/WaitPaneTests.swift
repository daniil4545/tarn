import Foundation
import Testing
@testable import Ghostty

/// `tarn wait`: what ends a wait and how it answers (`docs/specs/agent-cli.md` 3, 4.6, U4, U8).
@Suite
struct WaitPaneTests {
    private final class Sink: WaitSink {
        var lines: [[String: Any]] = []
        var hangUp: (@Sendable () -> Void)?
        func send(_ line: Data) {
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { lines.append(object) }
        }
        func watchPeer(_ handler: @escaping @Sendable () -> Void) { hangUp = handler }
    }

    private let pane = UUID()
    private let shell = PaneFacts(atPrompt: false, shellInForeground: true)
    private let busy = PaneFacts()
    private let idle = PaneFacts(atPrompt: true, shellInForeground: true)
    /// `confirm-close-surface` false or always: `needsConfirmQuit` says nothing about the prompt.
    private let blind = PaneFacts(promptReadable: false, atPrompt: true, shellInForeground: true)

    private func tick() async { try? await Task.sleep(for: .milliseconds(50)) }

    @Test func ruleTable() {
        let run = RunMark(kind: .run)
        let new = RunMark(kind: .new)
        struct Case {
            var mark: RunMark?
            var facts: PaneFacts
            var integrated: Bool
            var expected: Result<WaitOutcome, AgentRefusal>?
        }
        let cases = [
            Case(mark: nil, facts: idle, integrated: true, expected: .success(WaitOutcome(state: "succeed", exitCode: nil, durationMs: 0))),
            Case(mark: nil, facts: shell, integrated: false, expected: .failure(.noShellIntegration)),
            Case(mark: nil, facts: shell, integrated: true, expected: nil),
            Case(mark: nil, facts: busy, integrated: false, expected: nil),
            Case(mark: new, facts: busy, integrated: false, expected: nil),
            Case(mark: new, facts: PaneFacts(processExited: true), integrated: false, expected: .failure(.exitCodeUnknown)),
            Case(mark: run, facts: idle, integrated: true, expected: nil),
            Case(mark: nil, facts: blind, integrated: true, expected: nil),
            Case(mark: nil, facts: blind, integrated: false, expected: nil),
        ]
        for item in cases {
            let got = WaitRule.start(mark: item.mark, facts: item.facts, integrated: item.integrated)
            #expect(got == item.expected, "\(String(describing: item.mark)) \(item.facts)")
        }
    }

    /// Otty `pane run --format json`: succeed for 0, error otherwise.
    @Test func outcomeTextAndState() {
        #expect(WaitOutcome.finished(code: 0, durationMs: 1234).text == "succeed  exit 0  1.2s")
        #expect(WaitOutcome.finished(code: 2, durationMs: 50).state == "error")
        #expect(WaitOutcome(state: "closed", exitCode: nil, durationMs: 3000).text == "closed  exit -  3.0s")
        #expect(WaitOutcome(state: "succeed", exitCode: nil, durationMs: 0).fields["exit_code"] is NSNull)
    }

    @MainActor @Test func shellCommandFinishAnswersEveryWaitOfThePane() {
        let waits = PaneWaits()
        let one = Sink(), two = Sink()
        #expect(waits.begin(pane: pane, facts: busy, timeout: nil, reply: one) == nil)
        #expect(waits.begin(pane: pane, facts: busy, timeout: nil, reply: two) == nil)
        waits.commandFinished(pane: pane, exitCode: 3, durationNs: 2_500_000_000)
        for sink in [one, two] {
            #expect(sink.lines.first?["state"] as? String == "error")
            #expect(sink.lines.first?["exit_code"] as? Int == 3)
            #expect(sink.lines.first?["duration_ms"] as? Int == 2500)
        }
        #expect(waits.pendingCount == 0)
    }

    /// An idle pane answers at once with no code, even after an earlier finish: that code is not this wait's.
    @MainActor @Test func idlePaneAnswersAtOnceWithoutACode() throws {
        let waits = PaneWaits()
        waits.commandFinished(pane: pane, exitCode: 1, durationNs: 0)
        let result = try #require(waits.begin(pane: pane, facts: idle, timeout: nil, reply: Sink()))
        let fields = try result.get()
        #expect(fields["state"] as? String == "succeed")
        #expect(fields["exit_code"] is NSNull)
        #expect(fields["text"] as? String == "succeed  exit -  0.0s")
    }

    /// With `confirm-close-surface` not `true` the prompt cannot be read: wait for the next finish.
    @MainActor @Test func unreadablePromptWaitsForTheNextFinish() {
        let waits = PaneWaits()
        let sink = Sink()
        #expect(waits.begin(pane: pane, facts: blind, timeout: nil, reply: sink) == nil)
        #expect(sink.lines.isEmpty)
        waits.commandFinished(pane: pane, exitCode: 0, durationNs: 0)
        #expect(sink.lines.first?["state"] as? String == "succeed")
    }

    /// A closing window answers `closed` for its panes only, though its surface tree does not change.
    @MainActor @Test func closingAWindowAnswersItsPanes() {
        let waits = PaneWaits()
        let mine = Sink(), other = Sink()
        let elsewhere = UUID()
        _ = waits.begin(pane: pane, facts: busy, timeout: nil, reply: mine)
        _ = waits.begin(pane: elsewhere, facts: busy, timeout: nil, reply: other)
        waits.closed(panes: [pane])
        #expect(mine.lines.first?["state"] as? String == "closed")
        #expect(other.lines.isEmpty)
        #expect(waits.pendingCount == 1)
    }

    /// U4, U8: a `new` pane ends with its process and the code is unknown.
    @MainActor @Test func newPaneEndsWithItsProcessWithoutACode() {
        let waits = PaneWaits()
        waits.marks[pane] = RunMark(kind: .new, command: "sleep 2")
        let sink = Sink()
        #expect(waits.begin(pane: pane, facts: busy, timeout: nil, reply: sink) == nil)
        waits.commandFinished(pane: UUID(), exitCode: 0, durationNs: 0)
        #expect(sink.lines.isEmpty)
        waits.childExited(pane: pane)
        #expect(sink.lines.first?["error"] as? String == "exit code unknown")
        #expect(sink.lines.first?["code"] as? Int == 6)
    }

    /// The `run` rule: an idle pane with a typed line waits for the next finish, not for idle.
    @MainActor @Test func runPaneWaitsForTheNextFinish() {
        let waits = PaneWaits()
        waits.marks[pane] = RunMark(kind: .run, command: "make")
        let sink = Sink()
        #expect(waits.begin(pane: pane, facts: idle, timeout: nil, reply: sink) == nil)
        waits.commandFinished(pane: pane, exitCode: 0, durationNs: 1_000_000_000)
        #expect(sink.lines.first?["state"] as? String == "succeed")
        #expect(sink.lines.first?["command"] as? String == "make")
    }

    /// Luvus pane_closed: a pane that left every tree answers `closed`; a live one keeps its wait.
    @MainActor @Test func closedPaneAnswersClosed() {
        let waits = PaneWaits()
        let sink = Sink()
        _ = waits.begin(pane: pane, facts: busy, timeout: nil, reply: sink)
        waits.exists = { _ in true }
        waits.sweep()
        #expect(sink.lines.isEmpty)
        waits.exists = { _ in false }
        waits.sweep()
        #expect(sink.lines.first?["state"] as? String == "closed")
        #expect(waits.pendingCount == 0)
    }

    @MainActor @Test func timeoutAnswersNine() async {
        let waits = PaneWaits()
        let sink = Sink()
        _ = waits.begin(pane: pane, facts: busy, timeout: 0.05, reply: sink)
        await tick()
        await tick()
        #expect(sink.lines.first?["code"] as? Int == 9)
        #expect(waits.pendingCount == 0)
    }

    /// Luvus: a cancelled wait is released when its connection closes, and a later end sends nothing.
    @MainActor @Test func hangUpReleasesTheWait() async {
        let waits = PaneWaits()
        let sink = Sink()
        _ = waits.begin(pane: pane, facts: busy, timeout: nil, reply: sink)
        sink.hangUp?()
        await tick()
        #expect(waits.pendingCount == 0)
        waits.commandFinished(pane: pane, exitCode: 0, durationNs: 0)
        #expect(sink.lines.isEmpty)
    }

    /// No OSC 133: a typed command ends, the shell is back, no finish comes. Two ticks answer exit 6.
    @MainActor @Test func shellBackWithoutMarksEndsTheWaitWithNoIntegration() {
        let waits = PaneWaits()
        let sink = Sink()
        _ = waits.begin(pane: pane, facts: busy, timeout: nil, reply: sink)
        waits.factsOf = { _ in self.shell }
        waits.tick()
        #expect(sink.lines.isEmpty, "one tick may be a finish still on its way")
        waits.tick()
        #expect(sink.lines.first?["error"] as? String == "no shell integration")
        #expect(sink.lines.first?["code"] as? Int == 6)
    }

    @MainActor @Test func aFinishThatArrivesFirstWinsOverTheStall() {
        let waits = PaneWaits()
        let sink = Sink()
        _ = waits.begin(pane: pane, facts: busy, timeout: nil, reply: sink)
        waits.factsOf = { _ in self.shell }
        waits.tick()
        waits.commandFinished(pane: pane, exitCode: 0, durationNs: 0)
        waits.tick()
        #expect(sink.lines.count == 1)
        #expect(sink.lines.first?["state"] as? String == "succeed")
    }

    @MainActor @Test func aBusyPaneResetsTheStallCount() {
        let waits = PaneWaits()
        let sink = Sink()
        _ = waits.begin(pane: pane, facts: busy, timeout: nil, reply: sink)
        for facts in [shell, busy, shell] {
            waits.factsOf = { _ in facts }
            waits.tick()
        }
        #expect(sink.lines.isEmpty)
    }

    /// The `run` mark is spent by the finish it waited for: the next wait on the idle pane answers at once.
    @MainActor @Test func aRunMarkIsConsumedByItsFinish() throws {
        let waits = PaneWaits()
        waits.marks[pane] = RunMark(kind: .run, command: "make")
        _ = waits.begin(pane: pane, facts: idle, timeout: nil, reply: Sink())
        waits.commandFinished(pane: pane, exitCode: 0, durationNs: 0)
        #expect(waits.marks[pane] == nil)
        let again = try #require(waits.begin(pane: pane, facts: idle, timeout: nil, reply: Sink()))
        #expect(try again.get()["state"] as? String == "succeed")
    }

    @MainActor @Test func aHugeTimeoutDoesNotCrash() {
        let waits = PaneWaits()
        let sink = Sink()
        #expect(waits.begin(pane: pane, facts: busy, timeout: 1e99, reply: sink) == nil)
        waits.closed(panes: [pane])
        #expect(sink.lines.first?["state"] as? String == "closed")
    }

    @MainActor @Test func sweepForgetsIntegratedPanesThatAreGone() {
        let waits = PaneWaits()
        waits.commandFinished(pane: pane, exitCode: 0, durationNs: 0)
        waits.exists = { _ in false }
        waits.sweep()
        let sink = Sink()
        // Not integrated any more: a shell in the foreground without a prompt is refused again.
        let result = waits.begin(pane: pane, facts: shell, timeout: nil, reply: sink)
        guard case .failure(let refusal)? = result else {
            Issue.record("the pane stayed integrated")
            return
        }
        #expect(refusal == .noShellIntegration)
    }

    /// A real socket pair: the other end closing fires the callback; its half-close does not.
    @Test func watchPeerFiresOnCloseAndNotOnHalfClose() async throws {
        var fds: [Int32] = [0, 0]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        let reply = ControlSocket.Reply(fd: fds[0], queue: DispatchQueue(label: "test.peer"))
        let fired = Flag()
        reply.watchPeer { fired.set() }
        shutdown(fds[1], SHUT_WR)
        try await Task.sleep(for: .milliseconds(1300))
        #expect(!fired.value, "a half-close is not a hang-up")
        close(fds[1])
        let deadline = ContinuousClock.now + .seconds(2)
        while !fired.value, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(fired.value)
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        var value: Bool { lock.withLock { flag } }
        func set() { lock.withLock { flag = true } }
    }

    /// Only the pane's own shell (child of login) is an idle prompt; a nested shell, `zsh -c` and a
    /// script interpreter have a shell for parent and are commands.
    @Test func onlyTheRootShellCountsAsShellInForeground() {
        let cases: [(comm: String?, parent: String?, root: Bool)] = [
            ("zsh", "login", true),
            ("bash", "login", true),
            ("bash", "zsh", false),
            ("zsh", "zsh", false),
            ("sh", "bash", false),
            ("env", "login", false),
            ("python3", "zsh", false),
            ("zsh", nil, false),
            (nil, "login", false),
        ]
        for item in cases {
            #expect(AgentProcess.isRootShell(comm: item.comm, parentComm: item.parent) == item.root, "\(item)")
        }
    }
}
