// Benchmark of two terminal apps for `make -f tarn.mk bench`: startup, idle CPU, memory and
// output throughput, the metrics and thresholds of docs/spec.md section 7.
// Usage: bench <tarn.app> <upstream.app> <work dir>; prints a markdown report, exits 1 over a threshold.
import AppKit
import Darwin

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write("usage: bench <tarn.app> <upstream.app> <work dir>\n".data(using: .utf8)!)
    exit(2)
}
let apps = [("tarn", URL(fileURLWithPath: args[1])), ("upstream", URL(fileURLWithPath: args[2]))]
let work = URL(fileURLWithPath: args[3])
let throughputScript = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("throughput.sh")

let startupRuns = 10, throughputRuns = 5, idleSeconds = 60, settleSeconds = 5

/// A config folder for `XDG_CONFIG_HOME`: the same options for both apps, no restore, no updater, no quit question.
func configHome(_ name: String, command: String) throws -> URL {
    let dir = work.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("ghostty"), withIntermediateDirectories: true)
    let config = """
        command = \(command)
        window-save-state = never
        window-width = 120
        window-height = 40
        confirm-close-surface = false
        auto-update = off
        """
    try config.write(to: dir.appendingPathComponent("ghostty/config"), atomically: true, encoding: .utf8)
    return dir
}

func launch(_ app: URL, xdg: URL) -> NSRunningApplication {
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.activates = false
    config.addsToRecentItems = false
    config.environment = ["XDG_CONFIG_HOME": xdg.path]
    var result: Result<NSRunningApplication, Error>?
    NSWorkspace.shared.openApplication(at: app, configuration: config) { running, error in
        result = running.map { .success($0) } ?? .failure(error ?? CocoaError(.fileNoSuchFile))
    }
    while result == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
    switch result! {
    case .success(let running): return running
    case .failure(let error): fatalError("cannot launch \(app.path): \(error)")
    }
}

func hasWindow(_ pid: pid_t) -> Bool {
    let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return list.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
}

func quit(_ app: NSRunningApplication) {
    app.terminate()
    let deadline = Date().addingTimeInterval(5)
    while !app.isTerminated && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    if !app.isTerminated { app.forceTerminate() }
    while !app.isTerminated { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
}

func usage(_ pid: pid_t) -> rusage_info_v4 {
    var info = rusage_info_v4()
    let code = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    precondition(code == 0, "proc_pid_rusage failed for \(pid)")
    return info
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
}

/// Launch to the first on-screen window, milliseconds.
func startup(_ app: URL, xdg: URL) -> Double {
    let start = Date()
    let running = launch(app, xdg: xdg)
    while !hasWindow(running.processIdentifier) { usleep(2000) }
    let ms = Date().timeIntervalSince(start) * 1000
    quit(running)
    return ms
}

/// Mean CPU percent over `idleSeconds` after a settle, and resident memory at the end, MB.
func idle(_ app: URL, xdg: URL) -> (cpu: Double, rss: Double, footprint: Double) {
    let running = launch(app, xdg: xdg)
    let pid = running.processIdentifier
    while !hasWindow(pid) { usleep(10000) }
    sleep(UInt32(settleSeconds))
    let first = usage(pid), t0 = Date()
    sleep(UInt32(idleSeconds))
    let last = usage(pid)
    let elapsed = Date().timeIntervalSince(t0)
    // rusage CPU times are in Mach ticks: the timebase turns them into nanoseconds.
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let ticks = Double((last.ri_user_time + last.ri_system_time) - (first.ri_user_time + first.ri_system_time))
    let cpuSeconds = ticks * Double(timebase.numer) / Double(timebase.denom) / 1e9
    quit(running)
    return (cpuSeconds / elapsed * 100, Double(last.ri_resident_size) / 1_048_576, Double(last.ri_phys_footprint) / 1_048_576)
}

/// Wall time of `cat` of a 100 MB file in the app's only surface, seconds.
func throughput(_ app: URL, data: URL, run: Int, name: String) throws -> Double {
    let out = work.appendingPathComponent("\(name)-cat-\(run).txt")
    try? FileManager.default.removeItem(at: out)
    let xdg = try configHome("\(name)-cat", command: "direct:/bin/zsh \(throughputScript.path) \(data.path) \(out.path)")
    let running = launch(app, xdg: xdg)
    let deadline = Date().addingTimeInterval(120)
    while !FileManager.default.fileExists(atPath: out.path) {
        precondition(Date() < deadline, "\(name): no throughput result in 120 s")
        usleep(50000)
    }
    usleep(100_000)
    quit(running)
    return Double(try String(contentsOf: out, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
}

try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let data = work.appendingPathComponent("cat-100mb.txt")
if !FileManager.default.fileExists(atPath: data.path) {
    let line = "tarn bench 0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ\n"
    let block = String(repeating: line, count: 100_000).data(using: .utf8)!
    FileManager.default.createFile(atPath: data.path, contents: nil)
    let handle = try FileHandle(forWritingTo: data)
    while try handle.offset() < 100_000_000 { handle.write(block) }
    try handle.close()
}

struct Numbers { var startup = 0.0, cpu = 0.0, rss = 0.0, footprint = 0.0, cat = 0.0 }
var results: [String: Numbers] = [:]
for (name, app) in apps {
    FileHandle.standardError.write("bench: \(name) \(app.path)\n".data(using: .utf8)!)
    let xdg = try configHome("\(name)-idle", command: "direct:/bin/cat")
    var numbers = Numbers()
    numbers.startup = median((0..<startupRuns).map { _ in startup(app, xdg: xdg) })
    (numbers.cpu, numbers.rss, numbers.footprint) = idle(app, xdg: xdg)
    numbers.cat = median(try (0..<throughputRuns).map { try throughput(app, data: data, run: $0, name: name) })
    results[name] = numbers
}

let tarn = results["tarn"]!, upstream = results["upstream"]!
func percent(_ a: Double, _ b: Double) -> Double { (a - b) / b * 100 }
let rows: [(String, Double, Double, String, Bool)] = [
    ("Startup, ms (median of \(startupRuns))", tarn.startup, upstream.startup,
     String(format: "%+.1f%%", percent(tarn.startup, upstream.startup)), percent(tarn.startup, upstream.startup) <= 5),
    ("Idle CPU, % (mean of \(idleSeconds) s)", tarn.cpu, upstream.cpu,
     String(format: "%+.2f pp", tarn.cpu - upstream.cpu), tarn.cpu - upstream.cpu <= 0.5),
    ("Memory RSS, MB", tarn.rss, upstream.rss,
     String(format: "%+.1f%%", percent(tarn.rss, upstream.rss)), percent(tarn.rss, upstream.rss) <= 5),
    ("Memory footprint, MB", tarn.footprint, upstream.footprint,
     String(format: "%+.1f%%", percent(tarn.footprint, upstream.footprint)), percent(tarn.footprint, upstream.footprint) <= 5),
    ("cat 100 MB, s (median of \(throughputRuns))", tarn.cat, upstream.cat,
     String(format: "%+.1f%%", percent(tarn.cat, upstream.cat)), percent(tarn.cat, upstream.cat) <= 5),
]
print("| Metric | tarn | upstream | Difference | Within threshold |")
print("| --- | --- | --- | --- | --- |")
for (metric, a, b, diff, ok) in rows {
    print("| \(metric) | \(String(format: "%.2f", a)) | \(String(format: "%.2f", b)) | \(diff) | \(ok ? "yes" : "no") |")
}
exit(rows.allSatisfy { $0.4 } ? 0 : 1)
