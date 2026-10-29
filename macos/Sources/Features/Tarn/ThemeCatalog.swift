import Foundation

/// The themes Ghostty can load, and the base list the settings window shows on top
/// (`docs/modules/settings.md`). Ghostty looks a theme up by name in the user's `ghostty/themes`
/// folder, then in the app's own (`src/config/theme.zig:20`); the picker lists the same two.
struct ThemeCatalog {
    /// Theme file names of the base list, one theme each; names of files in Ghostty's theme folder.
    static let baseNames = [
        "Catppuccin Latte", "Catppuccin Mocha",
        "Atom One Light", "Atom One Dark",
        "Gruvbox Light", "Gruvbox Dark",
        "Dracula",
    ]

    /// Folders in lookup order: the user's first.
    let folders: [URL]

    init(folders: [URL] = ThemeCatalog.defaultFolders()) {
        self.folders = folders
    }

    static let shared = ThemeCatalog()

    static func defaultFolders(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        resources: URL? = Bundle.main.resourceURL
    ) -> [URL] {
        let config = environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return [
            config.appendingPathComponent("ghostty/themes"),
            resources?.appendingPathComponent("ghostty/themes"),
        ].compactMap { $0 }
    }

    /// Every theme name, sorted. A name in both folders shows once.
    var names: [String] {
        let all = folders.flatMap { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) ?? [] }
        return Set(all.filter { !$0.hasPrefix(".") })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The base themes that are installed, in list order.
    func base(among names: [String]) -> [String] {
        Self.baseNames.filter(names.contains)
    }

    /// The themes below the base list.
    func rest(among names: [String]) -> [String] {
        let base = Set(Self.baseNames)
        return names.filter { !base.contains($0) }
    }

    /// The names that contain the query, ignoring case and edge spaces; all of them for an empty query.
    static func matching(_ names: [String], query: String) -> [String] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    /// The colors of a theme, read from its file; `nil` when no folder holds it or it names no color.
    func palette(of name: String) -> ThemePalette? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        for folder in folders {
            let url = folder.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8) { return ThemePalette(themeFile: text) }
        }
        return nil
    }
}
