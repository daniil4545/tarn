import Foundation

/// Pure path rules of a workspace folder (`docs/specs/workspace-folder.md` D19, S26).
enum WorkspaceFolder {
    /// Absolute, standardized, symlinks resolved; nil for an empty or relative path.
    static func standardized(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized.path
    }

    /// True when `path` is `folder` or lies below it, compared by path components:
    /// `/a/F-old` is not inside `/a/F`. Both sides resolve symlinks, so a logical shell path
    /// under a symlinked folder still matches the stored real path. Only existing paths resolve.
    static func contains(_ folder: String, _ path: String) -> Bool {
        let base = URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardized.pathComponents
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized.pathComponents
        return target.count >= base.count && Array(target.prefix(base.count)) == base
    }

    /// D20: where a new surface starts. The inherited directory stays when it lies inside `folder`;
    /// anything else, nil included, gives `folder`. No folder, or one that is gone from disk (S9),
    /// returns `inherited` unchanged.
    static func startDirectory(inherited: String?, folder: String?, exists: (String) -> Bool) -> String? {
        guard let folder, exists(folder) else { return inherited }
        if let inherited, contains(folder, inherited) { return inherited }
        return folder
    }

    /// The workspace name for a folder: its last path component.
    static func name(of folder: String) -> String {
        URL(fileURLWithPath: folder).lastPathComponent
    }

    /// The folder as shown to the user, with `~` for the home directory.
    static func display(_ folder: String, home: String = NSHomeDirectory()) -> String {
        contains(home, folder) ? "~" + folder.dropFirst(home.count) : folder
    }
}
