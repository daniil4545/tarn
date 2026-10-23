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
    /// `detail` is a file path, which a dialog shows relative, so only its name is matched.
    var detailIsPath = false

    /// The part of `detail` a dialog shows as is: a file name, or the start of a command or
    /// question, since long ones wrap. Too short to tell dialogs apart gives "".
    var screenMark: String {
        let firstLine = detail.split(separator: "\n").first.map(String.init) ?? ""
        let mark = detailIsPath ? (firstLine as NSString).lastPathComponent : String(firstLine.prefix(30))
        return mark.count < 4 ? "" : mark
    }
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
    /// The `agent_id` of the subagent whose request holds `permission`; nil for the main agent.
    var permissionAgent: String?

    /// The turn ended and the user has not looked at it yet.
    var isUnseenDone: Bool { state == .waiting && !seen }
}

extension AgentSession {
    /// The transition table of `docs/spec.md` section 8.
    mutating func handle(_ name: String, _ event: [String: Any]) {
        let agentID = event["agent_id"] as? String
        let isSubagent = agentID != nil

        switch name {
        case "UserPromptSubmit" where !isSubagent:
            state = .working
            failed = false
            request = nil
            sawPermissionRequest = false
            permissionAgent = nil

        case "PermissionRequest":
            state = .permission
            request = Self.request(from: event)
            sawPermissionRequest = true
            permissionAgent = agentID

        case "PostToolUse", "PostToolUseFailure":
            // Only the agent that asked clears `permission`: a parallel subagent's tool
            // finishing says nothing about the dialog on screen.
            if (state == .permission && agentID == permissionAgent) || (!isSubagent && state != .working && state != .permission) {
                state = .working
                request = nil
            }

        case "Notification" where !isSubagent:
            switch event["notification_type"] as? String {
            case "permission_prompt" where state == .working && !sawPermissionRequest:
                state = .permission
                permissionAgent = nil
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

        if input["command"] == nil, let path = input["file_path"] as? String {
            return AgentRequest(kind: .tool, tool: tool, detail: path, options: [], detailIsPath: true)
        }
        let detail = input["command"] as? String
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

    /// Claude Code sends no event on Esc; its title, progress report and "Interrupted" on
    /// screen show it instead (`docs/spec.md` section 8).
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

        guard let key = Self.key(answering: request, option: option, screen: Self.bottomLines(view, count: 30)) else {
            Self.logger.info("dialog not on screen, focusing the surface instead")
            focus(surfaceID)
            return
        }
        model.sendKeyEvent(key)
    }

    /// The key that gives `option` to the dialog of `request`, or nil when the screen does
    /// not show that dialog: another tool's request, a subagent's, or one already answered.
    nonisolated static func key(answering request: AgentRequest, option: Int, screen: String) -> Ghostty.Input.KeyEvent? {
        // Menu lines without the selection cursor; a line must match a whole option, since
        // "1. Yes, and always allow" also starts with "1. Yes".
        let lines = screen.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces).trimmingPrefix("❯").trimmingCharacters(in: .whitespaces)
        }
        // The card's text must be in the dialog itself, the lines just above its first option,
        // not in the transcript above it.
        func dialogShowsCard(firstOption: String) -> Bool {
            let mark = request.screenMark
            guard !mark.isEmpty, let row = lines.lastIndex(of: firstOption) else { return false }
            return lines[max(0, row - 12)..<row].contains { $0.contains(mark) }
        }

        switch request.kind {
        case .tool:
            guard dialogShowsCard(firstOption: "1. Yes") else { return nil }
            // Option 0 approves once; option 1 rejects like Esc.
            return option == 0 ? .init(key: .digit1, text: "1") : .init(key: .escape)
        case .question:
            guard option < request.options.count, option < 9,
                  let first = request.options.first, dialogShowsCard(firstOption: "1. \(first)"),
                  lines.contains("\(option + 1). \(request.options[option])") else { return nil }
            let digits: [Ghostty.Input.Key] = [.digit1, .digit2, .digit3, .digit4, .digit5,
                                                .digit6, .digit7, .digit8, .digit9]
            return .init(key: digits[option], text: "\(option + 1)")
        }
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
        // A closed tab's record stays until a check finds its surface gone; drop it here.
        let alive = Set(sessions.keys.filter { Self.surfaceView($0) != nil })
        for id in sessions.keys where !alive.contains(id) {
            remove(id)
        }
        if let next = Self.nextWaiting(Array(sessions.values), alive: alive) { focus(next) }
    }

    /// The session the jump goes to; sessions of closed surfaces never count.
    nonisolated static func nextWaiting(_ sessions: [AgentSession], alive: Set<UUID>) -> UUID? {
        func rank(_ s: AgentSession) -> Int? {
            if s.state == .waiting && s.failed && !s.seen { return 0 }
            if s.state == .permission { return 1 }
            if s.isUnseenDone { return 2 }
            return nil
        }
        return sessions
            .filter { alive.contains($0.surfaceID) }
            .compactMap { s in rank(s).map { (s, $0) } }
            .min { ($0.1, $0.0.since) < ($1.1, $1.0.since) }?
            .0.surfaceID
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
