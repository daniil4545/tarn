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

    /// Runs `program` from a link named `file` with `argv`; the kernel name stays `program`'s.
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

    /// Runs `argv` as the leader of a new process group, as a pane's process is.
    private func withGroup(_ argv: [String], _ body: (pid_t) throws -> Void) throws {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)
        var cArgs = argv.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        var pid: pid_t = 0
        try #require(posix_spawn(&pid, argv[0], nil, &attr, &cArgs, environ) == 0)
        defer {
            killpg(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
        try body(pid)
    }

    /// `pid` once it is not `group` and `comm` names it, or nil after 5 s.
    private func settled(_ group: pid_t, comm: String) -> pid_t? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let pid = AgentProcess.foreground(group: group)
            if pid != group, AgentProcess.comm(pid: pid) == comm { return pid }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    /// spec: T-218 - a pane `tarn new` opened shows its command and folder, not login's.
    @Test func aCommandStartedThroughLoginIsTheForegroundProcess() throws {
        let user = String(cString: getpwuid(getuid()).pointee.pw_name)
        // `exec` as Ghostty's `exec -l`: login's child becomes the command (`/bin/sh` is bash by kernel name).
        try withGroup(["/usr/bin/login", "-flp", user, "/bin/sh", "-c", "cd /tmp && exec sleep 30"]) { login in
            #expect(AgentProcess.comm(pid: login) == "login")
            let command = try #require(settled(login, comm: "sleep"), "login's child never appeared")
            #expect(ViewerPaths.cwd(ofPid: command) == "/private/tmp")
        }
    }

    /// spec: T-218 - an agent keeps its group while its tools run: the leader still stands for it.
    @Test func aGroupLeaderThatIsNotLoginStandsForItsGroup() throws {
        try withGroup(["/bin/sh", "-c", "sleep 30; :"]) { shell in
            // sleep, the tool, must be in the group before the check means anything.
            let deadline = Date().addingTimeInterval(5)
            var pids = [pid_t](repeating: 0, count: 16)
            func members() -> Int {
                Int(proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(shell), &pids, Int32(pids.count * 4))) / 4
            }
            while members() < 2, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            try #require(members() == 2, "sleep never joined the group")
            #expect(AgentProcess.foreground(group: shell) == shell)
        }
    }

    /// spec: T-250 - an ssh tab keeps the remote shell's title.
    @Test func anSSHClientIsNamedByItsKernelName() throws {
        // The kernel names a process after the link's target, so this is the real client; the
        // proxy command keeps it waiting with no network and no user config.
        let ssh = ["ssh", "-F", "/dev/null", "-o", "BatchMode=yes", "-o", "ProxyCommand=sleep 30", "tarn-test"]
        try withProcess(file: "ssh", program: "/usr/bin/ssh", argv: ssh) { pid in
            #expect(execed(pid, comm: "ssh"), "the kernel name never became ssh")
            #expect(AgentProcess.isSSH(pid: pid))
            #expect(AgentProcess.agent(pid: pid) == nil)
        }
        try withProcess(file: "sleep", argv: ["sleep", "30"]) { pid in
            #expect(execed(pid, comm: "sleep"), "the kernel name never became sleep")
            #expect(!AgentProcess.isSSH(pid: pid))
        }
    }

    /// Whether `pid` took the kernel name `comm` within 5 s: posix_spawn returns before exec.
    private func execed(_ pid: pid_t, comm: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if AgentProcess.comm(pid: pid) == comm { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
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
