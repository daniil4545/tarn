import Foundation
import Testing
@testable import Ghostty

/// Workspace folders: path rules, the model, and the snapshot.
@Suite
struct WorkspaceFolderTests {
    private let t = (0..<4).map { _ in TabKey() }

    /// A temporary tree with `F` and a symlink `link` to `F`.
    private func tree() throws -> (root: String, folder: String, link: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tarn-folder-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("F")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        return (root.path, folder.path, link.path)
    }

    // spec: docs/specs/workspace-folder.md S26
    @Test func aSymlinkAndATrailingSlashGiveTheSameFolder() throws {
        let tree = try tree()
        defer { try? FileManager.default.removeItem(atPath: tree.root) }
        let real = try #require(WorkspaceFolder.standardized(tree.folder))
        #expect(WorkspaceFolder.standardized(tree.link) == real)
        #expect(WorkspaceFolder.standardized(tree.folder + "/") == real)
        #expect(WorkspaceFolder.standardized(tree.folder + "/../F") == real)
    }

    // spec: docs/specs/workspace-folder.md S26, S27
    @Test func anEmptyOrRelativePathHasNoFolder() {
        #expect(WorkspaceFolder.standardized("") == nil)
        #expect(WorkspaceFolder.standardized("relative/dir") == nil)
        #expect(WorkspaceFolder.standardized("~/code") == nil)
    }

    // spec: docs/specs/workspace-folder.md S26
    @Test func aPathThroughASymlinkLiesInsideTheRealFolder() throws {
        let tree = try tree()
        defer { try? FileManager.default.removeItem(atPath: tree.root) }
        let real = try #require(WorkspaceFolder.standardized(tree.folder))
        #expect(WorkspaceFolder.contains(real, tree.link + "/macos"))
        #expect(WorkspaceFolder.contains(real, "/private" + real))
    }

    // spec: docs/specs/workspace-folder.md S26
    @Test func containsComparesPathComponents() {
        #expect(WorkspaceFolder.contains("/a/F", "/a/F"))
        #expect(WorkspaceFolder.contains("/a/F", "/a/F/macos"))
        #expect(WorkspaceFolder.contains("/a/F/", "/a/F/macos/"))
        #expect(!WorkspaceFolder.contains("/a/F", "/a/F-old"))
        #expect(!WorkspaceFolder.contains("/a/F", "/a/F-old/x"))
        #expect(!WorkspaceFolder.contains("/a/F", "/a"))
    }

    @Test func theNameIsTheLastComponentAndHomeBecomesTilde() {
        #expect(WorkspaceFolder.name(of: "/Users/x/Dev/tarn") == "tarn")
        #expect(WorkspaceFolder.display("/Users/x/Dev/tarn", home: "/Users/x") == "~/Dev/tarn")
        #expect(WorkspaceFolder.display("/Users/xy/Dev", home: "/Users/x") == "/Users/xy/Dev")
        #expect(WorkspaceFolder.display("/opt/tarn", home: "/Users/x") == "/opt/tarn")
    }

    // spec: docs/specs/workspace-folder.md S3. Q1 and Q4 pick the workspace that holds the folder.
    @Test func theFirstTabOfTheWorkspaceWithTheFolderIsChosen() throws {
        var set = WorkspaceSet.makeDefault(tabs: [t[0], t[1]])
        let notes = try #require(set.create(name: "notes", folder: "/p/notes"))
        let tarn = try #require(set.create(name: "tarn", folder: "/p/tarn"))
        set.join(t[2], to: tarn)
        set.join(t[3], to: tarn)
        set.join(t[1], to: notes)
        let order = t
        #expect(set.firstTab(inFolder: "/p/tarn", order: order) == t[2])
        #expect(set.firstTab(inFolder: "/p/notes", order: order) == t[1])
        #expect(set.firstTab(inFolder: "/p/none", order: order) == nil)
        // Q4: the workspace being edited is skipped, so its own folder is no clash.
        #expect(set.firstTab(inFolder: "/p/tarn", order: order, except: tarn) == nil)
    }

    // spec: docs/specs/workspace-folder.md S22
    @Test func setFolderChangesOnlyTheFolder() throws {
        var set = WorkspaceSet.makeDefault(tabs: [t[0], t[1]])
        let id = set.workspaces[0].id
        let members = set.members
        let before = set.revision
        set.setFolder(id, "/p/tarn/")
        #expect(set.workspace(id)?.folder == "/p/tarn")
        #expect(set.members == members)
        #expect(set.revision == before + 1)
        set.setFolder(id, "/p/tarn")
        #expect(set.revision == before + 1, "the same folder is no change")
        set.setFolder(id, "relative")
        #expect(set.workspace(id)?.folder == "/p/tarn", "a relative path changes nothing")
        set.setFolder(id, nil)
        #expect(set.workspace(id)?.folder == nil)
        #expect(set.revision == before + 2)
        set.setFolder(id, nil)
        #expect(set.revision == before + 2)
    }

    @Test func createWithARelativeFolderIsRefused() {
        var set = WorkspaceSet()
        #expect(set.create(name: "x", folder: "relative") == nil)
        #expect(set.workspaces.isEmpty)
    }

    // spec: docs/specs/workspace-folder.md S21
    @Test func aSnapshotKeepsTheFolderThroughEncoding() throws {
        var set = WorkspaceSet.makeDefault(tabs: [t[0]])
        let tarn = try #require(set.create(name: "tarn", folder: "/p/tarn"))
        set.join(t[1], to: tarn)
        let data = try WorkspaceSnapshot(set: set, tabKey: t[0], order: [t[0], t[1]]).encoded()
        let back = try WorkspaceSnapshot.decode(data).makeSet()
        #expect(back.workspace(tarn)?.folder == "/p/tarn")
        #expect(back.workspace(of: t[0])?.folder == nil)
    }

    // spec: docs/specs/workspace-folder.md S21. A snapshot saved before folders has no such key.
    @Test func anOldSnapshotWithoutTheFieldDecodesWithNoFolder() throws {
        let id = UUID()
        let json = """
        {"version":1,"setID":"\(UUID())","revision":3,"tabKey":"\(t[0])",
         "workspaces":[{"id":"\(id)","name":"Default","collapsed":false,"tabKeys":["\(t[0])"]}]}
        """
        let set = try WorkspaceSnapshot.decode(Data(json.utf8)).makeSet()
        #expect(set.workspace(id)?.name == "Default")
        #expect(set.workspace(id)?.folder == nil)
        #expect(WorkspaceBook().isPlain(set))
    }

    @Test func isPlainTakesBothNamesAndNoFolder() throws {
        let book = WorkspaceBook()
        var set = WorkspaceSet.makeDefault(tabs: [t[0]])
        #expect(set.workspaces[0].name == "No project")
        #expect(book.isPlain(set))
        let id = set.workspaces[0].id
        #expect(set.rename(id, to: "Default"))
        #expect(book.isPlain(set))
        #expect(set.rename(id, to: "Work"))
        #expect(!book.isPlain(set))
        #expect(set.rename(id, to: "No project"))
        set.setFolder(id, "/p/tarn")
        #expect(!book.isPlain(set))
        set.setFolder(id, nil)
        _ = set.create(name: "Second")
        #expect(!book.isPlain(set))
    }
}
