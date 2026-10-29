import Foundation
import OSLog

extension AgentSession {
    /// The state `tarn ls` shows: `failed` for a waiting session whose last turn failed, else the state name.
    var listState: String {
        state == .waiting && failed ? "failed" : String(describing: state)
    }
}

/// The socket command `notify` (`docs/spec.md` 2.2, 11) and the reply format shared
/// with `open` and `AgentCommands`: one JSON line with sorted keys and `version`.
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

    /// True for a line that is not a JSON object (junk, invalid UTF-8) and not a permission hook's.
    static func isMalformed(_ line: Data) -> Bool {
        if (try? JSONSerialization.jsonObject(with: line)) is [String: Any] { return false }
        return line.range(of: Data("\"reply\":true".utf8)) == nil
    }

    /// A line that is not a JSON object gets an error reply (`docs/spec.md` 2.2), except a permission
    /// hook's line (`"reply":true`): that hook prints whatever the app answers, so it gets silence.
    static func refuse(_ line: Data, reply sink: ControlSocket.Reply) {
        guard isMalformed(line) else {
            logger.info("dropped a malformed hook line")
            return
        }
        logger.info("malformed request refused")
        sink.send(failure("malformed request"))
    }

    /// Answers `notify` and any other `cmd` the earlier handlers did not take.
    /// Returns false for JSON without `cmd`, which are hook events.
    @MainActor
    static func handle(_ message: [String: Any], reply sink: ControlSocket.Reply) -> Bool {
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
        return reply()
    }

    /// Checks the request and carries out `notify`; the error text, or nil on success.
    @MainActor
    private static func perform(command: String, message: [String: Any]) -> String? {
        guard message["version"] as? Int == 1 else { return "unsupported version" }
        switch command {
        case "notify":
            guard let id = (message["surface"] as? String).flatMap(UUID.init(uuidString:)) else {
                return "unknown surface"
            }
            return SessionRegistry.shared.notify(id, text: message["text"] as? String ?? "")
        default:
            return "unknown command: \(command)"
        }
    }
}
