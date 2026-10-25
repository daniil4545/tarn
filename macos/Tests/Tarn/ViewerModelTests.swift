import Carbon.HIToolbox
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

    @Test func codeFileTakesEditsLikeMarkdown() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/main.go"
        try "package main\n".write(toFile: path, atomically: true, encoding: .utf8)
        var doc = try #require(ViewerDocument(path: path))
        doc.edit("package app\n")
        #expect(doc.text == "package app\n")
        #expect(doc.isDirty)
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

/// Path clicks and pane keys that must not depend on the shell or the layout.
@Suite
@MainActor
struct ViewerClickAndKeyTests {
    private func folder() throws -> String {
        let dir = try Scratch.make()
        try "x".write(toFile: dir + "/a.md", atomically: true, encoding: .utf8)
        try "x".write(toFile: dir + "/pic.png", atomically: true, encoding: .utf8)
        return dir
    }

    @Test func relativeAndAbsoluteClicksOpenInTheViewer() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let expected = ViewerRouter.Decision.open(OpenTarget(path: dir + "/a.md", line: nil))
        #expect(ViewerRouter.decide("./a.md", cwd: dir) == expected)
        #expect(ViewerRouter.decide("a.md", cwd: dir) == expected)
        #expect(ViewerRouter.decide(dir + "/a.md", cwd: dir) == expected)
        #expect(ViewerRouter.decide(dir + "/a.md", cwd: nil) == expected)
    }

    @Test func refusalsNameTheirReason() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(ViewerRouter.decide("./a.md", cwd: nil) == .upstream(reason: "relative path and the terminal has no working directory"))
        #expect(ViewerRouter.decide("https://x.org/a.md", cwd: dir) == .upstream(reason: "a URL"))
        #expect(ViewerRouter.decide("./pic.png", cwd: dir) == .upstream(reason: "a media, document or archive type"))
        #expect(ViewerRouter.decide(dir, cwd: dir) == .upstream(reason: "a directory"))
        #expect(ViewerRouter.decide("./nope.md", cwd: dir) == .missing(raw: "./nope.md"))
    }

    @Test func workingDirectoryOfAProcessIsReadFromTheKernel() {
        let own = ViewerPaths.cwd(ofPid: getpid())
        #expect(own.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            == URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path)
    }

    private func key(_ characters: String, _ code: Int, _ flags: NSEvent.ModifierFlags = .command) -> String? {
        ViewerWebView.command(characters: characters, keyCode: UInt16(code), flags: flags)
    }

    @Test func paneKeysFollowTheTypedLetterOfLatinLayouts() {
        #expect(key("s", kVK_ANSI_S) == "save")
        #expect(key("e", kVK_ANSI_E) == "mode")
        #expect(key("b", kVK_ANSI_B) == "tree")
        // Dvorak: the B key types "x" (cut), the S key types "o" (open). Neither is a pane command.
        #expect(key("x", kVK_ANSI_B) == nil)
        #expect(key("o", kVK_ANSI_S) == nil)
        // Dvorak types "s" on the semicolon key: that is Cmd+S.
        #expect(key("s", kVK_ANSI_Semicolon) == "save")
        // Colemak: the E key types "f" (find), the S key types "r".
        #expect(key("f", kVK_ANSI_E) == nil)
        #expect(key("r", kVK_ANSI_S) == nil)
    }

    @Test func paneKeysFallBackToThePhysicalKeyForNonLatinLayouts() {
        #expect(key("ы", kVK_ANSI_S) == "save")
        #expect(key("у", kVK_ANSI_E) == "mode")
        #expect(key("и", kVK_ANSI_B) == "tree")
        #expect(key("ы", kVK_ANSI_S, [.command, .shift]) == nil)
        #expect(key("ф", kVK_ANSI_A) == nil)
    }

    @Test func otherModifiersOrKeysAreNotPaneCommands() {
        #expect(key("s", kVK_ANSI_S, [.command, .shift]) == nil)
        #expect(key("s", kVK_ANSI_S, []) == nil)
        #expect(key("a", kVK_ANSI_A) == nil)
        // Caps Lock does not stop the shortcut.
        #expect(key("s", kVK_ANSI_S, [.command, .capsLock]) == "save")
    }
}

