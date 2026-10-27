import Foundation

/// `tarn ls`: the terminal panes of the caller's workspace (`docs/specs/agent-cli.md` 4.1), in the
/// form of WezTerm `cli list` (`wezterm/src/cli/list.rs`): a header row, columns padded to the widest cell.
enum ListPanes {
    static let columns = ["PANE", "TAB", "TITLE", "CWD", "PROCESS", "BRANCH", "HOST", "STATE"]

    @MainActor
    static func run(_ message: [String: Any], _ scope: AgentScope) -> Result<[String: Any], AgentRefusal> {
        message["json"] as? Bool == true
            ? .success(["panes": scope.panes.map(json)])
            : .success(["text": text(scope.panes)])
    }

    /// The table; an empty cell shows as `-`, a title keeps to one line.
    static func text(_ rows: [PaneRow]) -> String {
        let table: [[String]] = [columns] + rows.map(cells)
        let widths: [Int] = columns.indices.map { column in table.map { $0[column].count }.max() ?? 0 }
        return table.map { line(of: $0, widths: widths) }.joined()
    }

    private static func cells(_ row: PaneRow) -> [String] {
        let values: [String] = [
            row.pane.uuidString, row.tab?.uuidString ?? "", oneLine(row.title), row.cwd,
            row.process, row.branch, row.host, row.state,
        ]
        return values.map { $0.isEmpty ? "-" : $0 }
    }

    /// Cells padded to `widths`, two spaces apart; the last one is not padded.
    private static func line(of cells: [String], widths: [Int]) -> String {
        var parts: [String] = []
        for (column, cell) in cells.enumerated() {
            let last = column == cells.count - 1
            parts.append(last ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0))
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
            "host": row.host,
            "state": row.state,
        ]
    }

    private static func oneLine(_ text: String) -> String {
        String(text.map { $0.isNewline || $0 == "\t" ? " " : $0 })
    }
}
