import Foundation

/// The project name and git branch of a working directory, for notification titles and
/// `tarn ls`. The sidebar keeps its own cached copy of the root walk in `Sidebar.swift`.
struct ProjectInfo: Equatable {
    /// The git root folder name, else the working folder name, else `tarn`.
    let name: String
    /// The branch from `HEAD`; empty outside git and on a detached HEAD.
    let branch: String

    static func resolve(cwd: String?) -> ProjectInfo {
        guard let cwd, !cwd.isEmpty else { return ProjectInfo(name: "tarn", branch: "") }
        let fm = FileManager.default
        var url = URL(fileURLWithPath: cwd)
        while url.path != "/" {
            let dot = url.appendingPathComponent(".git").path
            if fm.fileExists(atPath: dot) {
                return ProjectInfo(name: url.lastPathComponent, branch: branch(dot: dot, root: url.path))
            }
            url.deleteLastPathComponent()
        }
        let folder = (cwd as NSString).lastPathComponent
        return ProjectInfo(name: folder.isEmpty ? "tarn" : folder, branch: "")
    }

    /// `dot` is the `.git` folder, or the `.git` file of a worktree (`gitdir: <path>`).
    private static func branch(dot: String, root: String) -> String {
        var gitDir = dot
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dot, isDirectory: &isDir), !isDir.boolValue {
            guard let text = try? String(contentsOfFile: dot, encoding: .utf8),
                  let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
            else { return "" }
            let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDir = path.hasPrefix("/") ? path : root + "/" + path
        }
        guard let head = try? String(contentsOfFile: gitDir + "/HEAD", encoding: .utf8) else { return "" }
        let prefix = "ref: refs/heads/"
        guard head.hasPrefix(prefix) else { return "" }
        return head.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
