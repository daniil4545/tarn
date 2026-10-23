import AppKit
import Combine
import OSLog

/// The agent state of one terminal surface. See `docs/spec.md` section 8.
enum AgentState: Int, Comparable {
    case idle, waiting, working, permission

    static func < (lhs: AgentState, rhs: AgentState) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What a session in `permission` waits for: a tool to approve or a question to answer.
struct AgentRequest: Equatable {
    enum Kind: Equatable { case tool, question }

    let kind: Kind
    /// The tool name, e.g. `Bash`.
    let tool: String
    /// The command, file or question text.
    let detail: String
    /// Question options in order; the n-th is chosen by the digit key n.
    let options: [String]
}

/// One agent session, keyed by its surface.
struct AgentSession: Equatable {
    let surfaceID: UUID
    var state: AgentState = .idle
    var since = Date()
    /// The user focused the surface after the last state change.
    var seen = true
    /// The last turn ended with an API error.
    var failed = false
    var request: AgentRequest?
    /// A `PermissionRequest` arrived during the current turn, so a late
    /// `permission_prompt` notification is a duplicate.
    var sawPermissionRequest = false

    /// The turn ended and the user has not looked at it yet.
    var isUnseenDone: Bool { state == .waiting && !seen }
}

extension AgentSession {
    /// The transition table of `docs/spec.md` section 8 with the corrections of the
    /// 2026-10-23 research: `PermissionRequest` is the permission signal, `Stop` with
    /// background tasks keeps working, and subagent events only raise or clear permission.
    mutating func handle(_ name: String, _ event: [String: Any]) {
        let isSubagent = event["agent_id"] is String

        switch name {
        case "UserPromptSubmit" where !isSubagent:
            state = .working
            failed = false
            request = nil
            sawPermissionRequest = false

        case "PermissionRequest":
            state = .permission
            request = Self.request(from: event)
            sawPermissionRequest = true

        case "PostToolUse", "PostToolUseFailure":
            if state == .permission || (!isSubagent && state != .working) {
                state = .working
                request = nil
            }

        case "Notification" where !isSubagent:
            switch event["notification_type"] as? String {
            case "permission_prompt" where state == .working && !sawPermissionRequest:
                state = .permission
            case "idle_prompt" where state == .idle:
                state = .waiting
            default:
                break
            }

        case "Stop" where !isSubagent:
            if let tasks = event["background_tasks"] as? [Any], !tasks.isEmpty {
                state = .working
            } else {
                state = .waiting
                request = nil
            }

        case "StopFailure" where !isSubagent:
            state = .waiting
            failed = true
            request = nil

        case "SessionEnd" where !isSubagent:
            // After /clear the same agent waits for input in the same surface.
            state = event["reason"] as? String == "clear" ? .waiting : .idle
            request = nil

        default:
            break
        }
    }

