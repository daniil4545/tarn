import AppKit
import Foundation
import Testing
@testable import Ghostty

/// Where a new tab goes.
@Suite
struct TargetTests {
    private let t = (0..<6).map { _ in TabKey() }

    @Test func aSecondWindowGetsItsOwnSet() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        _ = book.pass([[t[0]], [t[1]]])
        #expect(book.set(of: t[0])?.id != book.set(of: t[1])?.id)
        #expect(book.names([t[1]]) == ["-"])
    }

    @Test func aNewTabIsUngroupedEvenWhenTheSelectedTabIsInAGroup() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        book.group("Work", [t[0]])
        _ = book.selected(t[0])
        _ = book.pass([[t[0], t[1]]], selected: [t[1]])
        #expect(book.workspace(of: t[1]) == nil)
        #expect(book.names([t[0], t[1]]) == ["Work", "-"])
    }

    /// spec: docs/specs/workspace-folder.md S42
    @Test func aTabOpenedFromAnotherTakesItsWorkspaceNotTheSelectedOne() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let work = book.group("Work", [t[1]])
        // t0 (ungrouped) is selected, but the new tab is opened from t1 (Work): before any pass saw it,
        // and again after a pass put it, unplaced, in the set.
        _ = book.selected(t[0])
        _ = book.opened(t[2], from: t[1])
        _ = book.pass([[t[0], t[1], t[2]]], selected: [t[0]])
        #expect(book.workspace(of: t[2])?.id == work)
        _ = book.opened(t[3], from: t[0])
        _ = book.pass([[t[0], t[1], t[2], t[3]]], selected: [t[0]])
        #expect(book.workspace(of: t[3]) == nil)
        _ = book.opened(t[3], from: t[1])
        #expect(book.names([t[0], t[1], t[2], t[3]]) == ["-", "Work"])
        #expect(book.runs(for: [t[0], t[1], t[2], t[3]])[1].tabs == [t[1], t[2], t[3]])
    }

    /// spec: docs/specs/workspace-folder.md S42
    @Test func aTabOpenedFromAnUngroupedTabIsUngroupedRightAfterIt() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        book.group("Work", [t[1]])
        let changed = book.opened(t[2], from: t[0])
        // Placed by `opened`, before any pass saw the tab.
        #expect(changed == [book.set(of: t[0])!.id])
        #expect(book.set(of: t[2])?.id == book.set(of: t[0])?.id)
        _ = book.pass([[t[0], t[2], t[1]]])
        #expect(book.workspace(of: t[2]) == nil)
        #expect(book.names([t[0], t[2], t[1]]) == ["-", "Work"])
        #expect(book.runs(for: [t[0], t[2], t[1]])[0].tabs == [t[0], t[2]])
    }

    @Test func aTabOpenedFromAnotherIsPlacedBeforeThePassSeesIt() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let work = book.group("Work", [t[1]])
        let changed = book.opened(t[2], from: t[1])
        #expect(changed == [book.set(of: t[1])!.id])
        let outcome = book.pass([[t[0], t[1], t[2]]])
        #expect(book.workspace(of: t[2])?.id == work)
        #expect(outcome.changed.isEmpty)
    }

    @Test func aTabSeenAloneBeforeItWasTabbedMovesToTheSourceSet() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        _ = book.pass([[t[0]], [t[1]]])
        _ = book.opened(t[1], from: t[0])
        #expect(book.set(of: t[1])?.id == book.set(of: t[0])?.id)
        #expect(book.sets.count == 1)
    }

    @Test func anOpenedTabUnfoldsItsWorkspace() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        let id = book.group("A", [t[0]])
        _ = book.edit(t[0]) { $0.setCollapsed(id, true) }
        _ = book.opened(t[1], from: t[0])
        #expect(book.workspace(of: t[1])?.collapsed == false)
    }

    @Test func aSourceNobodyHasSeenGivesNoWorkspace() {
        var book = WorkspaceBook()
        #expect(book.opened(t[1], from: t[0]).isEmpty)
        #expect(book.set(of: t[1]) == nil)
    }

    /// spec: docs/specs/workspace-folder.md S44
    @Test func theLastTabLeavingAWorkspaceTakesTheWorkspaceWithIt() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let tarn = book.group("tarn", [t[0]])
        let notes = book.group("Notes", [t[1]])
        #expect(book.names([t[0], t[1]]) == ["tarn", "Notes"])
        _ = book.edit(t[1]) { $0.join(t[1], to: tarn) }
        #expect(book.set(of: t[0])?.workspace(notes) == nil)
        #expect(book.names([t[0], t[1]]) == ["tarn"])
    }

    /// spec: docs/specs/workspace-folder.md S53
    @Test func aTabDroppedBetweenTwoTabsOfAWorkspaceDoesNotJoinIt() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]], [t[3], t[4]]])
        book.group("tarn", [t[0], t[1]])
        _ = book.selected(t[0])
        // t3 leaves a window of two and lands between t0 and t1.
        _ = book.pass([[t[0], t[3], t[1], t[2]], [t[4]]], selected: [t[0], t[4]])
        let order = [t[0], t[3], t[1], t[2]]
        let runs = book.runs(for: order)
        #expect(book.names(order) == ["tarn", "-"])
        #expect(runs[0].tabs == [t[0], t[1]])
        #expect(runs[1].tabs == [t[3], t[2]])
        #expect(book.workspace(of: t[3]) == nil)
    }

    @Test func aTabInAFoldedWorkspaceUnfoldsItOnSelectionButNotOnRepeat() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let id = book.group("A", [t[0], t[1]])
        _ = book.selected(t[1])
        _ = book.edit(t[0]) { $0.setCollapsed(id, true) }

        // The same tab becomes key again (the window regains focus): the fold stays.
        #expect(book.selected(t[1]) == nil)
        #expect(book.workspace(of: t[0])?.collapsed == true)
        // Another tab of the workspace is selected (cmd+1): it unfolds.
        #expect(book.selected(t[0]) != nil)
        #expect(book.workspace(of: t[0])?.collapsed == false)
    }

    @Test func aTabDraggedOutOfItsWindowStartsANewSetUngrouped() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        book.group("A", [t[2]])
        // t2 leaves for its own window; t0 and t1 stay.
        _ = book.pass([[t[0], t[1]], [t[2]]])
        #expect(book.set(of: t[2])?.id != book.set(of: t[0])?.id)
        #expect(book.names([t[2]]) == ["-"])
        #expect(book.names([t[0], t[1]]) == ["-"])
    }

    @Test func aTabDraggedToAnotherWindowIsUngrouped() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[4]], [t[2], t[3]]])
        let other = book.group("Other", [t[2]])
        book.group("Mine", [t[1]])
        _ = book.selected(t[2])
        // t1 moves to the second window, after t3.
        _ = book.pass([[t[0], t[4]], [t[2], t[3], t[1]]], selected: [t[0], t[2]])
        #expect(book.workspace(of: t[1]) == nil)
        #expect(book.workspace(of: t[2])?.id == other)
    }

    @Test func repeatedPassesChangeNothing() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let outcome = book.pass([[t[0], t[1]]])
        #expect(outcome == WorkspaceBook.Outcome())
    }
}

@MainActor
@Suite
struct KeyHopsTests {
    private let t = (0..<4).map { _ in TabKey() }

    @Test func keyNotificationsOfOurOwnMovesAreRecognisedUntilCleared() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        var hops = KeyHops()
        #expect(!hops.contains(window))
        hops.mark(window)
        #expect(hops.contains(window))
        hops.clear()
        #expect(!hops.contains(window))
    }
}
