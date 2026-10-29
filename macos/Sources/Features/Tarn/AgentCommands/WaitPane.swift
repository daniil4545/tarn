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
    /// Only `confirm-close-surface = true` makes `needsConfirmQuit` mean "not at a prompt" (`src/Surface.zig:995`).
    var promptReadable = true
    /// The cursor sits at a prompt: only OSC 133 marks can say so (`Terminal.cursorIsAtPrompt`).
    var atPrompt = false
    /// Ghostty injects its OSC 133 integration into the pane's shell (`ShellIntegration.injects`).
    var integrationExpected = true
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

extension AgentRefusal {
    /// Otty `pane wait` exit 6: the pane cannot report the code.
    static let exitCodeUnknown = AgentRefusal(text: "exit code unknown", code: 6)
    static let noShellIntegration = AgentRefusal(text: "no shell integration", code: 6)
    static let timeout = AgentRefusal(text: "timeout", code: 9)
}

/// The rules of `docs/specs/agent-cli.md` 3 "What ends a wait", free of windows so a test can drive them.
enum WaitRule {
    /// The answer at once, or nil to park the wait until an end arrives.
    static func start(mark: RunMark?, facts: PaneFacts, integrated: Bool) -> Result<WaitOutcome, AgentRefusal>? {
        if mark?.kind == .new {
            // U8: Ghostty reports no exit code of a configured command on macOS.
            return facts.processExited ? .failure(.exitCodeUnknown) : nil
        }
        // Otty `pane wait`: a pane that cannot report an end says so at once instead of hanging.
        // A readable prompt mark is OSC 133 too (`Terminal.cursorIsAtPrompt`): integrated by hand.
        let marked = facts.promptReadable && facts.atPrompt
        guard integrated || marked || facts.integrationExpected else { return .failure(.noShellIntegration) }
        // Never answer idle early: without a readable prompt the next finish is the only sign.
        guard facts.promptReadable else { return nil }
        // A `run` pane looks idle before Enter; an old command's code is not this wait's.
        return facts.atPrompt && mark?.kind != .run ? .success(WaitOutcome(state: "succeed", exitCode: nil, durationMs: 0)) : nil
    }
}

/// Whether Ghostty injects its OSC 133 integration, by its own rule (`src/termio/shell_integration.zig:43-167`).
enum ShellIntegration {
    /// `setting` is the `shell-integration` value; `shell` the command Ghostty started in the pane,
    /// nil when no process is readable, and the wait parks.
    static func injects(setting: String?, shell: String?) -> Bool {
        switch setting {
        case "none": return false
        case nil, "detect": break
        default: return true
        }
        guard let shell else { return true }
        // Apple's bash 3.2 ignores the ENV startup path Ghostty injects through.
        guard shell != "/bin/bash" else { return false }
        return ["bash", "elvish", "fish", "nu", "zsh"].contains((shell as NSString).lastPathComponent)
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
    }

    static let longestTimeout = 365.0 * 86400

    var marks: [UUID: RunMark] = [:]
    private var integrated = Set<UUID>()
    private var waits: [Wait] = []

    /// Panes that still exist; tests replace it.
    var exists: (UUID) -> Bool = { SessionRegistry.surfaceView($0) != nil }

    var pendingCount: Int { waits.count }

    /// The calls Ghostty's callbacks make; they run on the main thread.
    nonisolated static func commandFinished(pane: UUID, exitCode: Int, durationNs: UInt64) {
        MainActor.assumeIsolated { shared.commandFinished(pane: pane, exitCode: exitCode, durationNs: durationNs) }
    }
    nonisolated static func childExited(pane: UUID) { MainActor.assumeIsolated { shared.childExited(pane: pane) } }
    nonisolated static func surfaceTreeChanged() { MainActor.assumeIsolated { shared.surfaceTreeChanged() } }

    /// Starts a wait: the answer at once, or nil while the reply is held.
    func begin(pane: UUID, facts: PaneFacts, timeout: Double?, reply: any WaitSink) -> Result<[String: Any], AgentRefusal>? {
        if let now = WaitRule.start(mark: marks[pane], facts: facts, integrated: integrated.contains(pane)) {
            return now.map(\.fields)
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
        // A cancelled wait (its CLI killed) is released when its connection closes.
        reply.watchPeer { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish(id, nil) } }
        }
        return nil
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
            marks[pane] = nil
            integrated.remove(pane)
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

    private func answer(_ pane: UUID, _ result: Result<[String: Any], AgentRefusal>) {
        for wait in waits where wait.pane == pane { finish(wait.id, result) }
    }

    /// Ends a wait with an answer, or with none (nil) when its connection is already gone.
    private func finish(_ id: UUID, _ result: Result<[String: Any], AgentRefusal>?) {
        guard let index = waits.firstIndex(where: { $0.id == id }) else { return }
        let wait = waits.remove(at: index)
        wait.timer?.cancel()
        if let result { wait.reply.send(AgentCommands.encode("wait", result, surface: wait.pane.uuidString)) }
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

    /// The live value of an enum option, such as `confirm-close-surface` (`true`, `false`, `always`).
    @MainActor
    private static func option(_ key: String) -> String? {
        guard let config = (NSApp.delegate as? AppDelegate)?.ghostty.config.config else { return nil }
        var value: UnsafePointer<Int8>?
        guard ghostty_config_get(config, &value, key, UInt(key.utf8.count)), let value else { return nil }
        return String(cString: value)
    }

    @MainActor
    static func facts(of view: Ghostty.SurfaceView) -> PaneFacts {
        let pid = view.surfaceModel?.foregroundPID.map { AgentProcess.foreground(group: pid_t($0)) }
        return PaneFacts(
            processExited: view.processExited,
            promptReadable: option("confirm-close-surface") == "true",
            atPrompt: !view.needsConfirmQuit,
            integrationExpected: ShellIntegration.injects(
                setting: option("shell-integration"), shell: pid.flatMap(AgentProcess.paneShell(below:)) ?? getpwuid(getuid()).flatMap { $0.pointee.pw_shell.map { String(cString: $0) } })
        )
    }
}
