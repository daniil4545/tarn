import Foundation
import Testing
import WebKit
@testable import Ghostty

/// Tab rules, path resolution and document conflicts of the viewer pane (`docs/plans/s2-files.md`).
@Suite
struct ViewerTabsTests {
    @Test func nextOpenReplacesThePreviewTab() {
        var tabs = ViewerTabs()
        tabs.open("/a.md")
        tabs.open("/b.md")
        #expect(tabs.tabs.map(\.path) == ["/b.md"])
        #expect(tabs.tabs[0].preview)
    }

    @Test func pinnedTabStaysAndNextOpenAddsATab() {
        var tabs = ViewerTabs()
        tabs.open("/a.md")
        tabs.pin(at: 0)
        tabs.open("/b.md")
        #expect(tabs.tabs.map(\.path) == ["/a.md", "/b.md"])
        #expect(tabs.tabs.map(\.preview) == [false, true])
        #expect(tabs.activePath == "/b.md")
    }

    @Test func openingAnOpenPathActivatesItAndPinOnOpenKeepsIt() {
        var tabs = ViewerTabs()
        tabs.open("/a.md", pin: true)
        tabs.open("/b.md", pin: true)
        tabs.open("/a.md")
        #expect(tabs.tabs.count == 2)
        #expect(tabs.activePath == "/a.md")
        #expect(!tabs.tabs[0].preview)
    }

    @Test func anEditPinsThePreviewTab() {
        var tabs = ViewerTabs()
        tabs.open("/a.md")
        tabs.pin(path: "/a.md")
        #expect(!tabs.tabs[0].preview)
    }

    @Test func lineOpensGrowTheJumpToken() {
        var tabs = ViewerTabs()
        tabs.open("/a.swift", line: 3)
        let first = tabs.tabs[0].jump
        tabs.open("/a.swift", line: 3)
        #expect(tabs.tabs[0].line == 3)
        #expect(tabs.tabs[0].jump > first)
    }

    @Test func closingTabsMovesTheActiveOneAndEmptiesThePane() {
        var tabs = ViewerTabs()
        for name in ["/a", "/b", "/c"] { tabs.open(name, pin: true) }
        tabs.close(at: 0)
        #expect(tabs.activePath == "/c")
        tabs.close(at: 1)
        #expect(tabs.activePath == "/b")
        tabs.close(at: 0)
        #expect(tabs.tabs.isEmpty)
    }

    @Test func backgroundOpenKeepsTheActiveTab() {
        var tabs = ViewerTabs()
        tabs.open("/a.md")
        tabs.open("/b.md", background: true)
        #expect(tabs.activePath == "/a.md")
        #expect(tabs.tabs.map(\.path) == ["/a.md", "/b.md"])
        #expect(tabs.tabs[1].preview == false)

        var empty = ViewerTabs()
        empty.open("/a.md", background: true)
        #expect(empty.activePath == "/a.md")
    }
}

@Suite
struct ViewerPathsTests {
    private func resolve(_ raw: String, cwd: String? = "/work/app", existing: Set<String> = []) -> OpenTarget? {
        ViewerPaths.resolve(raw, cwd: cwd, home: "/Users/me") { existing.contains($0) }
    }

    @Test func resolvesAbsoluteHomeAndRelativePaths() {
        #expect(resolve("/etc/hosts") == OpenTarget(path: "/etc/hosts", line: nil))
        #expect(resolve("~/notes.md") == OpenTarget(path: "/Users/me/notes.md", line: nil))
        #expect(resolve("docs/spec.md") == OpenTarget(path: "/work/app/docs/spec.md", line: nil))
        #expect(resolve("./a/../b.md") == OpenTarget(path: "/work/app/b.md", line: nil))
        #expect(resolve("file:///tmp/x.md") == OpenTarget(path: "/tmp/x.md", line: nil))
    }

    @Test func splitsLineAndColumn() {
        #expect(resolve("docs/spec.md:12") == OpenTarget(path: "/work/app/docs/spec.md", line: 12))
        #expect(resolve("a.zig:7:3") == OpenTarget(path: "/work/app/a.zig", line: 7))
    }

    @Test func aFileWhoseNameHasAColonWinsOverTheSplit() {
        let target = resolve("a:12", existing: ["/work/app/a:12"])
        #expect(target == OpenTarget(path: "/work/app/a:12", line: nil))
    }

    @Test func relativePathWithoutCwdIsNotResolved() {
        #expect(resolve("a.md", cwd: nil) == nil)
    }

