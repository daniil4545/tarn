import AppKit
import Foundation
import Testing
@testable import Ghostty

/// Where a new tab goes.
@Suite
struct TargetTests {
    private let t = (0..<6).map { _ in TabKey() }

    @Test func firstLaunchHasDefaultWithTheTab() {
        var book = WorkspaceBook()
        let outcome = book.pass([[t[0]]])
        #expect(book.names([t[0]]) == [WorkspaceSet.homeName])
        #expect(book.workspace(of: t[0])?.folder == nil)
        #expect(outcome.changed.count == 1)
    }

    @Test func aSecondWindowGetsItsOwnDefault() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        _ = book.pass([[t[0]], [t[1]]])
        #expect(book.set(of: t[0])?.id != book.set(of: t[1])?.id)
        #expect(book.names([t[1]]) == [WorkspaceSet.homeName])
        #expect(book.workspace(of: t[1])?.folder == nil)
    }

    @Test func aNewTabJoinsTheWorkspaceOfTheSelectedTab() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        _ = book.newWorkspace("Work", in: t[0])
        // Select t0 ("~"), then a new tab appears: it goes to Default.
        _ = book.selected(t[0])
        _ = book.pass([[t[0], t[1]]], selected: [t[1]])
        #expect(book.workspace(of: t[1])?.name == WorkspaceSet.homeName)
    }

    /// spec: docs/specs/workspace-folder.md S42
    @Test func aTabOpenedFromAnotherTakesItsWorkspaceNotTheSelectedOne() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        // t0 ("~") is selected, but the new tab is opened from t1 (Work): before any pass saw it,
        // and again after a pass put it in "~".
        _ = book.selected(t[0])
        _ = book.opened(t[2], from: t[1])
        _ = book.pass([[t[0], t[1], t[2]]], selected: [t[0]])
        #expect(book.workspace(of: t[2])?.id == work)
        _ = book.opened(t[3], from: t[0])
        _ = book.pass([[t[0], t[1], t[2], t[3]]], selected: [t[0]])
        _ = book.opened(t[3], from: t[1])
        #expect(book.names([t[0], t[1], t[2], t[3]]) == [WorkspaceSet.homeName, "Work"])
        #expect(book.runs(for: [t[0], t[1], t[2], t[3]])[1].tabs == [t[1], t[2], t[3]])
    }

    @Test func aTabOpenedFromAnotherIsPlacedBeforeThePassSeesIt() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
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
        let id = book.workspace(of: t[0])!.id
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
        let notes = book.newWorkspace("Notes", in: t[0])
        _ = book.edit(t[1]) { $0.join(t[1], to: notes) }
        #expect(book.names([t[0], t[1]]) == ["~", "Notes"])
        let home = book.workspace(of: t[0])!.id
        _ = book.edit(t[1]) { $0.join(t[1], to: home) }
        #expect(book.set(of: t[0])?.workspace(notes) == nil)
        #expect(book.names([t[0], t[1]]) == ["~"])
    }

    /// spec: docs/specs/workspace-folder.md S53
    @Test func aTabDroppedBetweenTwoTabsOfAWorkspaceDoesNotJoinIt() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]], [t[3]]])
        let tarn = book.newWorkspace("tarn", in: t[0])
        _ = book.edit(t[0]) { $0.join(t[0], to: tarn) }
        _ = book.edit(t[1]) { $0.join(t[1], to: tarn) }
        _ = book.selected(t[0])
        // t3 comes from the other window and lands between t0 and t1.
        _ = book.pass([[t[0], t[3], t[1], t[2]]], selected: [t[0]])
        let runs = book.runs(for: [t[0], t[3], t[1], t[2]])
        #expect(runs.map(\.workspace.name) == ["tarn", WorkspaceSet.homeName])
        #expect(runs[0].tabs == [t[0], t[1]])
        #expect(runs[1].tabs == [t[3], t[2]])
    }

    @Test func aTabInAFoldedWorkspaceUnfoldsItOnSelectionButNotOnRepeat() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let id = book.workspace(of: t[0])!.id
        _ = book.selected(t[1])
        _ = book.edit(t[0]) { $0.setCollapsed(id, true) }

        // The same tab becomes key again (the window regains focus): the fold stays.
        #expect(book.selected(t[1]) == nil)
        #expect(book.workspace(of: t[0])?.collapsed == true)
        // Another tab of the workspace is selected (cmd+1): it unfolds.
        #expect(book.selected(t[0]) != nil)
        #expect(book.workspace(of: t[0])?.collapsed == false)
    }

    @Test func aNewTabUnfoldsItsWorkspace() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        let id = book.workspace(of: t[0])!.id
        _ = book.edit(t[0]) { $0.setCollapsed(id, true) }
        _ = book.pass([[t[0], t[1]]], selected: [t[0]])
        #expect(book.workspace(of: t[1])?.collapsed == false)
    }

    @Test func aTabDraggedOutOfItsWindowStartsANewDefault() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1], t[2]]])
        // t2 leaves for its own window; t0 and t1 stay.
        _ = book.pass([[t[0], t[1]], [t[2]]])
        #expect(book.set(of: t[2])?.id != book.set(of: t[0])?.id)
        #expect(book.names([t[2]]) == [WorkspaceSet.homeName])
        #expect(book.names([t[0], t[1]]) == [WorkspaceSet.homeName])
        // The set the tab dragged out of a window starts gets a "~" with no folder too.
        #expect(book.workspace(of: t[2])?.folder == nil)
    }

    @Test func aTabDraggedToAnotherWindowJoinsHome() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2], t[3]]])
        let other = book.newWorkspace("Other", in: t[2])
        _ = book.edit(t[2]) { $0.join(t[2], to: other) }
        _ = book.selected(t[2])
        // t1 moves to the second window, after t3.
        _ = book.pass([[t[0]], [t[2], t[3], t[1]]], selected: [t[0], t[2]])
        #expect(book.workspace(of: t[1])?.name == WorkspaceSet.homeName)
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
