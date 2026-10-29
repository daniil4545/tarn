import Foundation
import Testing
@testable import Ghostty

/// The agent commands: caller, workspace scope and `tarn ls` (`docs/specs/agent-cli.md` 4, 7).
@Suite
struct AgentCommandsTests {
    private let left = UUID()
    private let right = UUID()

    private func pane(in workspace: UUID?, title: String = "zsh", state: String = "") -> PaneRow {
        PaneRow(pane: UUID(), tab: UUID(), workspace: workspace, title: title, cwd: "/work", process: "zsh", branch: "main", state: state)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    private func ls(_ caller: String?, json: Bool = true, in panes: [PaneRow]) throws -> [String: Any] {
        var message: [String: Any] = ["version": 1, "cmd": "ls", "json": json]
        message["surface"] = caller
        return try object(AgentCommands.answer("ls", ListPanes.run, message: message, panes: panes))
    }

    /// spec: agent-cli B3 - two workspaces in one window and one in a second window.
    @Test @MainActor func lsListsOnlyTheCallersWorkspace() throws {
        let other = UUID()
        let mine = [pane(in: left), pane(in: left)]
        let all = [mine[0], pane(in: other), mine[1], pane(in: right), pane(in: nil)]
        let reply = try ls(mine[1].pane.uuidString, in: all)
        let ids = try #require(reply["panes"] as? [[String: Any]]).compactMap { $0["pane"] as? String }
        #expect(ids == mine.map(\.pane.uuidString))
    }

    @Test @MainActor func callerOutsideAPaneOrAWorkspaceIsRefused() throws {
        let quick = PaneRow(pane: UUID(), tab: nil, workspace: nil)
        let cases: [(String?, String)] = [
            (nil, "not in a tarn tab"),
            (UUID().uuidString, "not in a tarn tab"),
            (quick.pane.uuidString, "not in a workspace"),
        ]
        for (caller, error) in cases {
            let reply = try ls(caller, in: [quick, pane(in: left)])
            #expect(reply["ok"] as? Bool == false)
            #expect(reply["error"] as? String == error, "\(caller ?? "nil")")
            #expect(reply["code"] as? Int == 1)
        }
    }

    /// spec: docs/specs/workspace-folder.md S49 - a caller in a tab with no workspace reaches that tab only.
    @Test @MainActor func lsOfAnUngroupedCallerListsItsOwnTab() throws {
        let tab = UUID()
        let mine = [PaneRow(pane: UUID(), tab: tab, workspace: nil), PaneRow(pane: UUID(), tab: tab, workspace: nil)]
        let all = [mine[0], PaneRow(pane: UUID(), tab: UUID(), workspace: nil), mine[1], pane(in: left)]
        let reply = try ls(mine[1].pane.uuidString, in: all)
        let ids = try #require(reply["panes"] as? [[String: Any]]).compactMap { $0["pane"] as? String }
        #expect(ids == mine.map(\.pane.uuidString))
    }

    /// spec: docs/specs/workspace-folder.md S57 - `wait`, `read` and `close` on another ungrouped tab: exit 4.
    @Test @MainActor func anUngroupedCallerCannotReachAnotherTab() throws {
        final class Sink: WaitSink {
            func send(_ line: Data) {}
            func watchPeer(_ handler: @escaping @Sendable () -> Void) {}
        }
        let caller = PaneRow(pane: UUID(), tab: UUID(), workspace: nil)
        let other = PaneRow(pane: UUID(), tab: UUID(), workspace: nil)
        let scope = try AgentScope.resolve(caller: caller.pane.uuidString, in: [caller, other]).get()
        let message: [String: Any] = ["pane": other.pane.uuidString]
        let expected = AgentRefusal.noPane(other.pane.uuidString)
        #expect(throws: expected) { try ReadPane.run(message, scope).get() }
        #expect(throws: expected) { try ClosePane.run(message, scope).get() }
        let waited = WaitPane.start(message, scope: scope, reply: Sink())
        #expect(throws: expected) { try #require(waited).get() }
        #expect(expected.code == 4)
    }

    /// spec: agent-cli B5 - a missing or foreign id is exit 4, never the selected pane.
    @Test func paneOutsideTheScopeIsNoMatch() throws {
        let mine = pane(in: left)
        let foreign = pane(in: right)
        let scope = try AgentScope.resolve(caller: mine.pane.uuidString, in: [mine, foreign]).get()
        #expect(try scope.pane(mine.pane.uuidString.lowercased()).get() == mine)
        for id in [foreign.pane.uuidString, UUID().uuidString, "x", nil] {
            #expect(throws: AgentRefusal.noPane(id ?? "")) { try scope.pane(id).get() }
        }
        #expect(AgentRefusal.noPane("x").code == 4)
    }

    @Test @MainActor func wrongVersionIsRefused() throws {
        let mine = pane(in: left)
        let reply = try object(AgentCommands.answer("ls", ListPanes.run, message: ["version": 2, "surface": mine.pane.uuidString], panes: [mine]))
        #expect(reply["error"] as? String == "unsupported version")
    }

    @Test @MainActor func jsonCarriesThePaneFields() throws {
        let mine = pane(in: left, state: "waiting")
        let entry = try #require((try ls(mine.pane.uuidString, in: [mine])["panes"] as? [[String: Any]])?.first)
        #expect(Set(entry.keys) == ["pane", "tab", "workspace", "group", "folder", "title", "cwd", "process", "branch", "state"])
        #expect(entry["workspace"] as? String == left.uuidString)
        #expect(entry["state"] as? String == "waiting")
    }

    /// The form of WezTerm `cli list`: a header, columns padded to the widest cell, `-` for empty.
    @Test func textIsATableWithAHeader() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let tab = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let row = PaneRow(pane: id, tab: tab, workspace: left, title: "a\nb", cwd: "/w", process: "claude", branch: "", state: "permission")
        let lines = ListPanes.text([row]).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].split(separator: " ").map(String.init) == ["PANE", "TAB", "GROUP", "TITLE", "CWD", "PROCESS", "BRANCH", "STATE"])
        #expect(lines[1].split(separator: " ").map(String.init) == [id.uuidString, tab.uuidString, "-", "a", "b", "/w", "claude", "-", "permission"])
        #expect(lines[0].range(of: "TAB")?.lowerBound.utf16Offset(in: lines[0]) == id.uuidString.count + 2)
        #expect(ListPanes.text([]) == ListPanes.columns.joined(separator: "  ") + "\n")
    }

    // spec: docs/specs/workspace-folder.md S48
    @Test @MainActor func lsShowsGroupAndFolder() throws {
        let rows = [
            PaneRow(pane: UUID(), tab: UUID(), workspace: left, group: "tarn", folder: "/work/tarn"),
            PaneRow(pane: UUID(), tab: UUID(), workspace: right, group: "plain"),
            PaneRow(pane: UUID(), tab: UUID(), workspace: nil),
        ]
        for row in rows {
            let text = try #require(try ls(row.pane.uuidString, json: false, in: rows)["text"] as? String)
            let lines = text.split(separator: "\n")
            #expect(lines.count == 2)
            #expect(lines[1].split(separator: " ")[2] == Substring(row.group ?? "-"))
            let entry = try #require((try ls(row.pane.uuidString, in: rows)["panes"] as? [[String: Any]])?.first)
            if let group = row.group {
                #expect(entry["group"] as? String == group)
            } else {
                #expect(entry["group"] is NSNull)
            }
            if let folder = row.folder {
                #expect(entry["folder"] as? String == folder)
            } else {
                #expect(entry["folder"] is NSNull)
            }
        }
    }

    /// Cells of more than one UTF-16 unit or scalar are neither cut nor shifted.
    @Test func textKeepsEmojiAndDecomposedCells() {
        let nfd = "/w/caf\u{65}\u{301}"
        let rows = [
            PaneRow(pane: UUID(), tab: nil, workspace: left, title: "🚀 dev", cwd: nfd, process: "zsh"),
            PaneRow(pane: UUID(), tab: nil, workspace: left, title: "x\u{1B}[31m", cwd: "/w", process: "zsh"),
        ]
        let lines = ListPanes.text(rows).split(separator: "\n").map(String.init)
        #expect(lines[1].contains("🚀 dev  ") && lines[1].contains(nfd + "  "))
        #expect(!lines[2].contains("\u{1B}"))
        let process = lines.map { $0.distance(from: $0.startIndex, to: $0.range(of: $0 == lines[0] ? "PROCESS" : "zsh")!.lowerBound) }
        #expect(Set(process).count == 1, "\(lines)")
    }

    @Test func listStateShowsAFailedWait() {
        var session = AgentSession(surfaceID: UUID())
        session.state = .waiting
        #expect(session.listState == "waiting")
        session.failed = true
        #expect(session.listState == "failed")
    }
}
