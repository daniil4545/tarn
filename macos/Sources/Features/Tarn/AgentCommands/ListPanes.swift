import Foundation

/// `tarn ls`: the terminal panes of the caller's workspace (`docs/specs/agent-cli.md` 4.1), in the
/// form of WezTerm `cli list` (`wezterm/src/cli/list.rs`): a header row, columns padded to the widest cell.
enum ListPanes {
    static let columns = ["PANE", "TAB", "TITLE", "CWD", "PROCESS", "BRANCH", "STATE"]

    @MainActor
    static func run(_ message: [String: Any], _ scope: AgentScope) -> Result<[String: Any], AgentRefusal> {
        message["json"] as? Bool == true
            ? .success(["panes": scope.panes.map(json)])
            : .success(["text": text(scope.panes)])
    }

    /// The table; an empty cell shows as `-`, a title keeps to one line.
    static func text(_ rows: [PaneRow]) -> String {
        table([columns] + rows.map(cells))
    }

    /// Rows (the header first) padded to the widest cell of each column, two spaces apart; the last column is not padded.
    static func table(_ rows: [[String]]) -> String {
        let widths: [Int] = rows[0].indices.map { column in rows.map { $0[column].count }.max() ?? 0 }
        return rows.map { line(of: $0, widths: widths) }.joined()
    }

    private static func cells(_ row: PaneRow) -> [String] {
        let values: [String] = [
            row.pane.uuidString, row.tab?.uuidString ?? "", oneLine(row.title), row.cwd,
            row.process, row.branch, row.state,
        ]
        return values.map { $0.isEmpty ? "-" : $0 }
    }

    /// Cells padded to `widths`, two spaces apart; the last one is not padded.
    private static func line(of cells: [String], widths: [Int]) -> String {
        var parts: [String] = []
        for (column, cell) in cells.enumerated() {
            let last = column == cells.count - 1
            // Padded by characters: `padding(toLength:)` counts UTF-16 units and cuts an emoji or an NFD path.
            parts.append(last ? cell : cell + String(repeating: " ", count: widths[column] - cell.count))
        }
        return parts.joined(separator: "  ") + "\n"
    }

    static func json(_ row: PaneRow) -> [String: Any] {
        [
            "pane": row.pane.uuidString,
            "tab": row.tab?.uuidString ?? "",
            "workspace": row.workspace?.uuidString ?? "",
            "title": row.title,
            "cwd": row.cwd,
            "process": row.process,
            "branch": row.branch,
            "state": row.state,
        ]
    }

    /// Control characters (newline, tab, ESC) become spaces, so a title cannot break or recolor the table.
    private static func oneLine(_ text: String) -> String {
        String(text.map { $0.unicodeScalars.contains { $0.properties.generalCategory == .control } ? " " : $0 })
    }
}
