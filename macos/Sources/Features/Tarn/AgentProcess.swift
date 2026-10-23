// Based on Macterm/Model/AgentIcon.swift and Macterm/System/ProcessInspector.swift
// from thdxg/macterm, Copyright (c) 2026 Macterm, MIT License. See THIRD_PARTY.md.

import Darwin
import Foundation

/// Names the coding agent that runs as a surface's foreground process, if any.
///
/// The foreground process group stays with the agent while it runs its own tools,
/// so a `bash` started by Claude Code does not hide the agent.
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

    /// The kernel name of `pid`: the executable's basename cut to 15 characters.
    static func comm(pid: pid_t) -> String? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: &info.pbsi_comm) { raw in
            raw.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) }
        }
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
