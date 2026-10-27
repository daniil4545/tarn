import Foundation

/// `tarn run [--right] [--cwd D] -- <cmd...>`: a split like `tarn new` whose login shell gets the command
/// typed, not submitted; the user reads it and presses Enter (`docs/specs/agent-cli.md` 4.5, U1).
/// Source: herdr `send-text` "non-submitting", Otty `send-text` "Nothing is appended automatically".
enum RunPane {
    static let controlCharacter = AgentRefusal(text: "command has a control character")

    @MainActor
    static func run(_ message: [String: Any], _ scope: AgentScope) -> Result<[String: Any], AgentRefusal> {
        if let argv = message["argv"] as? [String], argv.contains(where: hasKey) {
            // A newline keeps the refusal of `new`; any other control character is a key press too.
            return .failure(ShellQuote.join(argv) == nil ? NewPane.notOneLine : controlCharacter)
        }
        return NewPane.open(message, scope, kind: .run)
    }

    /// Typed input reaches the line editor as keys: Ctrl+O submits in zsh and bash, Tab completes,
    /// Esc starts a binding. Only printable text may be typed (B2).
    static func hasKey(_ argument: String) -> Bool {
        argument.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
