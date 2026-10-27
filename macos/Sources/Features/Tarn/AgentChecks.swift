import Foundation

/// The three checks of the Claude Code line in Settings > Modules (`docs/modules/settings.md`).
/// Local only: no network, nothing written.
struct AgentChecks: Equatable {
    /// The version of `claude --version`; nil when Claude Code was not found.
    var version: String?
    var pluginInstalled: Bool
    var eventsSeen: Bool

    static let pluginKey = "tarn@tarn"
    static let pluginHint = "install the tarn plugin: claude plugin install tarn@tarn (docs/install.md)"
    static let eventsHint = "no events yet, start a Claude Code session in tarn"
    static let notFoundHint = "Claude Code not found"

    /// Where the Claude Code binary usually lives, in the order of the check.
    static func candidates(home: String = NSHomeDirectory()) -> [String] {
        ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
    }

    /// The version in the output of `claude --version`: the line `2.1.311 (Claude Code)`.
    static func version(from output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.range(of: #"^\d+\.\d+\.\d+ \(Claude Code\)$"#, options: .regularExpression) != nil {
                return String(text.prefix { !$0.isWhitespace })
            }
        }
        return nil
    }

    /// True when `installed_plugins.json` lists `tarn@tarn` under `plugins`.
    static func hasPlugin(in data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = root["plugins"] as? [String: Any]
        else { return false }
        return plugins[pluginKey] != nil
    }

    /// Runs the checks; blocks for up to a few seconds, so call it off the main thread.
    static func run(eventsSeen: Bool, home: String = NSHomeDirectory()) -> AgentChecks {
        let plugin = (try? Data(contentsOf: URL(fileURLWithPath: "\(home)/.claude/plugins/installed_plugins.json")))
            .map(hasPlugin) ?? false
        return AgentChecks(version: findVersion(home: home), pluginInstalled: plugin, eventsSeen: eventsSeen)
    }

    private static func findVersion(home: String) -> String? {
        for path in candidates(home: home) where FileManager.default.isExecutableFile(atPath: path) {
            if let output = capture(path, ["--version"]), let version = version(from: output) { return version }
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return capture(shell, ["-l", "-i", "-c", "claude --version"]).flatMap(version(from:))
    }

    /// Standard output of a command, or nil when it fails or runs over five seconds.
    private static func capture(_ path: String, _ arguments: [String], timeout: TimeInterval = 5) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
