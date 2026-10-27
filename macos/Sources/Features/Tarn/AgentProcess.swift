// Based on Macterm/Model/AgentIcon.swift and Macterm/System/ProcessInspector.swift
// from thdxg/macterm, Copyright (c) 2026 Macterm, MIT License. See THIRD_PARTY.md.

import Darwin
import Foundation

/// Names the coding agent that runs as a surface's foreground process, if any. The agent keeps
/// the foreground group while its own tools run, so a `bash` it starts does not hide it.
enum AgentProcess {
    /// Agent command names. A process matches one exactly, or as a prefix followed by a
    /// separator: brew's codex binary has the kernel name `codex-aarch64-a`.
    static let names = ["claude", "codex", "opencode"]

    /// Names to show for an agent that sets no title of its own.
    static let displayNames = ["claude": "Claude Code", "codex": "Codex", "opencode": "OpenCode"]

    /// Monochrome template images in `Assets.xcassets`, tinted like SF Symbols.
    static let icons = ["claude": "TarnAgentClaude", "codex": "TarnAgentCodex", "opencode": "TarnAgentOpenCode"]

    /// The agent running as `pid`, or nil for a shell, any other program or an unreadable pid.
    static func agent(pid: pid_t) -> String? {
        agent(comm: comm(pid: pid)) { argv(pid: pid) }
    }

    /// The agent named by a kernel name, or by the arguments read only when needed.
    static func agent(comm: String?, argv: () -> [String]?) -> String? {
        if let agent = match(comm) { return agent }

        // Only a name that cannot be the command itself costs an argv read: a bare version
        // (a native Claude Code build may set it) or an interpreter running a script.
        if let comm, !looksLikeVersion(comm), !interpreters.contains(comm.lowercased()) { return nil }
        return argv().flatMap(invokedName).flatMap(match)
    }

    static func match(_ processName: String?) -> String? {
        guard var name = processName?.lowercased() else { return nil }
        if name.hasSuffix(".exe") { name.removeLast(4) }
        if names.contains(name) { return name }

        // Longest name first, so a short name that prefixes a longer one cannot win.
        for key in names.sorted(by: { $0.count > $1.count }) where name.hasPrefix(key) {
            if let next = name.dropFirst(key.count).first, !next.isLetter, !next.isNumber {
                return key
            }
        }
        return nil
    }

    /// The name the user ran: argv[0]'s basename, or for an interpreter (`node …/bin/codex`)
    /// the script's basename without its extension.
    static func invokedName(_ argv: [String]) -> String? {
        guard var first = argv.first, !first.isEmpty else { return nil }
        if first.hasPrefix("-") { first.removeFirst() }
        let name = (first as NSString).lastPathComponent
        guard interpreters.contains(name.lowercased()), argv.count > 1 else { return name }

        let script = (argv[1] as NSString).lastPathComponent
        guard !script.isEmpty, !script.hasPrefix("-") else { return name }
        let ns = script as NSString
        return scriptExtensions.contains(ns.pathExtension.lowercased()) ? ns.deletingPathExtension : script
    }

    /// Digits and dots with at least one dot, digits at both ends, such as `2.1.207`.
    static func looksLikeVersion(_ value: String) -> Bool {
        value.contains(".")
            && value.allSatisfy { $0.isNumber || $0 == "." }
            && (value.first?.isNumber ?? false)
            && (value.last?.isNumber ?? false)
    }

    private static let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3"]
    private static let scriptExtensions: Set<String> = ["js", "mjs", "cjs", "ts", "py"]

    /// Whether `pid` is an ssh client. Ghostty drops OSC 7 with a remote host, so the tab's
    /// folder stays the local one ssh started in while the title is the remote shell's.
    static func isSSH(pid: pid_t) -> Bool { comm(pid: pid) == "ssh" }

