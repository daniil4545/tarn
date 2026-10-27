import Foundation

/// How a pane was started by `tarn new` or `tarn run` (`docs/specs/agent-cli.md` 3, run mark).
struct RunMark: Equatable {
    enum Kind: Equatable { case new, run }
    let kind: Kind
    var command = ""
}

/// What a pane looked like when `wait` asked, read from the surface by `WaitPane`.
struct PaneFacts: Equatable {
    var processExited = false
    /// The cursor sits at a prompt: only OSC 133 marks can say so (`Terminal.cursorIsAtPrompt`).
    var atPrompt = false
    /// The foreground process is the shell itself, so nothing runs and no mark tells it.
    var shellInForeground = false
}

/// How a wait ended: the reply fields of `tarn wait`.
struct WaitOutcome: Equatable {
    let state: String
    let exitCode: Int?
    var command = ""
    let durationMs: Int

    var fields: [String: Any] {
        var fields: [String: Any] = ["state": state, "command": command, "duration_ms": durationMs, "text": text]
        if let exitCode { fields["exit_code"] = exitCode }
        return fields
    }

    /// `<state>  exit <code>  <duration>` (`docs/specs/agent-cli.md` 4.6).
    var text: String {
        "\(state)  exit \(exitCode.map(String.init) ?? "-")  \(String(format: "%.1f", Double(durationMs) / 1000))s"
    }

    /// Otty `pane run --format json`: `succeed` for code 0, `error` otherwise.
    static func finished(code: Int, command: String = "", durationMs: Int) -> WaitOutcome {
        WaitOutcome(state: code == 0 ? "succeed" : "error", exitCode: code, command: command, durationMs: durationMs)
    }
}

/// What `wait` does with a pane at the moment it is asked.
enum WaitStart: Equatable {
    case answer(WaitOutcome)
    case refuse(AgentRefusal)
    case park
}

extension AgentRefusal {
    /// Otty `pane wait` exit 6: the pane cannot report the code.
    static let exitCodeUnknown = AgentRefusal(text: "exit code unknown", code: 6)
    static let noShellIntegration = AgentRefusal(text: "no shell integration", code: 6)
    static let timeout = AgentRefusal(text: "timeout", code: 9)
}

/// The rules of `docs/specs/agent-cli.md` 3 "What ends a wait", free of windows so a test can drive them.
enum WaitRule {
    static func start(mark: RunMark?, facts: PaneFacts, integrated: Bool, lastExit: Int?) -> WaitStart {
        if mark?.kind == .new {
            // U8: Ghostty reports no exit code of a configured command on macOS.
            return facts.processExited ? .refuse(.exitCodeUnknown) : .park
        }
        if facts.atPrompt {
            // A `run` pane looks idle before the user presses Enter: it waits for the next finish.
            if mark?.kind == .run { return .park }
            return .answer(.finished(code: lastExit ?? 0, durationMs: 0))
        }
        if !integrated, facts.shellInForeground { return .refuse(.noShellIntegration) }
        return .park
    }
}

/// An answer that can be sent once, and tells when the other end hangs up.
protocol WaitSink: AnyObject {
    func send(_ line: Data)
    func watchPeer(_ handler: @escaping @Sendable () -> Void)
}

extension ControlSocket.Reply: WaitSink {}

/// The waits of `tarn wait` and the run marks, set by `new` and `run`. Ghostty reports the ends
/// through three calls: `commandFinished`, `childExited` and `surfaceTreeChanged`.
@MainActor
final class PaneWaits {
    static let shared = PaneWaits()

    private struct Wait {
        let id = UUID()
        let pane: UUID
        let started = Date()
        let reply: any WaitSink
        var timer: Task<Void, Never>?
    }

    private(set) var marks: [UUID: RunMark] = [:]
    private var integrated = Set<UUID>()
    private var lastExit: [UUID: Int] = [:]
    private var waits: [Wait] = []

    /// Panes that still exist; tests replace it.
    var exists: (UUID) -> Bool = { SessionRegistry.surfaceView($0) != nil }

    var pendingCount: Int { waits.count }

    /// The calls Ghostty's callbacks make; they run on the main thread.
    nonisolated static func commandFinished(pane: UUID, exitCode: Int, durationNs: UInt64) {
        MainActor.assumeIsolated { shared.commandFinished(pane: pane, exitCode: exitCode, durationNs: durationNs) }
    }

    nonisolated static func childExited(pane: UUID) {
        MainActor.assumeIsolated { shared.childExited(pane: pane) }
    }

    nonisolated static func surfaceTreeChanged() {
        MainActor.assumeIsolated { shared.surfaceTreeChanged() }
    }

    func mark(_ pane: UUID, _ mark: RunMark) {
        marks[pane] = mark
    }

