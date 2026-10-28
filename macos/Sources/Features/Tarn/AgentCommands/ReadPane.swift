import AppKit
import GhosttyKit

/// `tarn read <pane> [--lines N]`: plain text of the last lines of a pane's screen and scrollback
/// (`docs/specs/agent-cli.md` 4.7). Follows herdr `pane read --lines N`: default 80, no escapes.
enum ReadPane {
    static let defaultLines = 80
    static let badLines = AgentRefusal(text: "bad lines")

    @MainActor
    static func run(_ message: [String: Any], _ scope: AgentScope) -> Result<[String: Any], AgentRefusal> {
        var count = defaultLines
        if let value = message["lines"] {
            guard let number = value as? Int, number > 0 else { return .failure(badLines) }
            count = number
        }
        return scope.pane(message["pane"] as? String).flatMap { row in
            guard let view = SessionRegistry.surfaceView(row.pane) else { return .failure(.noPane(row.pane.uuidString)) }
            return .success(["text": last(count, of: screenText(view))])
        }
    }

    /// A fresh read of the whole screen and scrollback: `cachedScreenContents` may be 500 ms old.
    /// The text comes from the cell grid, so it carries no escape sequences.
    @MainActor
    static func screenText(_ view: Ghostty.SurfaceView) -> String {
        guard let surface = view.surface else { return "" }
        var text = ghostty_text_s()
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false
        )
        guard ghostty_surface_read_text(surface, selection, &text) else { return "" }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }

    /// The last `count` lines, each with its trailing blanks cut; the empty rows below the last
    /// output are not lines. Each line ends with a newline. Only the kept lines are trimmed: the
    /// scrollback can hold thousands of rows.
    static func last(_ count: Int, of text: String) -> String {
        let blank: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\r" }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
        while let line = lines.last, line.allSatisfy(blank) { lines.removeLast() }
        return lines.suffix(count).map { String($0.reversed().drop(while: blank).reversed()) + "\n" }.joined()
    }
}