/// The one pane key, Cmd+B, over the states of the pane (user decision 2026-10-25, PR #3 comment
/// 6396372910): no pane, hidden, shown with no file, shown with files. Cmd+B opens and hides and
/// never closes; Cmd+W closes. Test-change: replaces the tests of the earlier three-key scheme.
@Suite
@MainActor
struct ViewerPaneKeyTests {
    private func hostWithFile() throws -> (ViewerHost, String) {
        let dir = try Scratch.make()
        try "one".write(toFile: dir + "/a.md", atomically: true, encoding: .utf8)
        let host = ViewerHost()
        host.open(OpenTarget(path: dir + "/a.md"), root: dir, focus: false)
        return (host, dir)
    }

    private func spin(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: Cmd+B, one test per cell of the table

    @Test func noPaneOpensItWithTheTreeAndTheKeyboardInTheTree() async throws {
        let host = ViewerHost()
        host.toggleFromKey(root: NSTemporaryDirectory())
        var calls: [String] = []
        host.model?.handle(["t": "ready"])
        host.model?.script = { calls.append($0) }
        try await spin(0.2)
        #expect(host.model?.treeVisible == true && host.model?.snapshot.isEmpty == true && !host.hidden)
        #expect(calls.contains("tarn.focusTree()"))
    }

    @Test func hiddenPaneComesBackAsItWasHiddenWithTheKeyboardInIt() async throws {
        let (host, dir) = try hostWithFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/a.md"
        host.model?.handle(["t": "edit", "path": path, "text": "mine", "rev": 1])
        host.model?.revealTree()
        host.toggleFromKey(root: nil)
        #expect(host.hidden)
        var grabs = 0
        host.model?.onFocus = { grabs += 1 }
        host.toggleFromKey(root: nil)
        try await spin(0.1)
        #expect(!host.hidden && host.model?.snapshot.map(\.path) == [path] && host.model?.treeVisible == true)
        #expect(host.model?.dirtyPaths == [path] && grabs == 1)
    }

    @Test func shownPaneWithNoFileHidesAndKeepsItsTreeState() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir + "/sub", withIntermediateDirectories: true)
        let host = ViewerHost()
        host.toggleFromKey(root: dir)
        host.model?.handle(["t": "treeToggle", "path": dir + "/sub"])
        let rows = host.model?.tree.rows().count
        host.toggleFromKey(root: nil)
        #expect(host.hidden && host.model != nil)
        host.toggleFromKey(root: nil)
        #expect(!host.hidden && host.model?.tree.rows().count == rows && host.model?.treeVisible == true)
    }

    @Test(arguments: [true, false]) func shownPaneWithFilesHidesWholeKeepingTabsEditsAndTree(tree: Bool) throws {
        let (host, dir) = try hostWithFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/a.md"
        if tree { host.model?.revealTree() }
        host.model?.handle(["t": "edit", "path": path, "text": "mine", "rev": 1])
        host.toggleFromKey(root: nil)
        #expect(host.hidden)
        #expect(host.model?.snapshot.map(\.path) == [path] && host.model?.treeVisible == tree)
        // A hidden pane with unsaved edits still reaches the close dialog.
        #expect(ViewerClose.dirtyPaths(in: host.model.map { [$0] } ?? []) == [path])
    }

    @Test func cmdBNeverClosesInAnyState() throws {
        let (withFile, dir) = try hostWithFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let empty = ViewerHost()
        for host in [empty, withFile] {
            host.toggleFromKey(root: dir)
            for _ in 0..<4 {
                host.toggleFromKey(root: nil)
                #expect(host.model != nil)
            }
        }
    }

    // MARK: Cmd+W, the Files button, Esc, Enter

    @Test func cmdWInAPaneWithNoFileClosesIt() {
        let model = ViewerModel(root: NSTemporaryDirectory())
        var closed = 0
        var hidden = 0
        model.onClosePane = { _, _ in closed += 1 }
        model.onHidePane = { hidden += 1 }
        model.command("closeTab")
        #expect(closed == 1 && hidden == 0)
    }

    @Test func cmdWClosesTheActiveTabAndTheLastTabClosesThePane() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for name in ["a.md", "b.md"] { try "x".write(toFile: dir + "/" + name, atomically: true, encoding: .utf8) }
        let model = ViewerModel(root: dir)
        model.open(OpenTarget(path: dir + "/a.md"), pin: true)
        model.open(OpenTarget(path: dir + "/b.md"), pin: true)
        var saved: [ViewerTab] = []
        var closes = 0
        model.onClosePane = { tabs, _ in saved = tabs; closes += 1 }
        model.command("closeTab")
        #expect(model.snapshot.count == 1 && closes == 0)
        model.command("closeTab")
        #expect(closes == 1 && saved.count == 1)
    }

    @Test func filesButtonAndEscToggleTheTreeOfAPaneWithFilesAndHideAnEmptyPane() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try "x".write(toFile: dir + "/a.md", atomically: true, encoding: .utf8)
        let model = ViewerModel(root: dir)
        model.open(OpenTarget(path: dir + "/a.md"))
        let before = model.treeVisible
        model.handle(["t": "toggleTree"])
        #expect(model.treeVisible != before)
        model.handle(["t": "hideTree"])
        #expect(!model.treeVisible)
        let empty = ViewerModel(root: dir)
        var hidden = 0
        empty.onHidePane = { hidden += 1 }
        empty.handle(["t": "toggleTree"])
        empty.handle(["t": "hideTree"])
        #expect(hidden == 2)
    }

    @Test func enterOnAFileInTheTreeOpensItAndMovesTheKeyboardIntoIt() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try "x".write(toFile: dir + "/a.md", atomically: true, encoding: .utf8)
        let model = ViewerModel(root: dir)
        var calls: [String] = []
        model.handle(["t": "ready"])
        model.script = { calls.append($0) }
        model.handle(["t": "treeOpen", "path": dir + "/a.md", "enter": true])
        #expect(model.snapshot.map(\.path) == [dir + "/a.md"])
        #expect(calls.last == "tarn.focusContent()")
        // A click on a file does not steal the keyboard from the tree.
        calls = []
        model.handle(["t": "treeOpen", "path": dir + "/a.md"])
        #expect(!calls.contains("tarn.focusContent()"))
    }

    @Test func enterOnAFileThatDoesNotOpenLeavesTheKeyboardInTheTree() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = ViewerModel(root: dir)
        var calls: [String] = []
        model.handle(["t": "ready"])
        model.script = { calls.append($0) }
        model.handle(["t": "treeOpen", "path": dir + "/gone.md", "enter": true])
        #expect(model.snapshot.isEmpty)
        #expect(!calls.contains("tarn.focusContent()"))
    }

    @Test func hidingThePaneGivesTheKeyboardToTheTerminal() throws {
        let (host, dir) = try hostWithFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        var returned = 0
        host.focusTerminal = { returned += 1 }
        host.toggleFromKey(root: nil)
        #expect(host.hidden && returned == 1)
        // Showing it gives the keyboard to the pane, not back to the terminal.
        host.toggleFromKey(root: nil)
        #expect(!host.hidden && returned == 1)
        // An empty pane hides the same way.
        let empty = ViewerHost()
        var emptyReturned = 0
        empty.focusTerminal = { emptyReturned += 1 }
        empty.toggleFromKey(root: dir)
        empty.toggleFromKey(root: nil)
        #expect(empty.hidden && emptyReturned == 1)
    }

    // MARK: Keys

    private func key(_ characters: String, _ code: Int, _ flags: NSEvent.ModifierFlags) -> String? {
        ViewerWebView.command(characters: characters, keyCode: UInt16(code), flags: flags)
    }

    @Test func onlyCmdBIsAPaneKeyAndTheRetiredChordsAreNot() {
        #expect(key("b", kVK_ANSI_B, .command) == "tree")
        #expect(key("и", kVK_ANSI_B, .command) == "tree")
        #expect(key("b", kVK_ANSI_B, [.command, .option]) == nil)
        #expect(key("E", kVK_ANSI_E, [.command, .shift]) == nil)
        #expect(key("e", kVK_ANSI_E, .command) == "mode")
        #expect(key("b", kVK_ANSI_B, [.command, .capsLock]) == "tree")
    }

    // MARK: Lifetime and focus kept from the earlier rounds

    @Test func hostCreatesATreeOnlyPaneThatSurvivesAFailedOpen() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let host = ViewerHost()
        let missing = OpenTarget(path: dir + "/nope.md", line: nil)
        #expect(!host.open(missing, root: dir, focus: false))
        #expect(host.model == nil)
        host.toggleFromKey(root: dir)
        #expect(!host.open(missing, root: dir, focus: false))
        #expect(host.model != nil)
    }

    @Test func undoOfACloseWhoseFilesAreGoneShowsTheTree() {
        let model = ViewerModel(root: NSTemporaryDirectory())
        model.reopen([ViewerTab(path: "/nonexistent/a.md", preview: false, line: nil, jump: 0)], active: 0)
        #expect(model.snapshot.isEmpty && model.treeVisible)
    }

    @Test func undoWhileAnotherPaneIsHiddenShowsItWithTheTabs() throws {
        let (host, dir) = try hostWithFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try "two".write(toFile: dir + "/b.md", atomically: true, encoding: .utf8)
        host.toggleFromKey(root: nil)
        host.restore([ViewerTab(path: dir + "/b.md", preview: false, line: nil, jump: 0)], active: 0, root: dir)
        #expect(!host.hidden && host.model?.snapshot.map(\.path).contains(dir + "/b.md") == true)
    }

    @Test func undoOfAnEmptyPaneCloseBringsBackThePaneWithItsTree() throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let host = ViewerHost()
        host.toggleFromKey(root: dir)
        host.model?.command("closeTab")
        #expect(host.model == nil)
        host.restore([], active: -1, root: dir)
        #expect(host.model?.treeVisible == true && host.model?.snapshot.isEmpty == true)
    }

    @Test func aPathClickShowsAHiddenPaneAndAnAgentOpenLeavesItHidden() throws {
        let (host, dir) = try hostWithFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try "two".write(toFile: dir + "/b.md", atomically: true, encoding: .utf8)
        host.toggleFromKey(root: nil)
        host.open(OpenTarget(path: dir + "/b.md"), root: dir, focus: false)
        #expect(host.hidden)
        host.open(OpenTarget(path: dir + "/b.md"), root: dir, focus: true)
        #expect(!host.hidden)
    }

    @Test func closingAHiddenPaneEndsTheHiddenState() throws {
        let (host, dir) = try hostWithFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        host.toggleFromKey(root: nil)
        host.closePane(saved: [], active: -1)
        #expect(host.model == nil && !host.hidden)
    }

    @Test func hidingThePaneSendsThePendingEditFirst() throws {
        let (host, dir) = try hostWithFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        var calls: [String] = []
        host.model?.handle(["t": "ready"])
        host.model?.script = { calls.append($0) }
        host.toggleFromKey(root: nil)
        #expect(calls.contains("tarn.flush()"))
    }

    private final class Responder: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    @Test func layoutChangeGivesTheTerminalItsFirstResponderBackOnAnAgentOpen() async throws {
        let (host, dir) = try hostWithFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try "two".write(toFile: dir + "/b.md", atomically: true, encoding: .utf8)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        let terminal = Responder()
        window.contentView = NSView()
        window.contentView?.addSubview(terminal)
        host.window = window
        window.makeFirstResponder(terminal)
        host.open(OpenTarget(path: dir + "/b.md"), root: dir, focus: false)
        window.makeFirstResponder(nil)
        try await spin(0.4)
        #expect(window.firstResponder === terminal)
    }

    @Test func focusWaitsForTheWebViewToJoinAWindow() async throws {
        let model = ViewerModel(root: NSTemporaryDirectory())
        let web = ViewerWebController(model: model)
        web.start()
        for _ in 0..<100 where web.container.subviews.isEmpty { try await spin(0.1) }
        let view = try #require(web.container.subviews.first)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        web.focus()
        window.contentView = web.container
        try await spin(0.4)
        #expect(window.firstResponder === view)
    }
}

