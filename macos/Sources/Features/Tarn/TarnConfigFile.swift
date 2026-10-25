import Foundation
import GhosttyKit

/// The file `~/.config/tarn/ghostty.conf`: Ghostty options changed in the tarn settings window.
/// It loads after the user's Ghostty config and its `config-file` includes, so its lines win; the
/// user's own files are never edited (`docs/modules/settings.md`).
///
/// The text is kept as lines. `key = value` lines are entries; comments, blank lines and anything
/// else stay verbatim, so a hand edit survives a save.
struct TarnConfigFile: Equatable {
    enum Error: Swift.Error, Equatable {
        /// The key or value holds a line break (or the key an `=` or edge space).
        case invalidText
    }

    enum Line: Equatable {
        case entry(key: String, value: String)
        case verbatim(String)
    }

    /// What a new file starts with.
    static let header: [Line] = [
        .verbatim("# Written by the tarn settings window. Loaded after your Ghostty config."),
        .verbatim("# Delete a line to give the option back to your Ghostty config."),
        .verbatim("# config-file lines here are ignored."),
        .verbatim(""),
    ]

    private(set) var lines: [Line]

    /// A new file: the header and no options.
    init() {
        lines = Self.header
    }

    /// Parses file text the way Ghostty reads a config line: trims whitespace, skips blank
    /// lines and `#` comments, and strips one pair of surrounding quotes from the value.
    init(parsing text: String) {
        lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else {
                return .verbatim(String(raw))
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return .entry(key: key, value: value)
        }
        // A trailing newline splits into one empty last element.
        if lines.last == .verbatim("") { lines.removeLast() }
    }

    // MARK: - Reading

    /// Every key with its values in file order; a repeatable key such as `font-family` has several.
    var entries: [(key: String, value: String)] {
        lines.compactMap { if case let .entry(key, value) = $0 { (key, value) } else { nil } }
    }

    /// The effective value: the last line of the key, as Ghostty reads a scalar option.
    func value(for key: String) -> String? {
        entries.last { $0.key == key }?.value
    }

    func contains(_ key: String) -> Bool {
        value(for: key) != nil
    }

    // MARK: - Editing

    /// Replaces every line of `key` with one line per value, at the place of the first one;
    /// appends when the key is new. An empty list removes the key.
    mutating func set(_ key: String, to values: [String]) throws {
        guard !key.isEmpty, !Self.hasBreak(key), !key.contains("="), key == key.trimmingCharacters(in: .whitespaces),
              !values.contains(where: Self.hasBreak) else { throw Error.invalidText }
        let new = values.map { Line.entry(key: key, value: $0) }
        if let first = lines.firstIndex(where: { $0.key == key }) {
            lines.remove(at: first)
            lines.removeAll { $0.key == key }
            lines.insert(contentsOf: new, at: min(first, lines.count))
        } else {
            lines.append(contentsOf: new)
        }
    }

    /// Removes every line of `key`; other lines, comments included, stay.
    mutating func remove(_ key: String) {
        lines.removeAll { $0.key == key }
    }

    // MARK: - Text

    var text: String {
        let out = lines.map { line -> String in
            switch line {
            case let .entry(key, value): "\(key) = \(Self.encode(value))"
            case let .verbatim(raw): raw
            }
        }
        return out.isEmpty ? "" : out.joined(separator: "\n") + "\n"
    }

    /// Ghostty strips one pair of quotes and does no escaping, so quote only what would
    /// otherwise change: an empty value, edge spaces, or a value already wrapped in quotes.
    private static func encode(_ value: String) -> String {
        let wrapped = value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\"")
        let needsQuotes = value.isEmpty || value != value.trimmingCharacters(in: .whitespaces) || wrapped
        return needsQuotes ? "\"\(value)\"" : value
    }

    private static func hasBreak(_ text: String) -> Bool {
        text.contains { $0.isNewline }
    }

    // MARK: - Disk

    /// `$XDG_CONFIG_HOME/tarn/ghostty.conf`, else `~/.config/tarn/ghostty.conf`, as Ghostty
    /// finds its own config directory.
    static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            base = URL(fileURLWithPath: xdg)
        } else {
            let home = environment["HOME"] ?? NSHomeDirectory()
            base = URL(fileURLWithPath: home).appendingPathComponent(".config")
        }
        return base.appendingPathComponent("tarn").appendingPathComponent("ghostty.conf")
    }

    /// The file for the app's own configs, or nil when the launch carries `-e`: our lines would
    /// land after the command the CLI sets (`Config.zig:4434`).
    static func activeURL(arguments: [String] = CommandLine.arguments) -> URL? {
        arguments.contains("-e") ? nil : defaultURL()
    }

    /// Reads the file; a missing file is an empty one.
    static func read(from url: URL) throws -> TarnConfigFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return TarnConfigFile() }
        return TarnConfigFile(parsing: try String(contentsOf: url, encoding: .utf8))
    }

    /// Writes through symlinks (a dotfiles link stays a link) and atomically: a failed write
    /// leaves the old file as it was.
    func save(to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target, options: .atomic)
    }

    /// Loads the file into a Ghostty config. Needs an absolute path, and Ghostty logs an error for
    /// a missing file, so check first.
    static func load(into config: ghostty_config_t, from url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        ghostty_config_load_file(config, url.path)
    }
}

private extension TarnConfigFile.Line {
    var key: String? {
        if case let .entry(key, _) = self { key } else { nil }
    }
}
