import Foundation

struct TreeRow: Equatable {
    var path: String
    var name: String
    var depth: Int
    var isDirectory: Bool
    var isOpen: Bool
}

/// The files tree of the viewer pane: a root folder, with folders unfolded on demand.
struct FileTree: Equatable {
    static let hidden: Set<String> = [".git", ".DS_Store", "node_modules"]
    static let maxRows = 5000

    var root: String
    private(set) var open: Set<String> = []

    init(root: String) {
        self.root = root
    }

    mutating func toggle(_ path: String) {
        if open.contains(path) { open.remove(path) } else { open.insert(path) }
    }

    /// Unfolds every folder between the root and `path`, so an opened file shows in the tree.
    mutating func reveal(_ path: String) {
        var folder = (path as NSString).deletingLastPathComponent
        while folder.hasPrefix(root), folder != root {
            open.insert(folder)
            folder = (folder as NSString).deletingLastPathComponent
        }
    }

    func rows() -> [TreeRow] {
        var rows: [TreeRow] = []
        list(root, depth: 0, into: &rows)
        return rows
    }

    private func list(_ folder: String, depth: Int, into rows: inout [TreeRow]) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return }
        let entries = names.filter { !Self.hidden.contains($0) }.map { name -> (String, Bool) in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: folder + "/" + name, isDirectory: &isDirectory)
            return (name, isDirectory.boolValue)
        }.sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 : lhs.0.localizedStandardCompare(rhs.0) == .orderedAscending
        }
        for (name, isDirectory) in entries where rows.count < Self.maxRows {
            let path = folder + "/" + name
            let isOpen = isDirectory && open.contains(path)
            rows.append(TreeRow(path: path, name: name, depth: depth, isDirectory: isDirectory, isOpen: isOpen))
            if isOpen { list(path, depth: depth + 1, into: &rows) }
        }
    }
}
