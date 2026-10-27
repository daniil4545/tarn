import Foundation

/// `tarn run [--right] [--cwd D] -- <cmd...>`: a split like `tarn new` whose login shell gets the command
/// typed, not submitted; the user reads it and presses Enter (`docs/specs/agent-cli.md` 4.5, U1).
/// Source: herdr `send-text` "non-submitting", Otty `send-text` "Nothing is appended automatically".
enum RunPane {
    static let controlCharacter = AgentRefusal(text: "command has a control character")

    @MainActor
    static func run(_ message: [String: Any], _ scope: AgentScope) -> Result<[String: Any], AgentRefusal> {
        NewPane.open(message, scope, kind: .run)
    }
}
