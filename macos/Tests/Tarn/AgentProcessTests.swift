import AppKit
import Darwin
import Foundation
import Testing
@testable import Ghostty

/// Agent detection by process name and the tab titles it gives.
@Suite
struct AgentProcessTests {
    @Test func matchesAgentNamesWithSuffixesButNotLookalikes() {
        #expect(AgentProcess.match("claude") == "claude")
        #expect(AgentProcess.match("Codex") == "codex")
        #expect(AgentProcess.match("codex-aarch64-a") == "codex")
        #expect(AgentProcess.match("claude.exe") == "claude")
        #expect(AgentProcess.match("opencode") == "opencode")
        #expect(AgentProcess.match("claudette") == nil)
        #expect(AgentProcess.match("zsh") == nil)
        #expect(AgentProcess.match(nil) == nil)
    }

    @Test func invokedNameReadsTheScriptBehindAnInterpreter() {
        #expect(AgentProcess.invokedName(["/opt/homebrew/bin/claude", "--resume"]) == "claude")
        #expect(AgentProcess.invokedName(["node", "/usr/local/lib/node_modules/.bin/opencode"]) == "opencode")
        #expect(AgentProcess.invokedName(["node", "/x/codex.js"]) == "codex")
        #expect(AgentProcess.invokedName(["node", "--inspect"]) == "node")
        #expect(AgentProcess.invokedName(["-zsh"]) == "zsh")
        #expect(AgentProcess.invokedName([]) == nil)
    }

    @Test func versionNamesAreRecognized() {
        #expect(AgentProcess.looksLikeVersion("2.1.207"))
        #expect(!AgentProcess.looksLikeVersion("2"))
        #expect(!AgentProcess.looksLikeVersion("python3.12"))
    }

    /// Runs `program` from a link named `file` with `argv`, so the kernel name is `file`.
    private func withProcess(
        file: String,
        program: String = "/bin/sleep",
        argv: [String],
        _ body: (pid_t) -> Void
    ) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent(file).path
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: program)

        var cArgs = argv.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        var pid: pid_t = 0
        try #require(posix_spawn(&pid, path, nil, nil, &cArgs, environ) == 0)
        defer {
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
        body(pid)
    }

    @Test(arguments: [
        // The kernel name is the agent.
        ("codex-aarch64-a", ["codex"], "codex"),
        // A version-named binary: argv[0] names the agent.
        ("2.1.207", ["claude", "--resume"], "claude"),
        // An interpreter: the script names the agent.
        ("node", ["node", "/usr/local/bin/opencode"], "opencode"),
        // A real program name never falls back to argv.
        ("zsh", ["claude"], nil),
        ("node", ["node", "server.js"], nil),
    ] as [(String, [String], String?)])
    func namesTheAgentFromKernelNameAndArguments(comm: String, argv: [String], agent: String?) {
        #expect(AgentProcess.agent(comm: comm) { argv } == agent)
    }

    @Test func argumentsAreReadOnlyWhenTheNameCannotBeTheCommand() {
        var reads = 0
        _ = AgentProcess.agent(comm: "bash") {
            reads += 1
            return ["claude"]
        }
        #expect(reads == 0)
    }

    @Test func readsTheKernelNameAndArgumentsOfALiveProcess() throws {
        // The trailing `:` keeps sh from replacing itself with sleep; the empty argument
        // must keep its place.
        let argv = ["probe", "-c", "sleep 30; :", "", "last"]
        try withProcess(file: "probe", program: "/bin/sh", argv: argv) { pid in
            #expect(AgentProcess.argv(pid: pid) == argv)
            #expect(AgentProcess.comm(pid: pid) != nil)
            #expect(AgentProcess.agent(pid: pid) == nil)
        }
    }

    @Test func unreadablePidIsNotAnAgent() {
        #expect(AgentProcess.agent(pid: 999_999) == nil)
    }

    @Test(arguments: [
        // codex leaves the shell's folder title: the agent's name replaces it.
        ("Galera", "codex", "Codex"),
        ("~/Galera", "codex", "Codex"),
        ("", "opencode", "OpenCode"),
        // codex leads the folder title with a spinner.
        ("⠏ Galera", "codex", "Codex"),
        // An agent's own title stays without its leading mark.
        ("✳ Claude Code", "claude", "Claude Code"),
        ("opencode", "opencode", "opencode"),
        // Without an agent the folder title stays.
        ("Galera", nil, "Galera"),
    ] as [(String, String?, String)])
    func agentTabTitle(title: String, agent: String?, shown: String) {
        #expect(SidebarModel.displayTitle(title, pwd: "/u/Galera", agent: agent) == shown)
    }

    @Test func everyAgentHasANameAndAnIcon() {
        for agent in AgentProcess.names {
            #expect(AgentProcess.displayNames[agent] != nil)
            #expect(AgentProcess.icons[agent].flatMap { NSImage(named: $0) } != nil, "\(agent)")
        }
    }
}
