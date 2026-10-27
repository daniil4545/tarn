import AppKit
import GhosttyKit

/// How a pane was started by `tarn new` or `tarn run` (`docs/specs/agent-cli.md` 3, run mark).
struct RunMark: Equatable {
    enum Kind: Equatable { case new, run }
    let kind: Kind
    var command = ""
}

/// What a pane looked like when `wait` asked, read from the surface by `WaitPane`.
struct PaneFacts: Equatable {
    var processExited = false
    /// `confirm-close-surface = true`: only then `needsConfirmQuit` means "the cursor is not at a
    /// prompt" (`src/Surface.zig:995-1012`); `false` and `always` answer without looking.
    var promptReadable = true
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
        ["state": state, "command": command, "duration_ms": durationMs, "text": text, "exit_code": exitCode ?? NSNull()]
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
    static func start(mark: RunMark?, facts: PaneFacts, integrated: Bool) -> WaitStart {
        if mark?.kind == .new {
            // U8: Ghostty reports no exit code of a configured command on macOS.
            return facts.processExited ? .refuse(.exitCodeUnknown) : .park
        }
        // Never answer idle early: without a readable prompt the next finish is the only sign.
        guard facts.promptReadable else { return .park }
        if facts.atPrompt {
            // A `run` pane looks idle before the user presses Enter: it waits for the next finish.
            if mark?.kind == .run { return .park }
            // An old command's code is not this wait's: idle reports none.
            return .answer(WaitOutcome(state: "succeed", exitCode: nil, durationMs: 0))
        }
        if !integrated, facts.shellInForeground { return .refuse(.noShellIntegration) }
        return .park
    }
}

extension WaitRule {
    /// A parked wait on a pane that shows no prompt mark while the shell is back in the foreground:
    /// the command ended and no OSC 133 finish will come (`docs/specs/agent-cli.md` 4.6).
    static func stalled(mark: RunMark?, facts: PaneFacts, integrated: Bool) -> Bool {
        mark == nil && !integrated && facts.promptReadable && !facts.atPrompt && facts.shellInForeground
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
    static let shared: PaneWaits = {
        let waits = PaneWaits()
        waits.observeWindows()
        return waits
    }()

    private struct Wait {
        let id = UUID()
        let pane: UUID
        let started = Date()
        let reply: any WaitSink
        var timer: Task<Void, Never>?
        /// Ticks that saw the shell back in the foreground; a finish arrives within ms, so one is not enough.
        var shellSeen = 0
    }

    /// One year: `Task.sleep` never gets a huge value.
    static let longestTimeout = 365.0 * 86400

    private(set) var marks: [UUID: RunMark] = [:]
    private var integrated = Set<UUID>()
    private var waits: [Wait] = []

    /// Panes that still exist; tests replace it.
    var exists: (UUID) -> Bool = { SessionRegistry.surfaceView($0) != nil }

    /// What a pane looks like now; tests replace it.
    var factsOf: (UUID) -> PaneFacts? = { id in SessionRegistry.surfaceView(id).map(WaitPane.facts(of:)) }

    private var ticker: Task<Void, Never>?

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
        switch WaitRule.start(mark: marks[pane], facts: facts, integrated: integrated.contains(pane)) {
        case .answer(let outcome): return .success(outcome.fields)
        case .refuse(let refusal): return .failure(refusal)
        case .park: break
        }
        var wait = Wait(pane: pane, reply: reply)
        let id = wait.id
        if let timeout, timeout > 0 {
            wait.timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(min(timeout, Self.longestTimeout)))
                guard !Task.isCancelled else { return }
                self?.finish(id, .failure(.timeout))
            }
        }
        waits.append(wait)
        startTicker()
        // A cancelled wait (its CLI killed) is released when its connection closes.
        reply.watchPeer { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.release(id) } }
        }
        return nil
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled, self?.waits.isEmpty == false {
                try? await Task.sleep(for: .milliseconds(500))
                self?.tick()
            }
            self?.ticker = nil
        }
    }

    /// Looks again at the panes of parked waits: a command without OSC 133 marks ended when the shell
    /// is back in the foreground on two ticks in a row, and the wait says so instead of hanging.
    func tick() {
        for index in waits.indices {
            let pane = waits[index].pane
            guard let facts = factsOf(pane),
                  WaitRule.stalled(mark: marks[pane], facts: facts, integrated: integrated.contains(pane))
            else {
                waits[index].shellSeen = 0
                continue
            }
            waits[index].shellSeen += 1
        }
        for wait in waits where wait.shellSeen >= 2 { finish(wait.id, .failure(.noShellIntegration)) }
    }

    /// Ghostty `command_finished` of a shell pane; a negative code is "no code reported".
    func commandFinished(pane: UUID, exitCode: Int, durationNs: UInt64) {
        integrated.insert(pane)
        let code: Int? = exitCode >= 0 ? exitCode : nil
        let command = marks[pane]?.command ?? ""
        let result: Result<[String: Any], AgentRefusal> = code.map {
            .success(WaitOutcome.finished(code: $0, command: command, durationMs: Int(durationNs / 1_000_000)).fields)
        } ?? .failure(.exitCodeUnknown)
        answer(pane, result)
        // The finish the `run` pane waited for is spent: a later wait on the idle pane answers at once.
        if marks[pane]?.kind == .run { marks[pane] = nil }
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
        closed(panes: Set(waits.map(\.pane)).union(marks.keys).union(integrated).filter { !exists($0) })
    }

    /// Answers `closed` for the waits on `panes` and forgets their marks.
    func closed(panes: some Sequence<UUID>) {
        for pane in panes {
            if let started = waits.first(where: { $0.pane == pane })?.started {
                let outcome = WaitOutcome(state: "closed", exitCode: nil, durationMs: Int(Date().timeIntervalSince(started) * 1000))
                answer(pane, .success(outcome.fields))
            }
            forget(pane)
        }
    }

    /// A window closing takes its panes with it, though its surface tree stays unchanged.
    func observeWindows() {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let controller = (note.object as? NSWindow)?.windowController as? BaseTerminalController else { return }
                PaneWaits.shared.closed(panes: controller.surfaceTree.map(\.id))
            }
        }
    }

    private func forget(_ pane: UUID) {
        marks[pane] = nil
        integrated.remove(pane)
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

    /// The live value of `confirm-close-surface`: `true`, `false` or `always`.
    @MainActor
    private static var confirmCloseSurface: String? {
        guard let config = (NSApp.delegate as? AppDelegate)?.ghostty.config.config else { return nil }
        var value: UnsafePointer<Int8>?
        let key = "confirm-close-surface"
        guard ghostty_config_get(config, &value, key, UInt(key.utf8.count)), let value else { return nil }
        return String(cString: value)
    }

    @MainActor
    static func facts(of view: Ghostty.SurfaceView) -> PaneFacts {
        let pid = view.surfaceModel?.foregroundPID.map { AgentProcess.foreground(group: pid_t($0)) }
        let comm = pid.flatMap(AgentProcess.comm) ?? ""
        return PaneFacts(
            processExited: view.processExited,
            promptReadable: confirmCloseSurface == "true",
            atPrompt: !view.needsConfirmQuit,
            shellInForeground: ["zsh", "bash", "fish", "sh", "dash", "nu", "login"].contains(comm)
        )
    }
}
