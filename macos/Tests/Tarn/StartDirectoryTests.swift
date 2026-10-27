import AppKit
import Testing
@testable import Ghostty

/// Where a new tab or split starts in a workspace with a folder (D20).
@Suite
struct StartDirectoryTests {
    private let t = (0..<3).map { _ in TabKey() }
    private let folder = "/p/F"
    private let always: (String) -> Bool = { _ in true }

    /// A book with a restored folderless "No project" holding t0 and "tarn" (folder `F`) holding t1.
    private func makeBook() -> (book: WorkspaceBook, tarn: Workspace.ID) {
        var book = WorkspaceBook()
        book.restoreLegacy([t[0], t[1]])
        _ = book.pass([[t[0], t[1]]])
        var tarn: Workspace.ID?
        _ = book.edit(t[0]) { tarn = $0.create(name: "tarn", folder: "/p/F") }
        _ = book.edit(t[1]) { $0.join(t[1], to: tarn!) }
        return (book, tarn!)
    }

    // spec: docs/specs/workspace-folder.md S4
    @Test func aDirectoryInsideTheFolderStays() {
        #expect(WorkspaceFolder.startDirectory(inherited: "/p/F/macos", folder: folder, exists: always) == "/p/F/macos")
        #expect(WorkspaceFolder.startDirectory(inherited: "/p/F", folder: folder, exists: always) == "/p/F")
    }

    // spec: docs/specs/workspace-folder.md S5
    @Test func aDirectoryOutsideTheFolderGivesTheFolder() {
        #expect(WorkspaceFolder.startDirectory(inherited: "/p/other", folder: folder, exists: always) == folder)
        #expect(WorkspaceFolder.startDirectory(inherited: "/p/F-old", folder: folder, exists: always) == folder)
    }

    // spec: docs/specs/workspace-folder.md S8
    @Test func noFolderLeavesTheInheritedDirectory() {
        #expect(WorkspaceFolder.startDirectory(inherited: "/p/other", folder: nil, exists: always) == "/p/other")
        #expect(WorkspaceFolder.startDirectory(inherited: nil, folder: nil, exists: always) == nil)
    }

    // spec: docs/specs/workspace-folder.md S9
    @Test func aFolderGoneFromDiskLeavesTheInheritedDirectory() {
        #expect(WorkspaceFolder.startDirectory(inherited: "/p/other", folder: folder, exists: { _ in false }) == "/p/other")
        #expect(WorkspaceFolder.startDirectory(inherited: nil, folder: folder, exists: { _ in false }) == nil)
    }

    // spec: docs/specs/workspace-folder.md S10
    @Test func withoutInheritanceTheFolderIsTheStart() {
        #expect(WorkspaceFolder.startDirectory(inherited: nil, folder: folder, exists: always) == folder)
    }

    // spec: docs/specs/workspace-folder.md S4, S26
    @Test func aLogicalPathThroughASymlinkStaysInsideTheRealFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tarn-start-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("F/macos")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("F"))
        let folder = try #require(WorkspaceFolder.standardized(root.appendingPathComponent("F").path))
        let inherited = link.path + "/macos"
        #expect(WorkspaceFolder.startDirectory(inherited: inherited, folder: folder, exists: always) == inherited)
    }

    // spec: docs/specs/workspace-folder.md S8
    @Test func aTabInAFolderlessWorkspaceHasNoFolder() {
        let (book, _) = makeBook()
        #expect(book.folderForNewSurface(from: t[0], order: t, split: false) == nil)
        #expect(book.folderForNewSurface(from: t[0], order: t, split: true) == nil)
    }

    // spec: docs/specs/workspace-folder.md S4
    @Test func aNewTabLandsInTheWorkspaceOfTheSelectedTab() {
        var (book, _) = makeBook()
        _ = book.selected(t[1])
        #expect(book.folderForNewSurface(from: t[1], order: t, split: false) == folder)
    }

    // spec: docs/specs/workspace-folder.md S6
    @Test func thePendingTargetOfThePlusPicksTheFolder() {
        var (book, tarn) = makeBook()
        _ = book.selected(t[0])
        book.setPendingTarget(tarn, for: t[0])
        #expect(book.folderForNewSurface(from: t[0], order: t, split: false) == folder)
        let cleared = book.clearPendingTarget(for: t[0])
        #expect(cleared)
        #expect(book.folderForNewSurface(from: t[0], order: t, split: false) == nil)
    }

    // spec: docs/specs/workspace-folder.md S7
    @Test func aSplitFollowsItsSourceTabAndIgnoresThePendingTarget() {
        var (book, tarn) = makeBook()
        _ = book.selected(t[0])
        book.setPendingTarget(tarn, for: t[0])
        #expect(book.folderForNewSurface(from: t[0], order: t, split: true) == nil)
        #expect(book.folderForNewSurface(from: t[1], order: t, split: true) == folder)
    }

    /// The selected tab's workspace was deleted: membership falls back to the top workspace of
    /// the window, so the folder does too, not the workspace the tab moved into.
    @Test func aDeletedLastSelectedWorkspaceGivesTheTopFolderAsMembershipDoes() throws {
        var book = WorkspaceBook()
        book.restoreLegacy(t)
        _ = book.pass([t])
        var tarn: Workspace.ID?
        var notes: Workspace.ID?
        _ = book.edit(t[0]) {
            tarn = $0.create(name: "tarn", folder: folder)
            notes = $0.create(name: "notes", folder: "/p/N")
        }
        let tarnID = try #require(tarn)
        let notesID = try #require(notes)
        _ = book.edit(t[0]) {
            $0.join(t[1], to: tarnID)
            $0.join(t[2], to: notesID)
        }
        _ = book.selected(t[2])
        _ = book.edit(t[0]) { _ = $0.delete(notesID, order: t) }
        #expect(book.folderForNewSurface(from: t[2], order: t, split: true) == folder, "t2 moved into tarn")
        #expect(book.folderForNewSurface(from: t[2], order: t, split: false) == nil, "top is No project, not tarn")
        #expect(book.folderForNewSurface(from: t[2], order: [t[1], t[2], t[0]], split: false) == folder, "top is tarn")
    }

    // spec: docs/specs/workspace-folder.md S34
    @Test func aTabThatOpensAWindowKeepsItsConfig() {
        #expect(!WorkspaceRegistry.landsInWorkspace(split: false, tabbingMode: .disallowed))
        #expect(WorkspaceRegistry.landsInWorkspace(split: true, tabbingMode: .disallowed))
        #expect(WorkspaceRegistry.landsInWorkspace(split: false, tabbingMode: .preferred))
        #expect(WorkspaceRegistry.landsInWorkspace(split: false, tabbingMode: .automatic))
    }

    // spec: docs/specs/workspace-folder.md D20, D24 (T-245)
    @Test func aTabInTheStartWorkspaceStartsInTheHomeFolder() {
        var book = WorkspaceBook()
        _ = book.pass([[t[0]]])
        #expect(book.folderForNewSurface(from: t[0], order: [t[0]], split: false) == WorkspaceBook.expectedHome)
        #expect(book.folderForNewSurface(from: t[0], order: [t[0]], split: true) == WorkspaceBook.expectedHome)
        #expect(WorkspaceBook.expectedHome != nil)
    }

    @Test func anUnknownTabHasNoFolder() {
        #expect(WorkspaceBook().folderForNewSurface(from: t[2], order: t, split: false) == nil)
    }
}
