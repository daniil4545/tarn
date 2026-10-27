import Foundation
import Testing
@testable import Ghostty

/// Where a new tab or split starts in a workspace with a folder (D20).
@Suite
struct StartDirectoryTests {
    private let t = (0..<3).map { _ in TabKey() }
    private let folder = "/p/F"
    private let always: (String) -> Bool = { _ in true }

    /// A book with "No project" holding t0 and "tarn" (folder `F`) holding t1.
    private func makeBook() -> (book: WorkspaceBook, tarn: Workspace.ID) {
        var book = WorkspaceBook()
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
        #expect(book.folderForNewSurface(from: t[0], split: false) == nil)
        #expect(book.folderForNewSurface(from: t[0], split: true) == nil)
    }

    // spec: docs/specs/workspace-folder.md S4
    @Test func aNewTabLandsInTheWorkspaceOfTheSelectedTab() {
        var (book, _) = makeBook()
        _ = book.selected(t[1])
        #expect(book.folderForNewSurface(from: t[1], split: false) == folder)
    }

    // spec: docs/specs/workspace-folder.md S6
    @Test func thePendingTargetOfThePlusPicksTheFolder() {
        var (book, tarn) = makeBook()
        _ = book.selected(t[0])
        book.setPendingTarget(tarn, for: t[0])
        #expect(book.folderForNewSurface(from: t[0], split: false) == folder)
        let cleared = book.clearPendingTarget(for: t[0])
        #expect(cleared)
        #expect(book.folderForNewSurface(from: t[0], split: false) == nil)
    }

    // spec: docs/specs/workspace-folder.md S7
    @Test func aSplitFollowsItsSourceTabAndIgnoresThePendingTarget() {
        var (book, tarn) = makeBook()
        _ = book.selected(t[0])
        book.setPendingTarget(tarn, for: t[0])
        #expect(book.folderForNewSurface(from: t[0], split: true) == nil)
        #expect(book.folderForNewSurface(from: t[1], split: true) == folder)
    }

    // spec: docs/specs/workspace-folder.md S29
    @Test func aNewTabAfterAMoveStartsInTheNewWorkspace() {
        var (book, tarn) = makeBook()
        _ = book.selected(t[0])
        #expect(book.folderForNewSurface(from: t[0], split: false) == nil)
        _ = book.edit(t[0]) { $0.join(t[0], to: tarn) }
        _ = book.selected(t[0])
        #expect(book.folderForNewSurface(from: t[0], split: false) == folder)
    }

    @Test func anUnknownTabHasNoFolder() {
        #expect(WorkspaceBook().folderForNewSurface(from: t[2], split: false) == nil)
    }
}