    /// The kernel name of `pid`: the executable's basename cut to 15 characters.
    static func comm(pid: pid_t) -> String? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: &info.pbsi_comm) { raw in
            raw.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) }
        }
    }

    /// The process that stands for a foreground process group: its leader, as WezTerm
    /// `get_foreground_process_info` takes `process_group_leader` (`mux/src/localpane.rs`). The one exception is a command Ghostty starts
    /// through `/usr/bin/login -flp` (`src/termio/Exec.zig:1933`): without job control it stays in
    /// login's group, so the leader is login and the command is login's child in the group. The
    /// members come from `proc_listpids(PROC_PGRP_ONLY)`, as kitty `processes_in_group` reads them.
    static func foreground(group: pid_t) -> pid_t {
        guard comm(pid: group) == "login" else { return group }
        let count = proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(group), nil, 0) / Int32(MemoryLayout<pid_t>.size)
        guard count > 0 else { return group }
        var pids = [pid_t](repeating: 0, count: Int(count) + 8)
        let size = proc_listpids(
            UInt32(PROC_PGRP_ONLY), UInt32(group), &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let members = pids.prefix(Int(size) / MemoryLayout<pid_t>.size)
        return members.first { $0 > 0 && $0 != group && parent($0) == group } ?? group
    }

    private static func parent(_ pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbsi_ppid)
    }

    /// The arguments of `pid` from `KERN_PROCARGS2`:
    /// `[int32 argc][exec_path\0][\0 padding][argv0\0 argv1\0 …][env…]`.
    static func argv(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let ok = buffer.withUnsafeMutableBytes { sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) == 0 }
        guard ok, size > MemoryLayout<Int32>.size else { return nil }
        buffer.removeLast(buffer.count - size)

        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        guard argc > 0 else { return nil }
        var i = MemoryLayout<Int32>.size
        let end = buffer.count

        // Skip exec_path and the padding after it.
        while i < end, buffer[i] != 0 { i += 1 }
        guard i < end else { return nil }
        while i < end, buffer[i] == 0 { i += 1 }

        // Exactly argc fields, empty ones kept, so the environment never slides in.
        var argv: [String] = []
        for _ in 0..<argc {
            guard i < end else { break }
            let start = i
            while i < end, buffer[i] != 0 { i += 1 }
            // A non-UTF-8 argument becomes empty but keeps its place.
            argv.append(String(bytes: buffer[start..<i], encoding: .utf8) ?? "")
            i += 1
        }
        return argv.count == argc ? argv : nil
    }
}

/// Answers of `AgentProcess.agent(pid:)` kept for the current run loop turn. Every tab window
/// has its own sidebar model, and one tab event (a title change) makes all N of them rebuild
/// their tabs; without this each model re-read every process, 2*N^2 reads per event
/// (T-106). A pid read once in a turn is shared, so a pass costs one read per pid; an event has two passes (2*N reads, not 2*N^2). The
/// next turn starts empty: the second refresh after a tab event and the 2 s timer see a
/// process that was replaced by `exec`.
@MainActor
enum AgentProcessCache {
    /// How a pid is read. Tests replace it to count the reads.
    static var reader: (pid_t) -> String? = { AgentProcess.agent(pid: $0) }

    /// The reads that missed the cache since the last `reset`.
    private(set) static var misses = 0

    private static var entries: [pid_t: String?] = [:]
    private static var sshEntries: [pid_t: Bool] = [:]
    private static var isClearScheduled = false

    static func agent(pid: pid_t) -> String? {
        if let hit = entries[pid] { return hit }
        misses += 1
        let agent = reader(pid)
        entries[pid] = .some(agent)
        scheduleClear()
        return agent
    }

    static func isSSH(pid: pid_t) -> Bool {
        if let hit = sshEntries[pid] { return hit }
        let isSSH = AgentProcess.isSSH(pid: pid)
        sshEntries[pid] = isSSH
        scheduleClear()
        return isSSH
    }

    /// Forgets every answer and the miss count.
    static func reset() {
        entries.removeAll()
        sshEntries.removeAll()
        misses = 0
    }

    private static func scheduleClear() {
        guard !isClearScheduled else { return }
        isClearScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                isClearScheduled = false
                entries.removeAll()
                sshEntries.removeAll()
            }
        }
    }
}