    @Test func tellsUrlsFromPaths() {
        #expect(ViewerPaths.isURL("https://example.com"))
        #expect(ViewerPaths.isURL("mailto:a@b.c"))
        #expect(!ViewerPaths.isURL("spec.md:12"))
        #expect(!ViewerPaths.isURL("file:///tmp/a.md"))
    }

    @Test func classifiesFiles() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try "x".write(toFile: dir + "/a.md", atomically: true, encoding: .utf8)
        try "x".write(toFile: dir + "/b.png", atomically: true, encoding: .utf8)
        try "x".write(toFile: dir + "/c.pdf", atomically: true, encoding: .utf8)
        try "x".write(toFile: dir + "/d.svg", atomically: true, encoding: .utf8)
        try "x".write(toFile: dir + "/Makefile", atomically: true, encoding: .utf8)
        #expect(ViewerPaths.classify(dir + "/a.md") == .text)
        #expect(ViewerPaths.classify(dir + "/b.png") == .system)
        #expect(ViewerPaths.classify(dir + "/c.pdf") == .system)
        #expect(ViewerPaths.classify(dir + "/d.svg") == .text)
        #expect(ViewerPaths.classify(dir + "/Makefile") == .text)
        try FileManager.default.createSymbolicLink(atPath: dir + "/link.md", withDestinationPath: dir + "/a.md")
        #expect(ViewerPaths.classify(dir + "/link.md") == .text)
        #expect(ViewerPaths.classify(dir) == .directory)
        #expect(ViewerPaths.classify(dir + "/nope") == .missing)
    }

    @Test func binaryIsDecidedByContent() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        func write(_ name: String, _ data: Data) -> String {
            let path = dir + "/" + name
            FileManager.default.createFile(atPath: path, contents: data)
            return path
        }
        #expect(ViewerPaths.isBinary(write("nul", Data([0x61, 0x00, 0x62]))))
        #expect(ViewerPaths.isBinary(write("bad", Data([0xFF, 0xFE, 0x41]))))
        #expect(!ViewerPaths.isBinary(write("text", Data("plain \u{e9} text\n".utf8))))
        #expect(!ViewerPaths.isBinary(write("empty", Data())))
        // A two-byte character cut by the 8 KB edge stays text.
        let cut = Data(repeating: 0x61, count: 8191) + Data("\u{e9}".utf8) + Data(repeating: 0x61, count: 100)
        #expect(!ViewerPaths.isBinary(write("cut", cut)))
        #expect(ViewerPaths.isBinary("/bin/ls"))
        #expect(!ViewerPaths.isBinary(dir + "/missing"))
    }

    @Test func sourceFilesAreTextAndSpecialFilesAreNeverRead() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for ext in ["ts", "mts", "mod", "sh", "py", "rs", "go", "json", "yaml", "toml", "swift", "c", "h", "jar", "command", "zig"] {
            try "x".write(toFile: dir + "/f." + ext, atomically: true, encoding: .utf8)
            #expect(ViewerPaths.classify(dir + "/f." + ext) == .text, "\(ext)")
        }
        #expect(ViewerPaths.classify("/dev/null") == .special)
        #expect(ViewerPaths.classify("/dev/zero") == .special)
        #expect(mkfifo(dir + "/pipe", 0o600) == 0)
        #expect(ViewerPaths.classify(dir + "/pipe") == .special)
    }
}

