import Foundation
import Testing
@testable import Ghostty

/// Agent tabs join the workspace of their folder (D21, D26, D27).
@Suite(.serialized)
struct AgentArrivalTests {
    private let t = (0..<4).map { _ in TabKey() }
    private let alive: (pid_t) -> Bool = { _ in true }
    private let dead: (pid_t) -> Bool = { _ in false }

    /// A restored folderless "No project" holds t0 and t2, "tarn" (`/p/F`) holds t1, "dev" (`/p`) holds t3.
    private func makeBook() -> (book: WorkspaceBook, tarn: Workspace.ID, dev: Workspace.ID) {
        var book = WorkspaceBook()
        book.restoreLegacy([t[0], t[1], t[3], t[2]])
        _ = book.pass([[t[0], t[1], t[3], t[2]]])
        var tarn: Workspace.ID?
        var dev: Workspace.ID?
        _ = book.edit(t[0]) {
            tarn = $0.create(name: "tarn", folder: "/p/F")
            dev = $0.create(name: "dev", folder: "/p")
        }
        _ = book.edit(t[1]) { $0.join(t[1], to: tarn!) }
        _ = book.edit(t[3]) { $0.join(t[3], to: dev!) }
        _ = book.pass([[t[0], t[2], t[1], t[3]]])
        return (book, tarn!, dev!)
    }

    private func start(_ book: inout WorkspaceBook, _ tab: TabKey, pid: pid_t = 10, at path: String?) -> String? {
        book.checkArrival(tab, alive: alive) { (pid, path) }
    }

