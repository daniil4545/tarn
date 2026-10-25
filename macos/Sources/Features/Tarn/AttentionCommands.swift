import Foundation
import OSLog

/// One row of `tarn ls`: a live session with the fields of `docs/spec.md` section 5.
struct SessionRow: Equatable {
    let surfaceID: UUID
    let agentSessionID: String
    let cwd: String
    let project: String
    let branch: String
    let state: AgentState
    let since: Date
    let seen: Bool
    let failed: Bool
    let note: String

    init(_ session: AgentSession, cwd: String?) {
        let info = ProjectInfo.resolve(cwd: cwd)
        self.init(session, cwd: cwd, project: info.name, branch: info.branch)
    }

    init(_ session: AgentSession, cwd: String?, project: String, branch: String) {
        surfaceID = session.surfaceID
        agentSessionID = session.agentSessionID
        self.cwd = cwd ?? ""
        self.project = project
        self.branch = branch
        state = session.state
        since = session.since
        seen = session.seen
        failed = session.failed
        note = session.note
    }

    /// `failed` for a waiting session whose last turn failed, else the state name.
    var displayState: String {
        if state == .waiting, failed { return "failed" }
        switch state {
        case .idle: return "idle"
        case .waiting: return "waiting"
        case .working: return "working"
        case .permission: return "permission"
        }
    }
}

/// The socket commands `ls` and `notify` (`docs/spec.md` 2.2, 11) and the reply format shared
/// with `open`: one JSON line with sorted keys and `version`.
enum AttentionCommands {
    private static let logger = Logger(subsystem: "tarn", category: "socket")

    static func reply(_ fields: [String: Any] = [:]) -> Data {
        var fields = fields
        fields["ok"] = fields["error"] == nil
        fields["version"] = 1
        let json = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data()
        return json + Data("\n".utf8)
    }

    static func failure(_ text: String) -> Data { reply(["error": text]) }

    /// Rows as `3  tarn  main  permission  2m`: position, project, branch (`-` outside git),
    /// state and time in the state.
    static func text(_ rows: [SessionRow], now: Date) -> String {
        rows.enumerated().map { index, row in
            "\(index + 1)  \(row.project)  \(row.branch.isEmpty ? "-" : row.branch)  \(row.displayState)  \(age(now.timeIntervalSince(row.since)))\n"
        }.joined()
    }

    static func json(_ rows: [SessionRow]) -> [[String: Any]] {
        let formatter = ISO8601DateFormatter()
        return rows.map { row in
            [
                "surface": row.surfaceID.uuidString,
                "agentSessionID": row.agentSessionID,
                "cwd": row.cwd,
                "project": row.project,
                "branch": row.branch,
                "state": String(describing: row.state),
                "since": formatter.string(from: row.since),
                "seen": row.seen,
                "failed": row.failed,
                "note": row.note,
            ]
        }
    }

    static func age(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    /// True for a line that is not a JSON object (junk, invalid UTF-8) and not a permission hook's.
    static func isMalformed(_ line: Data) -> Bool {
        if (try? JSONSerialization.jsonObject(with: line)) is [String: Any] { return false }
        return line.range(of: Data("\"reply\":true".utf8)) == nil
    }

    /// Answers `ls`, `notify` and any other `cmd` the earlier handlers did not take. A line that
    /// is not a JSON object gets an error reply (`docs/spec.md` 2.2), except a permission hook's
    /// line (`"reply":true`): that hook prints whatever the app answers, so it gets silence.
    /// Returns false for JSON without `cmd`, which are hook events.
    @MainActor
    static func handle(_ line: Data, reply sink: ControlSocket.Reply) -> Bool {
        if isMalformed(line) {
            logger.info("malformed request refused")
            sink.send(failure("malformed request"))
            return true
        }
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return false }
        guard let command = message["cmd"] as? String else { return false }
        sink.send(answer(command: command, message: message))
        return true
    }

    /// The reply line for `command`; logs a refusal.
    @MainActor
    static func answer(command: String, message: [String: Any]) -> Data {
        if let error = perform(command: command, message: message) {
            logger.info("\(command, privacy: .public) refused: \(error, privacy: .public) surface=\(message["surface"] as? String ?? "-", privacy: .public)")
            return failure(error)
        }
        return command == "ls" ? listing(message) : reply()
    }

    /// Checks the request and carries out `notify`; the error text, or nil on success.
    @MainActor
    private static func perform(command: String, message: [String: Any]) -> String? {
        guard message["version"] as? Int == 1 else { return "unsupported version" }
        switch command {
        case "ls":
            return nil
        case "notify":
            guard let id = (message["surface"] as? String).flatMap(UUID.init(uuidString:)) else {
                return "unknown surface"
            }
            return SessionRegistry.shared.notify(id, text: message["text"] as? String ?? "")
        default:
            return "unknown command: \(command)"
        }
    }

    @MainActor
    private static func listing(_ message: [String: Any]) -> Data {
        let rows = SessionRegistry.shared.liveSessions().map { SessionRow($0.session, cwd: $0.view.pwd) }
        return message["json"] as? Bool == true
            ? reply(["sessions": json(rows)])
            : reply(["text": text(rows, now: Date())])
    }
}
