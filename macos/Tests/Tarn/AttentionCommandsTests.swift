import Foundation
import Testing
@testable import Ghostty

/// The socket commands `ls` and `notify`, their reply format and the helpers behind them.
@Suite
struct AttentionCommandsTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func row(
        _ state: AgentState, project: String = "tarn", branch: String = "main", failed: Bool = false,
        age: TimeInterval = 120, note: String = ""
    ) -> SessionRow {
        var session = AgentSession(surfaceID: UUID())
        session.state = state
        session.failed = failed
        session.since = now.addingTimeInterval(-age)
        session.note = note
        return SessionRow(session, cwd: "/work/\(project)", project: project, branch: branch)
    }

    private func line(_ data: Data) -> String { String(bytes: data, encoding: .utf8) ?? "" }

    @Test func rowsFollowSpecSample() {
        let rows = [row(.permission), row(.waiting, project: "api", branch: "", failed: true, age: 45)]
        #expect(AttentionCommands.text(rows, now: now) == "1  tarn  main  permission  2m\n2  api  -  failed  45s\n")
        #expect(AttentionCommands.text([], now: now).isEmpty)
    }

    @Test func agesUseTheLargestUnit() {
        #expect(AttentionCommands.age(0) == "0s")
        #expect(AttentionCommands.age(59) == "59s")
        #expect(AttentionCommands.age(60) == "1m")
        #expect(AttentionCommands.age(3 * 3600 + 5) == "3h")
        #expect(AttentionCommands.age(2 * 86400) == "2d")
        #expect(AttentionCommands.age(-5) == "0s")
    }

    @Test func jsonCarriesTheSessionFields() throws {
        let entry = try #require(AttentionCommands.json([row(.waiting, failed: true, note: "x")]).first)
        for key in ["surface", "agentSessionID", "cwd", "project", "branch", "state", "since", "seen", "failed", "note"] {
            #expect(entry[key] != nil, "missing \(key)")
        }
        #expect(entry["state"] as? String == "waiting")
        #expect(entry["failed"] as? Bool == true)
        #expect(entry["note"] as? String == "x")
    }

    @Test func repliesHaveSortedKeysAndVersion() {
        #expect(line(AttentionCommands.reply()) == "{\"ok\":true,\"version\":1}\n")
        #expect(line(AttentionCommands.failure("no such file")) == "{\"error\":\"no such file\",\"ok\":false,\"version\":1}\n")
        #expect(line(AttentionCommands.reply(["text": "a\nb"])).hasPrefix("{\"ok\":true,\"text\":\"a\\nb\""))
    }

    @Test @MainActor func refusalsAreErrorRepliesWithoutAPrefix() {
        let cases: [([String: Any], String)] = [
            (["version": 2, "cmd": "ls"], "unsupported version"),
            (["version": 1, "cmd": "bogus"], "unknown command: bogus"),
            (["version": 1, "cmd": "notify", "text": "x"], "unknown surface"),
            (["version": 1, "cmd": "notify", "surface": UUID().uuidString, "text": "x"], "unknown surface"),
        ]
        for (message, error) in cases {
            let answer = AttentionCommands.answer(command: message["cmd"] as? String ?? "", message: message)
            #expect(line(answer) == "{\"error\":\"\(error)\",\"ok\":false,\"version\":1}\n", "\(message)")
        }
    }

    @Test @MainActor func lsOfNothingIsAnEmptyList() {
        let text = AttentionCommands.answer(command: "ls", message: ["version": 1, "cmd": "ls"])
        #expect(line(text) == "{\"ok\":true,\"text\":\"\",\"version\":1}\n")
        let json = AttentionCommands.answer(command: "ls", message: ["version": 1, "cmd": "ls", "json": true])
        #expect(line(json) == "{\"ok\":true,\"sessions\":[],\"version\":1}\n")
    }
}

@Suite
struct ProjectInfoTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func namesTheGitRootAndReadsTheBranch() throws {
        let root = try folder().appendingPathComponent("proj")
        let inner = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/feat/x\n".write(to: root.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(ProjectInfo.resolve(cwd: inner.path) == ProjectInfo(name: "proj", branch: "feat/x"))
    }

    @Test func detachedHeadHasNoBranch() throws {
        let root = try folder()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "0123456789abcdef\n".write(to: root.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(ProjectInfo.resolve(cwd: root.path).branch.isEmpty)
    }

    @Test func worktreeFileLeadsToItsGitDir() throws {
        let base = try folder()
        let tree = base.appendingPathComponent("wt")
        let gitDir = base.appendingPathComponent("main.git/worktrees/wt")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "gitdir: \(gitDir.path)\n".write(to: tree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/s7\n".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        #expect(ProjectInfo.resolve(cwd: tree.path) == ProjectInfo(name: "wt", branch: "s7"))
    }

    @Test func outsideGitUsesTheFolderName() throws {
        let plain = try folder().appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        #expect(ProjectInfo.resolve(cwd: plain.path) == ProjectInfo(name: "notes", branch: ""))
        #expect(ProjectInfo.resolve(cwd: nil) == ProjectInfo(name: "tarn", branch: ""))
    }
}

@Suite
struct ControlSocketOwnershipTests {
    private func path() -> String { "/tmp/ts-\(UUID().uuidString.prefix(8)).sock" }

    @Test func secondInstanceLeavesALiveSocketAlone() {
        let path = path()
        defer { unlink(path) }
        let first = ControlSocket { _, _ in }
        first.start(path: path)
        #expect(first.isBound)
        #expect(ControlSocket.hasListener(path))

        let second = ControlSocket { _, _ in }
        second.start(path: path)
        #expect(!second.isBound)
        #expect(ControlSocket.hasListener(path))
    }

    /// spec: docs/spec.md 2.2.1 - only the user may talk to the socket.
    @Test func socketIsOwnerOnly() {
        let path = path()
        defer { unlink(path) }
        let socket = ControlSocket { _, _ in }
        socket.start(path: path)
        var info = stat()
        #expect(stat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)
    }

    @Test func staleFileIsReplaced() {
        let path = path()
        defer { unlink(path) }
        let stale = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: path.utf8) }
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(stale)
        #expect(!ControlSocket.hasListener(path))

        let replacement = ControlSocket { _, _ in }
        replacement.start(path: path)
        #expect(replacement.isBound)
    }
}
