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
}