@Suite
struct ViewerDocumentTests {
    private func document(_ text: String) throws -> (ViewerDocument, String, String) {
        let dir = try Scratch.make()
        let path = dir + "/doc.md"
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return (try #require(ViewerDocument(path: path)), path, dir)
    }

    private func rewrite(_ path: String, _ text: String) throws {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        // Same-size rewrites inside one timestamp tick still differ by a later date.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: path)
    }

    @Test func cleanDocumentReloadsOnADiskChange() throws {
        var (doc, path, dir) = try document("one")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try rewrite(path, "two")
        #expect(doc.diskChanged(FileRead.read(path)) == .reloaded)
        #expect(doc.text == "two")
        #expect(doc.revision == 2)
        #expect(doc.diskChanged(FileRead.read(path)) == .none)
    }

    @Test func editedDocumentGetsAConflictOnceAndTakeDiskResolvesIt() throws {
        var (doc, path, dir) = try document("one")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        doc.edit("mine")
        try rewrite(path, "agent")
        #expect(doc.diskChanged(FileRead.read(path)) == .conflict)
        #expect(doc.text == "mine")
        #expect(doc.diskChanged(FileRead.read(path)) == .none)
        doc.takeDisk()
        #expect(doc.text == "agent")
        #expect(!doc.conflict && !doc.isDirty)
    }

    @Test func keepMineClearsTheBannerAndStaysDirty() throws {
        var (doc, path, dir) = try document("one")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        doc.edit("mine")
        try rewrite(path, "agent")
        _ = doc.diskChanged(FileRead.read(path))
        doc.keepMine()
        #expect(!doc.conflict)
        #expect(doc.text == "mine" && doc.isDirty)
        #expect(doc.diskChanged(FileRead.read(path)) == .none)
    }

    @Test func savingSetsTheNewFingerprintSoOurOwnWriteIsNotAChange() throws {
        var (doc, path, dir) = try document("one")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        doc.edit("mine")
        try "mine".write(toFile: path, atomically: true, encoding: .utf8)
        doc.saved(stamp: FileStamp.of(path))
        #expect(!doc.isDirty)
        #expect(doc.diskChanged(FileRead.read(path)) == .none)
    }

    @Test func deletedFileKeepsTheTextAndReportsOnce() throws {
        var (doc, path, dir) = try document("one")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.removeItem(atPath: path)
        #expect(doc.diskChanged(FileRead.read(path)) == .deleted)
        #expect(doc.diskChanged(FileRead.read(path)) == .none)
        #expect(doc.text == "one")
    }

    @Test func bigAndNonUtf8FilesGetANotice() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: URL(fileURLWithPath: dir + "/bin.txt"))
        let big = Data(repeating: 0x61, count: FileRead.maxBytes + 1)
        try big.write(to: URL(fileURLWithPath: dir + "/big.txt"))
        guard case .notice = ViewerDocument(path: dir + "/bin.txt")?.content else { Issue.record("no notice"); return }
        guard case .notice = ViewerDocument(path: dir + "/big.txt")?.content else { Issue.record("no notice"); return }
    }

    @Test func taskToggleWritesTheMarkerOnItsLineOnly() {
        let text = "# T\n\n- [ ] one\n- [x] two\n\n```\n- [ ] in fence\n```\n> - [ ] quoted\n1. [ ] numbered\n"
        #expect(TaskList.set(text, line: 2, checked: true) == text.replacingOccurrences(of: "- [ ] one", with: "- [x] one"))
        #expect(TaskList.set(text, line: 3, checked: false) == text.replacingOccurrences(of: "- [x] two", with: "- [ ] two"))
        #expect(TaskList.set(text, line: 8, checked: true)?.contains("> - [x] quoted") == true)
        #expect(TaskList.set(text, line: 9, checked: true)?.contains("1. [x] numbered") == true)
        #expect(TaskList.set(text, line: 0, checked: true) == nil)
        #expect(TaskList.set(text, line: 99, checked: true) == nil)
    }
}

@Suite
struct ViewerRulesTests {
    @Test func ruleListBlocksEverythingButTheOwnScheme() throws {
        let rules = try #require(JSONSerialization.jsonObject(with: Data(ViewerRules.contentRuleListJSON.utf8)) as? [[String: Any]])
        #expect(rules.count == 2)
        let block = try #require(rules[0]["action"] as? [String: String])
        #expect(block["type"] == "block")
        #expect((rules[0]["trigger"] as? [String: String])?["url-filter"] == ".*")
        #expect((rules[1]["action"] as? [String: String])?["type"] == "ignore-previous-rules")
        #expect((rules[1]["trigger"] as? [String: String])?["url-filter"] == "^tarn-md:")
    }

    @Test func ruleListCompilesInWebKit() async throws {
        let list = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "tarn-viewer-test", encodedContentRuleList: ViewerRules.contentRuleListJSON)
        #expect(list != nil)
    }

    @Test func servesOnlyBundleAssetsAndImagesUnderTheRoots() throws {
        let bundle = URL(fileURLWithPath: "/bundle")
        let roots = ["/work/app"]
        func asset(_ text: String) -> ViewerRules.Asset? {
            ViewerRules.asset(for: URL(string: text)!, bundle: bundle, roots: roots)
        }
        #expect(asset("tarn-md://app/tarn-viewer.js")?.file.path == "/bundle/tarn-viewer.js")
        #expect(asset("tarn-md://app/tarn-viewer.js")?.mimeType == "text/javascript")
        #expect(asset("tarn-md://app/other.js") == nil)
        #expect(asset("tarn-md://file/work/app/img/a.png")?.mimeType == "image/png")
        #expect(asset("tarn-md://file/work/app/../secret/a.png") == nil)
        #expect(asset("tarn-md://file/work/application/a.png") == nil)
        #expect(asset("tarn-md://file/work/app/notes.md") == nil)
        #expect(asset("tarn-md://file/etc/passwd") == nil)
        #expect(asset("https://example.com/a.png") == nil)
        #expect(asset("tarn-md://other/x") == nil)
    }
}