    // spec: docs/specs/workspace-folder.md S11
    @Test func anAgentInAFolderJoinsItsWorkspaceAndIsNotMarked() {
        var (book, tarn, _) = makeBook()
        #expect(start(&book, t[0], at: "/p/F/macos") == nil)
        #expect(book.pendingTabs == [t[0]])
        #expect(book.takeArrival(t[0]) == tarn)
        _ = book.edit(t[0]) { $0.join(t[0], to: tarn) }
        #expect(book.set(of: t[0])?.isManual(t[0]) == false)
        #expect(book.pendingTabs.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S12
    @Test func anAgentAtHomeDoesNotMove() {
        let (book, _, _) = makeBook()
        #expect(book.arrival(of: t[1], at: "/p/F") == nil)
        #expect(book.arrival(of: t[1], at: "/p/F/docs") == nil)
    }

    // spec: docs/specs/workspace-folder.md S13
    @Test func anAgentOutsideEveryFolderStaysAndMarksOnlyAWorkspaceWithAFolder() {
        let (book, _, _) = makeBook()
        #expect(book.arrival(of: t[1], at: "/q/other") == nil)
        #expect(book.isOutsideFolder(t[1], at: "/q/other"))
        #expect(!book.isOutsideFolder(t[1], at: "/p/F/macos"))
        #expect(!book.isOutsideFolder(t[0], at: "/q/other"))
        #expect(book.arrival(of: t[0], at: "/q/other") == nil)
    }

    // spec: docs/specs/workspace-folder.md S14
    @Test func theDeepestFolderWins() {
        let (book, tarn, dev) = makeBook()
        #expect(book.arrival(of: t[0], at: "/p/F/macos") == tarn)
        #expect(book.arrival(of: t[0], at: "/p/notes") == dev)
        #expect(book.arrival(of: t[3], at: "/p/F/macos") == tarn)
    }

    // spec: docs/specs/workspace-folder.md S15
    @Test func theSameFolderTwiceKeepsTheCurrentThenTakesTheUpper() {
        let a = Workspace(name: "A", folder: "/p/F")
        let b = Workspace(name: "B", folder: "/p/F")
        let runs = [WorkspaceSet.Run(workspace: a, tabs: []), WorkspaceSet.Run(workspace: b, tabs: [])]
        #expect(WorkspaceFolder.home(for: "/p/F/x", in: runs, current: b.id) == b.id)
        #expect(WorkspaceFolder.home(for: "/p/F/x", in: runs, current: nil) == a.id)
        #expect(WorkspaceFolder.home(for: "/q", in: runs, current: a.id) == nil)
        #expect(WorkspaceFolder.home(for: "relative", in: runs, current: a.id) == nil)
    }

    // spec: docs/specs/workspace-folder.md S16
    @Test func aManualTabNeverArrives() {
        var (book, _, _) = makeBook()
        _ = book.edit(t[0]) { $0.markManual(t[0]) }
        #expect(book.arrival(of: t[0], at: "/p/F") == nil)
        _ = start(&book, t[2], at: "/p/F")
        _ = book.edit(t[2]) { $0.markManual(t[2]) }
        #expect(book.takeArrival(t[2]) == nil)
    }

    // spec: docs/specs/workspace-folder.md S17
    @Test func anAgentThatRestartsFiresTheCheckAgain() {
        var (book, _, _) = makeBook()
        _ = start(&book, t[0], pid: 10, at: "/q")
        _ = book.takeArrival(t[0])
        var calls = 0
        _ = book.checkArrival(t[0], alive: dead) { calls += 1; return (11, "/p/F") }
        #expect(calls == 1)
        #expect(book.pendingTabs == [t[0]])
    }

    // spec: docs/specs/workspace-folder.md S18
    @Test func aCdAfterTheJoinQueuesNothing() {
        var (book, _, _) = makeBook()
        _ = start(&book, t[0], at: "/p/F")
        _ = book.takeArrival(t[0])
        var calls = 0
        _ = book.checkArrival(t[0], alive: alive) { calls += 1; return (10, "/q/notes") }
        #expect(calls == 0)
        #expect(book.pendingTabs.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S19
    @Test func theFirstAgentDecidesAndASecondOneIsIgnored() {
        var (book, _, _) = makeBook()
        _ = start(&book, t[0], pid: 10, at: "/q")
        #expect(book.pendingTabs == [t[0]])
        _ = book.takeArrival(t[0])
        _ = start(&book, t[0], pid: 20, at: "/p/F")
        #expect(book.pendingTabs.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S27
    @Test func unexpectedInputQueuesNothingAndGivesOneNote() {
        var (book, _, _) = makeBook()
        #expect(start(&book, t[0], at: nil)?.contains("usable path") == true)
        _ = book.checkArrival(t[2], alive: dead) { nil }
        #expect(start(&book, t[2], pid: 12, at: "relative")?.contains("usable path") == true)
        #expect(start(&book, TabKey(), at: "/p/F")?.contains("without a set") == true)
        #expect(book.pendingTabs.isEmpty)
        #expect(book.arrival(of: TabKey(), at: "/p/F") == nil)
        #expect(!book.isOutsideFolder(TabKey(), at: "/p/F"))
    }

    // spec: docs/specs/workspace-folder.md S28
    @Test func theQueueKeepsThePathAndComputesTheDestinationWhenItRuns() {
        var (book, tarn, dev) = makeBook()
        _ = start(&book, t[0], at: "/p/F/macos")
        #expect(book.pendingTabs == [t[0]])
        _ = book.edit(t[0]) { _ = $0.delete(tarn, order: [t[0], t[2], t[1], t[3]]) }
        #expect(book.takeArrival(t[0]) == dev)
    }

    // spec: docs/specs/workspace-folder.md S29
    @Test func aNewTabAfterAnArrivalJoinsTheDestination() {
        var (book, tarn, _) = makeBook()
        _ = book.selected(t[2])
        _ = book.edit(t[0]) { $0.join(t[0], to: tarn) }
        _ = book.arrived(t[0], selected: true)
        #expect(book.folderForNewSurface(from: t[0], order: [t[2], t[1], t[0], t[3]], split: false) == "/p/F")
    }

    // spec: docs/specs/workspace-folder.md S30
    @Test func anUndoOfACloseKeepsTheDecidingProcess() {
        var (book, _, _) = makeBook()
        _ = start(&book, t[0], at: "/q")
        _ = book.takeArrival(t[0])
        let closed = book.closing(t[0])
        #expect(closed?.deciding == 10)
        let back = TabKey()
        book.reinsert(back, from: closed!)
        var calls = 0
        _ = book.checkArrival(back, alive: alive) { calls += 1; return (10, "/p/F") }
        #expect(calls == 0)
    }

    // spec: docs/specs/workspace-folder.md S31
    @Test func anArrivalDoesNotMark() {
        var (book, tarn, _) = makeBook()
        _ = book.edit(t[0]) { $0.join(t[0], to: tarn, byUser: false) }
        #expect(book.set(of: t[0])?.manual.isEmpty == true)
    }

    // spec: docs/specs/workspace-folder.md S32
    @Test func aCollapsedDestinationUnfoldsForASelectedArrivalOnly() {
        var (book, tarn, _) = makeBook()
        _ = book.edit(t[1]) { $0.setCollapsed(tarn, true) }
        _ = book.edit(t[0]) { $0.join(t[0], to: tarn) }
        #expect(book.arrived(t[0], selected: false) == nil)
        #expect(book.workspace(of: t[0])?.collapsed == true)
        #expect(book.arrived(t[0], selected: true) != nil)
        #expect(book.workspace(of: t[0])?.collapsed == false)
    }

    // spec: docs/specs/workspace-folder.md S20
    @Test func aFolderInAnotherWindowIsNeverAnArrivalTarget() {
        var (book, _, _) = makeBook()
        let other = TabKey()
        let outside = TabKey()
        _ = book.pass([[t[0], t[2], t[1], t[3]], [other, outside]])
        _ = book.edit(other) { $0.rename($0.workspaces[0].id, to: "far") }
        _ = book.edit(other) { _ = $0.create(name: "elsewhere", folder: "/z/only") }
        #expect(book.arrival(of: outside, at: "/p/F") == nil)
        #expect(book.arrival(of: t[0], at: "/z/only") == nil)
        _ = start(&book, outside, at: "/p/F")
        #expect(book.takeArrival(outside) == nil)
    }

    // spec: docs/specs/workspace-folder.md S28
    @Test func aQueuedTabWaitsUntilItsWindowGroupIsKey() {
        var (book, _, _) = makeBook()
        _ = start(&book, t[0], at: "/p/F")
        #expect(book.runnable(in: [TabKey()]).isEmpty)
        #expect(book.pendingTabs == [t[0]])
        #expect(book.runnable(in: [t[2], t[0]]) == [t[0]])
    }

    // spec: docs/specs/workspace-folder.md R4
    @Test func anAgentStartedWhileFrozenQueuesNothingAndIsNoArrivalLater() {
        var (book, _, _) = makeBook()
        book.frozen = true
        _ = start(&book, t[0], at: "/p/F")
        #expect(book.pendingTabs.isEmpty)
        book.frozen = false
        var calls = 0
        _ = book.checkArrival(t[0], alive: alive) { calls += 1; return (10, "/q/after-cd") }
        #expect(calls == 0)
        #expect(book.pendingTabs.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S33
    @Test func aStoppedAndResumedAgentIsNoNewStart() {
        var (book, _, _) = makeBook()
        _ = start(&book, t[0], at: "/q")
        _ = book.takeArrival(t[0])
        var calls = 0
        for _ in 0..<3 { _ = book.checkArrival(t[0], alive: alive) { calls += 1; return (10, "/p/F") } }
        #expect(calls == 0)
        #expect(book.pendingTabs.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S33
    @Test func theLiveProcessCheckSeesOurOwnAndNotAGonePid() {
        #expect(WorkspaceRegistry.isAlive(getpid()))
        #expect(!WorkspaceRegistry.isAlive(Int32.max))
    }

    /// T-106: each agent pid costs one cache read; a tab with a live deciding process costs none,
    /// and later lookups of the same pid in the turn (the sidebar's) are hits.
    @MainActor @Test func theCheckCostsOneCacheReadPerNewPid() {
        let saved = AgentProcessCache.reader
        AgentProcessCache.reader = { _ in "claude" }
        AgentProcessCache.reset()
        defer {
            AgentProcessCache.reader = saved
            AgentProcessCache.reset()
        }
        var (book, _, _) = makeBook()
        func sync() {
            for (index, tab) in t.enumerated() {
                let pid = pid_t(10 + index)
                _ = book.checkArrival(tab, alive: alive) {
                    AgentProcessCache.agent(pid: pid) == nil ? nil : (pid, "/q")
                }
            }
        }
        sync()
        #expect(AgentProcessCache.misses == t.count)
        sync()
        sync()
        #expect(AgentProcessCache.misses == t.count)
        _ = AgentProcessCache.agent(pid: 10)
        #expect(AgentProcessCache.misses == t.count)
    }
}