    /// Starts a wait: the answer at once, or nil while the reply is held.
    func begin(pane: UUID, facts: PaneFacts, timeout: Double?, reply: any WaitSink) -> Result<[String: Any], AgentRefusal>? {
        switch WaitRule.start(mark: marks[pane], facts: facts, integrated: integrated.contains(pane), lastExit: lastExit[pane]) {
        case .answer(let outcome): return .success(outcome.fields)
        case .refuse(let refusal): return .failure(refusal)
        case .park: break
        }
        var wait = Wait(pane: pane, reply: reply)
        let id = wait.id
        if let timeout, timeout > 0 {
            wait.timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                self?.finish(id, .failure(.timeout))
            }
        }
        waits.append(wait)
        // A cancelled wait (its CLI killed) is released when its connection closes.
        reply.watchPeer { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.release(id) } }
        }
        return nil
    }

    /// Ghostty `command_finished` of a shell pane; a negative code is "no code reported".
    func commandFinished(pane: UUID, exitCode: Int, durationNs: UInt64) {
        integrated.insert(pane)
        let code: Int? = exitCode >= 0 ? exitCode : nil
        lastExit[pane] = code
        let command = marks[pane]?.command ?? ""
        let result: Result<[String: Any], AgentRefusal> = code.map {
            .success(WaitOutcome.finished(code: $0, command: command, durationMs: Int(durationNs / 1_000_000)).fields)
        } ?? .failure(.exitCodeUnknown)
        answer(pane, result)
    }

    /// Ghostty `show_child_exited`: ends the wait on a `new` pane; the code is unknown (U8).
    func childExited(pane: UUID) {
        guard marks[pane]?.kind == .new else { return }
        answer(pane, .failure(.exitCodeUnknown))
    }

    /// Ghostty `surfaceTreeDidChange`: a pane that left every tree is closed. A pane moved to another
    /// window is still found by the next tick and keeps its waits.
    func surfaceTreeChanged() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.sweep() } }
    }

    /// Answers `closed` for the waits of panes that no longer exist and forgets their marks.
    func sweep() {
        for pane in Set(waits.map(\.pane)) where !exists(pane) {
            let started = waits.first { $0.pane == pane }?.started ?? Date()
            let outcome = WaitOutcome(state: "closed", exitCode: nil, durationMs: Int(Date().timeIntervalSince(started) * 1000))
            answer(pane, .success(outcome.fields))
        }
        for pane in marks.keys where !exists(pane) { forget(pane) }
    }

    private func forget(_ pane: UUID) {
        marks[pane] = nil
        integrated.remove(pane)
        lastExit[pane] = nil
    }

    private func answer(_ pane: UUID, _ result: Result<[String: Any], AgentRefusal>) {
        for wait in waits where wait.pane == pane { finish(wait.id, result) }
    }

    private func finish(_ id: UUID, _ result: Result<[String: Any], AgentRefusal>) {
        guard let index = waits.firstIndex(where: { $0.id == id }) else { return }
        let wait = waits.remove(at: index)
        wait.timer?.cancel()
        wait.reply.send(AgentCommands.encode("wait", result, surface: wait.pane.uuidString))
    }

    private func release(_ id: UUID) {
        guard let index = waits.firstIndex(where: { $0.id == id }) else { return }
        waits.remove(at: index).timer?.cancel()
    }
}

/// `tarn wait <pane> [--timeout S]`: holds the reply until the pane reports an end
/// (`docs/specs/agent-cli.md` 4.6). Follows Otty `pane wait` and Luvus `pane_closed`.
enum WaitPane {
    /// Starts the wait; the answer line now, or nil when the reply is held until the end.
    @MainActor
    static func start(_ message: [String: Any], scope: AgentScope, reply: any WaitSink) -> Result<[String: Any], AgentRefusal>? {
        switch scope.pane(message["pane"] as? String) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(let row):
            let facts = SessionRegistry.surfaceView(row.pane).map(self.facts) ?? PaneFacts(processExited: true)
            return PaneWaits.shared.begin(pane: row.pane, facts: facts, timeout: message["timeout"] as? Double, reply: reply)
        }
    }

    @MainActor
    private static func facts(of view: Ghostty.SurfaceView) -> PaneFacts {
        let pid = view.surfaceModel?.foregroundPID.map { AgentProcess.foreground(group: pid_t($0)) }
        let comm = pid.flatMap(AgentProcess.comm) ?? ""
        return PaneFacts(
            processExited: view.processExited,
            atPrompt: !view.needsConfirmQuit,
            shellInForeground: ["zsh", "bash", "fish", "sh", "dash", "nu", "login"].contains(comm)
        )
    }
}