@Suite
@MainActor
struct ViewerSaveTests {
    /// A pane with `name` open and edited to "mine"; returns the host and the file path.
    private func editedPane(_ name: String, in dir: String) throws -> (ViewerHost, String) {
        let path = dir + "/" + name
        try "one".write(toFile: path, atomically: true, encoding: .utf8)
        let host = ViewerHost()
        host.open(OpenTarget(path: path), root: dir, focus: false)
        host.model?.handle(["t": "edit", "path": path, "text": "mine", "rev": 1])
        return (host, path)
    }

    @Test(arguments: ["a.md", "main.go"])
    func writesAnEditedTextFile(name: String) throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let (host, path) = try editedPane(name, in: dir)
        host.model?.handle(["t": "save", "path": path])
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "mine")
    }

    /// The agent rewrote the file after the edit: as text, over 5 MB, or not UTF-8.
    @Test(arguments: [
        Data("agent".utf8),
        Data(repeating: 0x61, count: FileRead.maxBytes + 1),
        Data([0xFF, 0xFE, 0x00, 0x61]),
    ])
    func neverWritesOverTheAgentsVersion(disk: Data) throws {
        let dir = try Scratch.make()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let (host, path) = try editedPane("a.md", in: dir)
        try disk.write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: path)
        host.model?.handle(["t": "save", "path": path])
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == disk)
    }
}