@Suite
struct FileTreeTests {
    @Test func listsFoldersFirstHidesNoiseAndUnfoldsOnDemand() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let manager = FileManager.default
        try manager.createDirectory(atPath: dir + "/docs", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: dir + "/.git", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: dir + "/node_modules", withIntermediateDirectories: true)
        try "x".write(toFile: dir + "/docs/a.md", atomically: true, encoding: .utf8)
        try "x".write(toFile: dir + "/b.md", atomically: true, encoding: .utf8)

        var tree = FileTree(root: dir)
        #expect(tree.rows().map(\.name) == ["docs", "b.md"])
        tree.toggle(dir + "/docs")
        #expect(tree.rows().map(\.name) == ["docs", "a.md", "b.md"])
        #expect(tree.rows()[1].depth == 1)
        tree.toggle(dir + "/docs")
        tree.reveal(dir + "/docs/a.md")
        #expect(tree.rows().map(\.name) == ["docs", "a.md", "b.md"])
    }
}

private enum Scratch {
    static func make() throws -> String {
        let dir = NSTemporaryDirectory() + "tarn-viewer-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Unsaved edits when a window or the app closes (`ViewerClose`).
@Suite
@MainActor
struct ViewerCloseTests {
    private func model(editing names: [String: String]) throws -> (ViewerModel, String) {
        let dir = try Scratch.make()
        let model = ViewerModel(root: dir)
        for (name, edit) in names.sorted(by: { $0.key < $1.key }) {
            let path = dir + "/" + name
            try "one".write(toFile: path, atomically: true, encoding: .utf8)
            model.open(OpenTarget(path: path), pin: true)
            if !edit.isEmpty { model.handle(["t": "edit", "path": path, "text": edit, "rev": 1]) }
        }
        return (model, dir)
    }

    @Test func aDraggedTabMovesToAnotherViewerWithItsEdits() throws {
        let (source, dir) = try model(editing: ["a.md": "x", "b.md": ""])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let destination = ViewerModel(root: dir)
        #expect(destination.canTake(dir + "/a.md", from: source))
        destination.take(dir + "/a.md", from: source)
        source.release(dir + "/a.md")
        #expect(destination.dirtyPaths == [dir + "/a.md"])
        #expect(source.dirtyPaths.isEmpty)
        #expect(source.snapshot.map(\.path) == [dir + "/b.md"])
        source.release(dir + "/b.md")
        #expect(source.isEmpty)
    }

    private func pair(source: String, target: String) throws -> (ViewerModel, ViewerModel, String) {
        let (src, dir) = try model(editing: ["a.md": source])
        let dst = ViewerModel(root: dir)
        dst.open(OpenTarget(path: dir + "/a.md"), pin: true)
        if !target.isEmpty { dst.handle(["t": "edit", "path": dir + "/a.md", "text": target, "rev": 1]) }
        return (src, dst, dir)
    }

    @Test func absorbKeepsTheSourceEditsWhenOnlyTheSourceHasThem() throws {
        let (src, dst, dir) = try pair(source: "src", target: "")
        let path = dir + "/a.md"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(dst.canAbsorb(src))
        dst.absorb(src)
        #expect(dst.dirtyPaths == [path])
        #expect(dst.snapshot.count == 1)
    }

    @Test func absorbKeepsTheTargetEditsWhenOnlyTheTargetHasThem() throws {
        let (src, dst, dir) = try pair(source: "", target: "dst")
        let path = dir + "/a.md"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(dst.canAbsorb(src))
        dst.absorb(src)
        #expect(dst.dirtyPaths == [path])
        #expect(dst.snapshot.count == 1)
    }

    @Test func absorbRefusesTwoDifferentEditsAndChangesNothing() throws {
        let (src, dst, dir) = try pair(source: "src", target: "dst")
        let path = dir + "/a.md"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(!dst.canAbsorb(src))
        #expect(!dst.canTake(path, from: src))
        #expect(src.dirtyPaths == [path])
        #expect(dst.dirtyPaths == [path])
    }

    @Test func absorbMergesEqualEditsIntoOne() throws {
        let (src, dst, dir) = try pair(source: "same", target: "same")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(dst.canAbsorb(src))
        dst.absorb(src)
        #expect(dst.snapshot.count == 1)
    }

    @Test func aTreeRowFileOpensFromDiskInTheDestination() throws {
        let (source, dir) = try model(editing: [:])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try "one".write(toFile: dir + "/t.md", atomically: true, encoding: .utf8)
        let destination = ViewerModel(root: dir)
        destination.take(dir + "/t.md", from: source)
        #expect(destination.snapshot.map(\.path) == [dir + "/t.md"])
    }

    @Test func collectsOnlyDirtyFilesInTabOrder() throws {
        let (model, dir) = try model(editing: ["a.md": "x", "b.md": "", "c.md": "y"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(model.dirtyPaths == [dir + "/a.md", dir + "/c.md"])
    }

    @Test func dirtyPathsOfSeveralPanesHaveNoRepeats() throws {
        let (first, dir) = try model(editing: ["a.md": "x"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let second = ViewerModel(root: dir)
        second.open(OpenTarget(path: dir + "/a.md"), pin: true)
        second.handle(["t": "edit", "path": dir + "/a.md", "text": "z", "rev": 1])
        #expect(ViewerClose.dirtyPaths(in: [first, second]) == [dir + "/a.md"])
    }

    @Test func saveAllWritesTheFilesAndClearsTheFlags() throws {
        let (model, dir) = try model(editing: ["a.md": "x", "b.md": "y"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(model.saveAll())
        #expect(model.dirtyPaths.isEmpty)
        #expect(try String(contentsOfFile: dir + "/a.md", encoding: .utf8) == "x")
        #expect(try String(contentsOfFile: dir + "/b.md", encoding: .utf8) == "y")
    }

    @Test func dontSaveKeepsTheEditsAndSkipsTheQuestionOnce() throws {
        let (model, dir) = try model(editing: ["a.md": "x"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(ViewerClose.unsettled([model]).count == 1)
        // Don't Save, then the repeated close passes once.
        model.discardOnce = true
        #expect(ViewerClose.unsettled([model]).isEmpty)
        // Ghostty's own dialog was cancelled: the edits are intact and the next close asks again.
        #expect(model.dirtyPaths == [dir + "/a.md"])
        #expect(ViewerClose.unsettled([model]).count == 1)
        #expect(try String(contentsOfFile: dir + "/a.md", encoding: .utf8) == "one")
    }

    /// Every direct close of a window or tab must be reachable only after `ViewerClose.intercept`.
    /// A new call site fails this test until it is reviewed and listed here.
    @Test func directClosesAreAllReviewed() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let reviewed: [String: Int] = [
            // callers behind ViewerClose.intercept, plus undo and redo (asked at the original close)
            "TerminalController.swift": 19,
            "ScriptWindow.swift": 2,
            "ScriptTab.swift": 2,
            "Sidebar.swift": 1, // Close Other / Below, behind ViewerClose.intercept (Sidebar.close(_:title:from:))
        ]
        var found: [String: Int] = [:]
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let count = text.components(separatedBy: "closeWindowImmediately(").count - 1
                + text.components(separatedBy: "closeTabImmediately(").count - 1
            if count > 0 { found[url.lastPathComponent] = count }
        }
        #expect(found == reviewed)
    }

    @Test func discardMarkIsOnlyInForceDuringTheRepeatedCloseAndNeverLeftBehind() throws {
        let (model, dir) = try model(editing: ["a.md": "x"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        var askedInside = true
        ViewerClose.discardThen([model]) { askedInside = !ViewerClose.unsettled([model]).isEmpty }
        #expect(!askedInside)
        #expect(!model.discardOnce)
        #expect(ViewerClose.unsettled([model]).count == 1)
        // A repeated close that never asks again leaves nothing behind either.
        ViewerClose.discardThen([model]) {}
        #expect(!model.discardOnce)
        #expect(model.dirtyPaths.count == 1)
    }

    @Test func aWindowCloseReachesTheWholeTabGroup() {
        let first = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        let second = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        first.tabbingMode = .preferred
        second.tabbingMode = .preferred
        #expect(ViewerClose.members(of: first) == [first])
        first.addTabbedWindow(second, ordered: .above)
        #expect(Set(ViewerClose.members(of: second).map(ObjectIdentifier.init)) == Set([first, second].map(ObjectIdentifier.init)))
        #expect(ViewerClose.members(of: nil).isEmpty)
    }

    @Test func buttonsMapToChoices() {
        #expect(ViewerClose.choice(for: .alertFirstButtonReturn) == .save)
        #expect(ViewerClose.choice(for: .alertSecondButtonReturn) == .discard)
        #expect(ViewerClose.choice(for: .alertThirdButtonReturn) == .cancel)
        #expect(ViewerClose.choice(for: .cancel) == .cancel)
    }

    @Test func closeGoesOnForDiscardAndForASuccessfulSaveOnly() {
        #expect(ViewerClose.proceeds(.discard) { false })
        #expect(ViewerClose.proceeds(.save) { true })
        #expect(!ViewerClose.proceeds(.save) { false })
        #expect(!ViewerClose.proceeds(.cancel) { true })
    }

    @Test func messageNamesOneFileOrCountsMany() {
        #expect(ViewerClose.message(for: ["/p/a.md"]).title == "Save changes to a.md?")
        let many = (1...10).map { "/p/f\($0).md" }
        let text = ViewerClose.message(for: many)
        #expect(text.title == "Save changes to 10 files?")
        #expect(text.detail.contains("f8.md") && !text.detail.contains("f9.md"))
        #expect(text.detail.contains("and 2 more"))
    }
}

/// The web view must not outlive its controller: a window closed without `stop()` frees it.
@Suite
@MainActor
struct ViewerWebLifetimeTests {
    @Test func controllerIsFreedWhenNothingHoldsIt() async throws {
        let model = ViewerModel(root: NSTemporaryDirectory())
        var controller: ViewerWebController? = ViewerWebController(model: model)
        weak var weakController = controller
        let container = try #require(controller?.container)
        controller?.start()
        for _ in 0..<100 where container.subviews.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(!container.subviews.isEmpty)
        controller = nil
        for _ in 0..<20 where weakController != nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(weakController == nil)
    }
}

/// The layout glue of one tab: what a drag from a page leaves behind.
@Suite
@MainActor
struct ViewerHostTests {
    private func host(with names: [String]) throws -> (ViewerHost, String) {
        let dir = try Scratch.make()
        let host = ViewerHost()
        for name in names {
            try "one".write(toFile: dir + "/" + name, atomically: true, encoding: .utf8)
            #expect(host.open(OpenTarget(path: dir + "/" + name), root: dir, focus: false))
        }
        return (host, dir)
    }

    @Test func aFileDragFromThePageEndsWithAClickOrTheDragEnd() throws {
        let (host, dir) = try host(with: ["a.md"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = try #require(host.models.first)
        model.onFileDrag?(PageFileDrag(path: dir + "/a.md", moves: true, sole: true))
        #expect(host.drag != nil)
        host.cancelFileDrag()
        #expect(host.drag == nil)

        model.onFileDrag?(PageFileDrag(path: dir + "/a.md", moves: true, sole: true))
        model.onFileDrag?(nil)
        #expect(host.drag == nil)

        // A terminal drag is Ghostty's session: a click does not cancel it.
        host.terminalDragged(UUID())
        host.cancelFileDrag()
        #expect(host.drag != nil)
    }

    @Test func plainPointerEventsAreNeverAnswered() {
        #expect(AreaDropView.isPlainEvent(.leftMouseDown))
        #expect(AreaDropView.isPlainEvent(.mouseMoved))
        #expect(AreaDropView.isPlainEvent(.scrollWheel))
        #expect(!AreaDropView.isPlainEvent(.leftMouseDragged))
        #expect(!AreaDropView.isPlainEvent(nil))
    }

    @Test func aFileThatDoesNotOpenLeavesNoEmptyViewer() throws {
        let (host, dir) = try host(with: ["a.md"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let source = try #require(host.tree.viewers.first).id
        let missing = dir + "/gone.md"

        host.drop(.file(FileDrag(path: missing, viewer: source, moves: false, sole: false)), .half(.top))
        #expect(host.tree.viewers.count == 1)
        host.drop(.file(FileDrag(path: missing, viewer: source, moves: true, sole: false)), .half(.top))
        #expect(host.tree.viewers.count == 1)

        // A file that opens makes the second viewer.
        try "two".write(toFile: dir + "/b.md", atomically: true, encoding: .utf8)
        host.drop(.file(FileDrag(path: dir + "/b.md", viewer: source, moves: false, sole: false)), .half(.top))
        #expect(host.tree.viewers.count == 2)
    }
}
