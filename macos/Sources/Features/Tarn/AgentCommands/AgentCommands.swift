import AppKit
import OSLog

/// A terminal pane as the agent commands see it (`docs/specs/agent-cli.md` 3, 4).
struct PaneRow: Equatable {
    let pane: UUID
    let tab: UUID?
    /// Nil for a window outside the workspaces, such as the quick terminal.
    let workspace: UUID?
    var title = ""
    var cwd = ""
    var process = ""
    var branch = ""
    var host = ""
    /// The agent state of `docs/spec.md` 8, or empty for a pane without a session.
    var state = ""
}

/// Why a command was refused: the text the CLI prints after `tarn: ` and its exit code.
struct AgentRefusal: Error, Equatable {
    let text: String
    var code = 1

    static let notInTab = AgentRefusal(text: "not in a tarn tab")
    static let notInWorkspace = AgentRefusal(text: "not in a workspace")

    /// Otty `pane wait`: a selector that matches nothing fails with exit 4, never a fallback.
    static func noPane(_ id: String) -> AgentRefusal { AgentRefusal(text: "no pane matched: \(id)", code: 4) }
}

/// The caller of a command and the panes it may reach: the panes of its own workspace (B3).
struct AgentScope: Equatable {
    let caller: PaneRow
    let panes: [PaneRow]

    static func resolve(caller id: String?, in all: [PaneRow]) -> Result<AgentScope, AgentRefusal> {
        guard let uuid = id.flatMap(UUID.init(uuidString:)), let caller = all.first(where: { $0.pane == uuid }) else {
            return .failure(.notInTab)
        }
        guard let workspace = caller.workspace else { return .failure(.notInWorkspace) }
        return .success(AgentScope(caller: caller, panes: all.filter { $0.workspace == workspace }))
    }

    /// The pane `id` names; a missing or foreign id is refused, never replaced by another pane (B5).
    func pane(_ id: String?) -> Result<PaneRow, AgentRefusal> {
        guard let uuid = id.flatMap(UUID.init(uuidString:)), let row = panes.first(where: { $0.pane == uuid }) else {
            return .failure(.noPane(id ?? ""))
        }
        return .success(row)
    }
}

/// The socket commands an agent calls on panes (`docs/specs/agent-cli.md`). One handler file per
/// command and one row in `handlers`, as kitty keeps one file per remote command (`kitty/rc/`).
enum AgentCommands {
    typealias Handler = @MainActor (_ message: [String: Any], _ scope: AgentScope) -> Result<[String: Any], AgentRefusal>

    private static let logger = Logger(subsystem: "tarn", category: "socket")

    @MainActor
    static let handlers: [String: Handler] = [
        "ls": ListPanes.run,
        "new": NewPane.run,
    ]

    /// Answers a command of `handlers`; false for any other line.
    @MainActor
    static func handle(_ message: [String: Any], reply sink: ControlSocket.Reply) -> Bool {
        guard let command = message["cmd"] as? String else { return false }
        if command == "wait" {
            waitCommand(message, reply: sink)
            return true
        }
        guard let handler = handlers[command] else { return false }
        sink.send(answer(command, handler, message: message, panes: livePanes()))
        return true
    }

    /// `wait` holds its reply until the pane reports an end, so it is not a `Handler`.
    @MainActor
    private static func waitCommand(_ message: [String: Any], reply sink: ControlSocket.Reply) {
        let result: Result<[String: Any], AgentRefusal>?
        if message["version"] as? Int != 1 {
            result = .failure(AgentRefusal(text: "unsupported version"))
        } else {
            switch AgentScope.resolve(caller: message["surface"] as? String, in: livePanes()) {
            case .success(let scope): result = WaitPane.start(message, scope: scope, reply: sink)
            case .failure(let refusal): result = .failure(refusal)
            }
        }
        if let result { sink.send(encode("wait", result, surface: message["surface"] as? String)) }
    }

    /// The reply line of `handler` for `message`, with the panes of every window given; logs a refusal.
    @MainActor
    static func answer(_ command: String, _ handler: Handler, message: [String: Any], panes: [PaneRow]) -> Data {
        let result: Result<[String: Any], AgentRefusal>
        if message["version"] as? Int != 1 {
            result = .failure(AgentRefusal(text: "unsupported version"))
        } else {
            result = AgentScope.resolve(caller: message["surface"] as? String, in: panes).flatMap { handler(message, $0) }
        }
        return encode(command, result, surface: message["surface"] as? String)
    }

    /// The reply line of a result; logs a refusal.
    static func encode(_ command: String, _ result: Result<[String: Any], AgentRefusal>, surface: String?) -> Data {
        switch result {
        case .success(let fields):
            return AttentionCommands.reply(fields)
        case .failure(let refusal):
            logger.info("\(command, privacy: .public) refused: \(refusal.text, privacy: .public) surface=\(surface ?? "-", privacy: .public)")
            return AttentionCommands.reply(["error": refusal.text, "code": refusal.code])
        }
    }

    /// Every terminal pane in screen order, hidden splits of a zoomed tab included.
    @MainActor
    static func livePanes() -> [PaneRow] {
        SessionRegistry.orderedWindows().flatMap { window -> [PaneRow] in
            guard let controller = window.windowController as? BaseTerminalController else { return [] }
            let tab = WorkspaceRegistry.shared.tabKey(of: window)
            let workspace = WorkspaceRegistry.shared.workspace(of: window)?.id
            return controller.surfaceTree.map { view in
                let pid = view.surfaceModel?.foregroundPID.map { AgentProcess.foreground(group: pid_t($0)) }
                let cwd = view.workingDirectory ?? ""
                return PaneRow(
                    pane: view.id,
                    tab: tab,
                    workspace: workspace,
                    title: view.title,
                    cwd: cwd,
                    process: pid.flatMap(AgentProcess.comm) ?? "",
                    branch: ProjectInfo.resolve(cwd: cwd).branch,
                    state: SessionRegistry.shared.sessions[view.id]?.listState ?? ""
                )
            }
        }
    }
}
