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
        #expect(book.names([t[0]]) == [WorkspaceSet.defaultName])
        #expect(outcome.reorders.isEmpty)
        #expect(outcome.changed.count == 1)
    }

    @Test func aSecondWindowGetsItsOwnDefault() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        _ = book.pass([[t[0]], [t[1]]])
        #expect(book.set(of: t[0])?.id != book.set(of: t[1])?.id)
        #expect(book.names([t[1]]) == [WorkspaceSet.defaultName])
    }

    @Test func aNewTabJoinsTheWorkspaceOfTheSelectedTab() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        _ = book.newWorkspace("Work", in: t[0])
        // Select t0 (Default), then a new tab appears: it goes to Default.
        _ = book.selected(t[0])
        _ = book.pass([[t[0], t[1]]], selected: [t[1]])
        #expect(book.workspace(of: t[1])?.name == WorkspaceSet.defaultName)
    }

    @Test func aPendingTargetWinsOverTheSelection() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.selected(t[0])
        book.setPendingTarget(work, for: t[0])
        let outcome = book.pass([[t[0], t[2], t[1]]], selected: [t[2]])
        #expect(book.workspace(of: t[2])?.id == work)
        // t2 sits before t1, the last tab of Work: it moves one place down.
        #expect(outcome.reorders == [.init(tab: t[2], delta: 1)])
    }

    @Test func aPendingTargetIsUsedOnce() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let work = book.newWorkspace("Work", in: t[0])
        _ = book.edit(t[1]) { $0.join(t[1], to: work) }
        _ = book.selected(t[0])
        book.setPendingTarget(work, for: t[0])
        _ = book.pass([[t[0], t[1], t[2]]], selected: [t[0]])
        _ = book.pass([[t[0], t[1], t[2], t[3]]], selected: [t[0]])
        #expect(book.workspace(of: t[3])?.name == WorkspaceSet.defaultName)
    }

    @Test func aNewWorkspaceHoldsItsFirstTabAndOpensAtTheEnd() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]]])
        let fresh = book.newWorkspace("Notes", in: t[0])
        book.setPendingTarget(fresh, for: t[0])
        // Between the command and the tab, a pass must not drop the empty workspace.
        _ = book.pass([[t[0], t[1]]])
        #expect(book.set(of: t[0])?.workspace(fresh) != nil)

        let outcome = book.pass([[t[0], t[2], t[1]]], selected: [t[2]])
        #expect(book.names([t[0], t[1], t[2]]) == ["Default", "Notes"])
        #expect(outcome.reorders == [.init(tab: t[2], delta: 1)])
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
        #expect(book.names([t[2]]) == [WorkspaceSet.defaultName])
        #expect(book.names([t[0], t[1]]) == [WorkspaceSet.defaultName])
    }

    @Test func aTabDraggedToAnotherWindowJoinsItsCurrentWorkspace() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0], t[1]], [t[2], t[3]]])
        let other = book.newWorkspace("Other", in: t[2])
        _ = book.edit(t[2]) { $0.join(t[2], to: other) }
        _ = book.selected(t[2])
        // t1 moves to the second window, after t3.
        _ = book.pass([[t[0]], [t[2], t[3], t[1]]], selected: [t[0], t[2]])
        #expect(book.workspace(of: t[1])?.id == other)
        #expect(book.names([t[0]]) == [WorkspaceSet.defaultName])
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
struct TargetExpiryTests {
    private let t = (0..<4).map { _ in TabKey() }

    @Test func aTargetNobodyUsedStopsSteeringLaterTabs() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        let other = book.newWorkspace("Other", in: t[0])
        book.setPendingTarget(other, for: t[0])
        let first = book.clearPendingTarget(for: t[0])
        let second = book.clearPendingTarget(for: t[0])
        #expect(first)
        #expect(!second)
        _ = book.pass([[t[0], t[1]]], selected: [t[0]])
        #expect(book.workspace(of: t[1])?.name == WorkspaceSet.defaultName)
    }

    @Test func anEmptyWorkspaceMadeForATabThatNeverCameIsRemoved() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        let created = book.newWorkspace("Ghost", in: t[0])
        book.setPendingTarget(created, for: t[0])
        _ = book.pass([[t[0]]])
        #expect(book.set(of: t[0])?.workspace(created) != nil)
        _ = book.clearPendingTarget(for: t[0])
        _ = book.pass([[t[0]]])
        #expect(book.set(of: t[0])?.workspace(created) == nil)
    }

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
