import AppKit
import Foundation
import Testing
@testable import Ghostty

/// T-106: a tab title change made every tab window's sidebar model read every process.
@Suite(.serialized)
@MainActor
struct AgentProcessCacheTests {
    private func withReader(_ reader: @escaping (pid_t) -> String?, body: () -> Void) {
        let saved = AgentProcessCache.reader
        AgentProcessCache.reader = reader
        AgentProcessCache.reset()
        body()
        AgentProcessCache.reader = saved
        AgentProcessCache.reset()
    }

    /// N models rebuild N tabs twice for one event: 2*N^2 lookups, N reads.
    @Test func oneEventReadsEachProcessOnce() {
        let tabs = 8
        var reads = 0
        let reader: (pid_t) -> String? = { pid in
            reads += 1
            return pid == 3 ? "claude" : nil
        }
        withReader(reader) {
            for _ in 0..<2 {
                for _ in 0..<tabs {
                    for pid in 0..<tabs {
                        #expect(AgentProcessCache.agent(pid: pid_t(pid)) == (pid == 3 ? "claude" : nil))
                    }
                }
            }
            #expect(reads == tabs)
            #expect(AgentProcessCache.misses == tabs)
        }
    }

    /// A pid that is not an agent is cached too, or a plain shell would be read every time.
    @Test func aNonAgentAnswerIsCached() {
        var reads = 0
        let reader: (pid_t) -> String? = { _ in
            reads += 1
            return nil
        }
        withReader(reader) {
            _ = AgentProcessCache.agent(pid: 7)
            _ = AgentProcessCache.agent(pid: 7)
            #expect(reads == 1)
        }
    }

    /// The next run loop turn reads again: a shell that became an agent by `exec` shows up.
    @Test func theNextTurnReadsAgain() async {
        var answer: String?
        let saved = AgentProcessCache.reader
        AgentProcessCache.reader = { _ in answer }
        AgentProcessCache.reset()
        defer {
            AgentProcessCache.reader = saved
            AgentProcessCache.reset()
        }

        #expect(AgentProcessCache.agent(pid: 5) == nil)
        answer = "codex"
        #expect(AgentProcessCache.agent(pid: 5) == nil)

        await MainActor.run {}
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(AgentProcessCache.agent(pid: 5) == "codex")
    }

    /// The fix of T-106 is the call in `SidebarModel.makeTab`: five refreshes of a model that
    /// lists a real controller read its shell once. With `AgentProcess.agent` in `makeTab` the
    /// cache sees no read at all and the test fails.
    @Test func refreshesInOneTurnReadTheShellOnce() async throws {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty)
        // Not shown: the window tests that count visible windows are not disturbed.
        let controller = TerminalController(app)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        let model = SidebarModel()
        model.window = window

        var reads: [pid_t] = []
        let saved = AgentProcessCache.reader
        AgentProcessCache.reader = { pid in
            reads.append(pid)
            return nil
        }
        defer {
            AgentProcessCache.reader = saved
            AgentProcessCache.reset()
            model.window = nil
            window.close()
        }

        // Only a read by `model` counts: the window's own sidebar model reads the same shell. `model` has
        // no tab until the registry has put the window in a workspace run, and the shell takes a moment
        // to become the pty's foreground process, so each try starts from an empty cache.
        func ownShellWasRead() -> Bool {
            let own = Set(Array(controller.surfaceTree).compactMap { $0.surfaceModel?.foregroundPID }.compactMap { pid_t(exactly: $0) })
            return !own.isEmpty && own.isSubset(of: reads)
        }

        // A hidden window sends no events, so the registry is asked to look as Ghostty's observers
        // would. No await between the last try and the count below: a parallel test could change
        // the registry there.
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            WorkspaceRegistry.shared.sync()
            reads.removeAll()
            AgentProcessCache.reset()
            model.refresh()
            if ownShellWasRead() { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(ownShellWasRead(), "makeTab never asked for the foreground process")

        reads.removeAll()
        AgentProcessCache.reset()
        for _ in 0..<5 { model.refresh() }
        #expect(ownShellWasRead())
        #expect(reads.count == Set(reads).count, "a pid was read twice in one turn: \(reads)")
    }
}
