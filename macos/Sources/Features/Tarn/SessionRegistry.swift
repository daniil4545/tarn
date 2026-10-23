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
    /// Question options in order.
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
    /// The `agent_id` of the subagent whose request holds `permission`; nil for the main agent.
    var permissionAgent: String?
    /// A permission hook waits for the card's answer to `request`.
    var answerable = false

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

    /// While a hook waits, the session shows the oldest waiting request, whatever other events say.
    mutating func show(waiting waitingRequest: AgentRequest?) {
        answerable = waitingRequest != nil
        guard let waitingRequest else { return }
        state = .permission
        request = waitingRequest
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

/// A permission hook that waits for the card's answer (`docs/spec.md` section 2.3).
struct PendingAnswer<Reply: AnyObject> {
    let request: AgentRequest
    let input: [String: Any]
    let reply: Reply

    /// What still waits after `name`: a finished call drops its own request, the end of a
    /// turn drops all.
    static func remaining(_ waiting: [Self], after name: String, _ event: [String: Any]) -> [Self] {
        let isMain = event["agent_id"] == nil
        switch name {
        case "UserPromptSubmit", "StopFailure", "SessionEnd":
            return isMain ? [] : waiting
        case "Stop":
            let tasks = event["background_tasks"] as? [Any] ?? []
            return isMain && tasks.isEmpty ? [] : waiting
        case "PostToolUse", "PostToolUseFailure":
            let tool = event["tool_name"] as? String
            let input = event["tool_input"] as? [String: Any] ?? [:]
            guard let done = waiting.firstIndex(where: {
                $0.request.tool == tool && NSDictionary(dictionary: $0.input).isEqual(to: input)
            }) else { return waiting }
            var rest = waiting
            rest.remove(at: done)
            return rest
        default:
            return waiting
        }
    }
}

/// The only owner of agent state. Hook events arrive through the control socket; the
/// surface's own title and progress report close the gaps where Claude Code sends no event.
@MainActor
final class SessionRegistry {
    static let shared = SessionRegistry()

    private static let logger = Logger(subsystem: "tarn", category: "registry")

    private(set) var sessions: [UUID: AgentSession] = [:]
    /// Permission hooks that wait for the card, oldest first; the card shows the first.
    private var pending: [UUID: [PendingAnswer<ControlSocket.Reply>]] = [:]
    private var socket: ControlSocket?
    private var timer: Timer?
    private var focusObservers: [UUID: AnyCancellable] = [:]

    /// When a working surface first looked idle by its own signals (Esc gives no event).
    private var idleSince: [UUID: Date] = [:]

    func start() {
        guard socket == nil else { return }
        let socket = ControlSocket { [weak self] line, reply in self?.receive(line, reply: reply) }
        socket.start()
        self.socket = socket

        // Polls only sessions in `working` or `permission`; others cost nothing.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkLiveness() }
        }
    }

    // MARK: Events

    private func receive(_ line: Data, reply: ControlSocket.Reply) {
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

        var waiting = pending[surfaceID] ?? []
        if name == "PermissionRequest", message["reply"] as? Bool == true {
            let request = AgentSession.request(from: event)
            // The card has no buttons for several questions or a multi-select; the dialog answers.
            if request.kind == .question && request.options.isEmpty {
                reply.send(Data())
            } else {
                waiting.append(PendingAnswer(request: request, input: event["tool_input"] as? [String: Any] ?? [:], reply: reply))
            }
        }
        let remaining = PendingAnswer.remaining(waiting, after: name, event)
        // A dropped hook gets no answer and falls back to the agent's own dialog.
        for item in waiting where !remaining.contains(where: { $0.reply === item.reply }) {
            item.reply.send(Data())
        }
        pending[surfaceID] = remaining.isEmpty ? nil : remaining

        var session = sessions[surfaceID] ?? AgentSession(surfaceID: surfaceID)
        let old = session
        session.handle(name, event)
        session.show(waiting: remaining.first?.request)
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
            closePending(id)
            var next = session
            next.answerable = false
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

    /// Answers `request`, the one the card shows, through its waiting hook (`docs/spec.md` 2.3).
    func answer(_ surfaceID: UUID, request: AgentRequest, option: Int) {
        guard var session = sessions[surfaceID],
              let view = Self.surfaceView(surfaceID),
              var waiting = pending[surfaceID],
              let first = waiting.first, first.request == request,
              let line = Self.decision(for: first.request, input: first.input, option: option)
        else { return }

        first.reply.send(line)
        waiting.removeFirst()
        pending[surfaceID] = waiting.isEmpty ? nil : waiting
        if waiting.isEmpty {
            session.state = .working
            session.request = nil
            session.since = Date()
        }
        session.show(waiting: waiting.first?.request)
        update(session, view: view)
    }

    /// The hook output that gives `option` to `request`: allow or deny a tool, or allow a
    /// question with the chosen label as its answer. Nil for an option the request lacks.
    nonisolated static func decision(for request: AgentRequest, input: [String: Any], option: Int) -> Data? {
        let decision: [String: Any]
        switch request.kind {
        case .tool:
            decision = option == 0
                ? ["behavior": "allow"]
                : ["behavior": "deny", "message": "The user denied this in tarn."]
        case .question:
            guard request.options.indices.contains(option) else { return nil }
            var updated = input
            updated["answers"] = [request.detail: request.options[option]]
            decision = ["behavior": "allow", "updatedInput": updated]
        }
        let output = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        guard var data = try? JSONSerialization.data(withJSONObject: output) else { return nil }
        data.append(UInt8(ascii: "\n"))
        return data
    }

    // MARK: Pending answers

    private func closePending(_ id: UUID) {
        pending[id]?.forEach { $0.reply.send(Data()) }
        pending[id] = nil
    }

    // MARK: Store

    private func update(_ session: AgentSession, view: Ghostty.SurfaceView) {
        sessions[session.surfaceID] = session
        observeFocus(view)
        NotificationCenter.default.post(name: .terminalTabsDidChange, object: nil)
    }

    private func remove(_ id: UUID) {
        closePending(id)
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