    static func request(from event: [String: Any]) -> AgentRequest {
        let tool = event["tool_name"] as? String ?? "tool"
        let input = event["tool_input"] as? [String: Any] ?? [:]

        if tool == "AskUserQuestion",
           let questions = input["questions"] as? [[String: Any]],
           let first = questions.first {
            let options = (first["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
            // Several questions or a multi-select need the full dialog; no quick answers then.
            let quick = questions.count == 1 && first["multiSelect"] as? Bool != true
            return AgentRequest(
                kind: .question,
                tool: tool,
                detail: first["question"] as? String ?? "",
                options: quick ? options : [])
        }

        let detail = input["command"] as? String
            ?? input["file_path"] as? String
            ?? input["url"] as? String
            ?? input["description"] as? String
            ?? ""
        return AgentRequest(kind: .tool, tool: tool, detail: detail, options: [])
    }
}

/// The only owner of agent state. Hook events arrive through the control socket; the
/// surface's own title and progress report close the gaps where Claude Code sends no event.
@MainActor
final class SessionRegistry {
    static let shared = SessionRegistry()

    private static let logger = Logger(subsystem: "tarn", category: "registry")

    private(set) var sessions: [UUID: AgentSession] = [:]
    private var socket: ControlSocket?
    private var timer: Timer?
    private var focusObservers: [UUID: AnyCancellable] = [:]

    /// When a working surface first looked idle by its own signals (Esc gives no event).
    private var idleSince: [UUID: Date] = [:]

    func start() {
        guard socket == nil else { return }
        let socket = ControlSocket { [weak self] line in self?.receive(line) }
        socket.start()
        self.socket = socket

        // Polls only sessions in `working` or `permission`; others cost nothing.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkLiveness() }
        }
    }

    // MARK: Events

    private func receive(_ line: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              message["version"] as? Int == 1,
              let surfaceText = message["surface"] as? String,
              let surfaceID = UUID(uuidString: surfaceText),
              let event = message["event"] as? [String: Any],
              let name = event["hook_event_name"] as? String
        else {
            Self.logger.info("dropped a malformed line")
            return
        }
        guard let view = Self.surfaceView(surfaceID) else {
            Self.logger.info("event \(name, privacy: .public) for unknown surface")
            return
        }

        var session = sessions[surfaceID] ?? AgentSession(surfaceID: surfaceID)
        let old = session
        session.handle(name, event)
        guard session != old else { return }

        if session.state != old.state {
            Self.logger.info("\(surfaceID, privacy: .public) \(String(describing: old.state), privacy: .public) -> \(String(describing: session.state), privacy: .public) on \(name, privacy: .public)")
            session.since = Date()
            session.seen = Self.isFocused(view)
            idleSince[surfaceID] = nil
        }
        update(session, view: view)
    }

    // MARK: Liveness

    /// Claude Code sends no event when the user presses Esc, during a turn or on a
    /// permission dialog. Its own signals close the gap: during a turn it shows a spinner
    /// in the title and an indeterminate progress report; after Esc the title is back to
    /// `✳`, the progress report is cleared and the screen says "Interrupted".
    private func checkLiveness() {
        for (id, session) in sessions where session.state == .working || session.state == .permission {
            guard let view = Self.surfaceView(id) else {
                remove(id)
                continue
            }

            let looksIdle: Bool
            switch session.state {
            case .working:
                looksIdle = view.progressReport == nil && view.title.hasPrefix("✳")
            default:
                looksIdle = Self.bottomLines(view).contains("Interrupted")
            }

            guard looksIdle else {
                idleSince[id] = nil
                continue
            }
            let first = idleSince[id] ?? Date()
            idleSince[id] = first
            guard Date().timeIntervalSince(first) >= 2 else { continue }

            Self.logger.info("\(id, privacy: .public) \(String(describing: session.state), privacy: .public) -> waiting on liveness")
            var next = session
            next.state = .waiting
            next.request = nil
            next.since = Date()
            // The user pressed Esc in this surface, so there is nothing new to see.
            next.seen = true
            idleSince[id] = nil
            update(next, view: view)
        }
    }

    // MARK: Actions

    /// Answers a permission request or a question from the sidebar card. The key goes
    /// to the surface only if the dialog is on its screen; otherwise the surface is focused.
    func answer(_ surfaceID: UUID, option: Int) {
        guard let session = sessions[surfaceID],
              session.state == .permission,
              let request = session.request,
              let view = Self.surfaceView(surfaceID),
              let model = view.surfaceModel
        else { return }

        let screen = Self.bottomLines(view, count: 30)
        let key: Ghostty.Input.KeyEvent?
        switch request.kind {
        case .tool:
            // Option 0 approves once ("1. Yes"); option 1 rejects like Esc.
            guard screen.contains("1. Yes") else { key = nil; break }
            key = option == 0
                ? .init(key: .digit1, text: "1")
                : .init(key: .escape)
        case .question:
            guard option < request.options.count, option < 9,
                  screen.contains(request.options[option]) else { key = nil; break }
            let digits: [Ghostty.Input.Key] = [.digit1, .digit2, .digit3, .digit4, .digit5,
                                                .digit6, .digit7, .digit8, .digit9]
            key = .init(key: digits[option], text: "\(option + 1)")
        }

        guard let key else {
            Self.logger.info("dialog not on screen, focusing the surface instead")
            focus(surfaceID)
            return
        }
        model.sendKeyEvent(key)
    }

    func focus(_ surfaceID: UUID) {
        guard let view = Self.surfaceView(surfaceID),
              let controller = view.window?.windowController as? BaseTerminalController
        else { return }
        controller.focusSurface(view)
    }

    /// Focuses the session that needs the user most: failed, then permission, then an
    /// unseen finished turn; within a group the oldest first.
    func focusNextWaiting() {
        func rank(_ s: AgentSession) -> Int? {
            if s.state == .waiting && s.failed && !s.seen { return 0 }
            if s.state == .permission { return 1 }
            if s.isUnseenDone { return 2 }
            return nil
        }
        let next = sessions.values
            .compactMap { s in rank(s).map { (s, $0) } }
            .min { ($0.1, $0.0.since) < ($1.1, $1.0.since) }
        if let next { focus(next.0.surfaceID) }
    }

    // MARK: Store

    private func update(_ session: AgentSession, view: Ghostty.SurfaceView) {
        sessions[session.surfaceID] = session
        observeFocus(view)
        NotificationCenter.default.post(name: .terminalTabsDidChange, object: nil)
    }

    private func remove(_ id: UUID) {
        sessions[id] = nil
        focusObservers[id] = nil
        idleSince[id] = nil
        NotificationCenter.default.post(name: .terminalTabsDidChange, object: nil)
    }

    /// Focusing a surface marks its session seen.
    private func observeFocus(_ view: Ghostty.SurfaceView) {
        let id = view.id
        guard focusObservers[id] == nil else { return }
        focusObservers[id] = view.$focusInstant
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, var session = self.sessions[id], !session.seen else { return }
                    session.seen = true
                    self.sessions[id] = session
                    NotificationCenter.default.post(name: .terminalTabsDidChange, object: nil)
                }
            }
    }

    // MARK: Surfaces

    static func surfaceView(_ id: UUID) -> Ghostty.SurfaceView? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else { continue }
            if let view = controller.surfaceTree.first(where: { $0.id == id }) { return view }
        }
        return nil
    }

    private static func isFocused(_ view: Ghostty.SurfaceView) -> Bool {
        NSApp.isActive && view.window?.isKeyWindow == true && view.focused
    }

    /// The last lines of the visible screen, where Claude Code draws its dialogs.
    private static func bottomLines(_ view: Ghostty.SurfaceView, count: Int = 12) -> String {
        view.cachedVisibleContents.get()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(count)
            .joined(separator: "\n")
    }
}
