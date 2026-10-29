import AppKit
import Foundation
import OSLog

/// What the page's keys ask of the layout around the viewer.
enum ViewerLayoutCommand {
    /// Opens the active file in a new viewer on that side.
    case split(AreaEdge)
    case focus(AreaTree.FocusDirection)
    /// Moves the nearest divider of the viewer on that axis, as Ghostty's `resize_split` does.
    /// `pane` is the viewer's own size; the whole area's follows from it.
    case resize(AreaTree.Spatial.Direction, pane: CGSize)
    /// Equal shares for the viewers and the block, and for the terminals inside the block.
    case equalize
}

/// A file the page starts to drag: a tab (it moves) or a tree row (it only opens).
struct PageFileDrag: Equatable {
    let path: String
    let moves: Bool
    let sole: Bool
}

/// What a viewer pane shows: tabs, documents, the files tree and the watchers. The web page draws
/// it and reports user actions; this model owns the state. See `docs/modules/viewer.md`.
@MainActor
final class ViewerModel {
    private static let logger = Logger(subsystem: "tarn", category: "viewer")

    private(set) var tabs = ViewerTabs()
    private(set) var tree: FileTree
    private(set) var treeVisible = false
    private var docs: [String: ViewerDocument] = [:]
    private var rowCache: [TreeRow] = []
    private var watchers: [String: FileWatcher] = [:]
    private var ready = false

    var dark = true {
        didSet { if dark != oldValue { pushChrome() } }
    }

    /// Runs a script in the page. Set by the web controller.
    var script: ((String) -> Void)?
    /// Asks to close the pane, with the tabs it had, for undo.
    var onClosePane: (([ViewerTab], Int) -> Void)?
    /// A key or menu command that changes the layout of the tab: a split or a focus move.
    var onLayout: ((ViewerLayoutCommand) -> Void)?
    /// The page started dragging a file, or ended the drag (nil).
    var onFileDrag: ((PageFileDrag?) -> Void)?
    /// Asks to give the page keyboard focus.
    var onFocus: (() -> Void)?
    /// True while the page holds keyboard focus.
    var hasFocus: () -> Bool = { false }
    /// Cmd+B typed in the pane; the host owns the pane's lifetime and focus.
    var onPaneKey: (() -> Void)?
    /// Asks to hide the pane (Esc or the Files button in a pane with no file).
    var onHidePane: (() -> Void)?

    init(root: String) {
        tree = FileTree(root: root)
    }

    /// Folders the page may read images from.
    var assetRoots: [String] {
        [tree.root] + docs.keys.map { ($0 as NSString).deletingLastPathComponent }
    }

    var snapshot: [ViewerTab] { tabs.tabs }

    /// Set when the user chose Don't Save in a close sheet; the repeated close consumes it. The edits
    /// stay in place until the window really closes, so a Cancel in a later dialog loses nothing.
    var discardOnce = false

    /// Paths with unsaved edits, in tab order.
    var dirtyPaths: [String] {
        tabs.tabs.map(\.path).filter { docs[$0]?.isDirty == true }
    }

    // MARK: Actions

    @discardableResult
    func open(_ target: OpenTarget, pin: Bool = false, background: Bool = false) -> Bool {
        guard ensureDocument(target.path) else {
            toast("Cannot open \((target.path as NSString).lastPathComponent)")
            return false
        }
        tabs.open(target.path, line: target.line, pin: pin, background: background)
        prune()
        tree.reveal(target.path)
        pushDocument(target.path, reason: "open")
        pushChrome()
        return true
    }

    /// Takes over the files of another viewer, edits included: the viewer is dropped into this one.
    func absorb(_ other: ViewerModel) {
        let active = other.tabs.activePath
        for tab in other.tabs.tabs {
            adopt(tab.path, from: other)
            tabs.open(tab.path, pin: true)
        }
        if let active {
            tabs.open(active, pin: true)
            tree.reveal(active)
        }
        pushAll()
    }

    /// Whether `take(_:from:)` loses nothing. Both viewers may hold the file: a clean copy gives way
    /// to a copy with edits, equal edits are one, but two different edited copies cannot share a
    /// tab (tabs and documents are keyed by path), so that drop is refused and both stay as they are.
    func canTake(_ path: String, from other: ViewerModel) -> Bool {
        guard let mine = docs[path], let theirs = other.docs[path] else { return true }
        return !(mine.isDirty && theirs.isDirty && mine.text != theirs.text)
    }

    /// `canTake` for every file of `other`.
    func canAbsorb(_ other: ViewerModel) -> Bool {
        other.tabs.tabs.allSatisfy { canTake($0.path, from: other) }
    }

    /// Takes one file from another viewer's tab, edits included, or opens it from disk when it
    /// was not a tab. The caller then calls `release` on the other viewer.
    @discardableResult
    func take(_ path: String, from other: ViewerModel) -> Bool {
        guard other.docs[path] != nil else {
            return open(OpenTarget(path: path), pin: true)
        }
        adopt(path, from: other)
        tabs.open(path, pin: true)
        tree.reveal(path)
        pushAll()
        return true
    }

    /// The file went to another viewer: its tab goes, the document went with it. No question, no
    /// undo; the caller closes the viewer when no tab is left.
    func release(_ path: String) {
        guard let index = tabs.tabs.firstIndex(where: { $0.path == path }) else { return }
        tabs.close(at: index)
        docs[path] = nil
        watchers[path] = nil
        pushChrome()
    }

    var isEmpty: Bool { tabs.tabs.isEmpty }

    /// Brings the document over unless this viewer holds the same file with edits of its own
    /// (or an equal copy). Callers check `canTake` first.
    private func adopt(_ path: String, from other: ViewerModel) {
        guard let doc = other.docs[path] else { return }
        if let mine = docs[path], mine.isDirty || !doc.isDirty { return }
        docs[path] = doc
        watchers[path] = FileWatcher(path: path) { [weak self] in self?.diskChanged(path) }
    }

    func reopen(_ saved: [ViewerTab], active: Int) {
        for tab in saved where ensureDocument(tab.path) {
            tabs.open(tab.path, pin: !tab.preview)
        }
        tabs.activate(active)
        // Every file is gone: an empty pane with no tree would hang there; show the tree instead.
        if tabs.tabs.isEmpty { treeVisible = true }
        pushAll()
    }

    /// Drops documents and watchers of files that lost their tab (a replaced preview).
    private func prune() {
        let open = Set(tabs.tabs.map(\.path))
        for path in docs.keys where !open.contains(path) {
            docs[path] = nil
            watchers[path] = nil
        }
    }

    func toggleTree() {
        treeVisible.toggle()
        pushChrome()
    }

    func closeActiveTab() {
        // A pane with no file has no tab to close: Cmd+W closes the pane itself.
        if tabs.tabs.isEmpty {
            onClosePane?([], -1)
            return
        }
        closeTab(at: tabs.active)
    }

    /// Esc and the Files button in a pane with no file: the pane hides with its tree state kept.
    @discardableResult
    private func hidePaneIfEmpty() -> Bool {
        guard tabs.tabs.isEmpty else { return false }
        onHidePane?()
        return true
    }

    func flushPendingEdit() {
        runScript("tarn.flush()")
    }

    func focusTreeInPage() {
        onFocus?()
        runScript("tarn.focusTree()")
    }

    func focusContentInPage() {
        onFocus?()
        runScript("tarn.focusContent()")
    }

    /// Opens the pane with the tree only, no file (Cmd+B in a terminal with no pane).
    func revealTree() {
        treeVisible = true
        pushChrome()
    }

    func closeTab(at index: Int) {
        guard tabs.tabs.indices.contains(index) else { return }
        let path = tabs.tabs[index].path
        guard confirmDiscard(path) else { return }
        // The alert is modal but the main queue runs: find the tab again.
        guard let index = tabs.tabs.firstIndex(where: { $0.path == path }) else { return }
        let before = (tabs.tabs, tabs.active)
        tabs.close(at: index)
        docs[path] = nil
        watchers[path] = nil
        if tabs.tabs.isEmpty {
            onClosePane?(before.0, before.1)
        } else {
            pushChrome()
        }
    }

    /// Saves every dirty document. False when one stays dirty (conflict or write error).
    func saveAll() -> Bool {
        for path in dirtyPaths { save(path) }
        return dirtyPaths.isEmpty
    }

    func closePane() {
        for tab in tabs.tabs where !confirmDiscard(tab.path) { return }
        onClosePane?(tabs.tabs, tabs.active)
    }

    /// The page process died: the page reloads and `ready` pushes the state again.
    func pageLost() {
        ready = false
    }

    func shutdown() {
        watchers = [:]
        script = nil
        ready = false
    }

    /// Runs a command that came from a key or the menu.
    func command(_ name: String) {
        switch name {
        case "save", "mode": runScript("tarn.cmd(\(literal(name)))")
        case "find:open", "find:next", "find:prev", "find:hide":
            runScript("tarn.find(\(literal(String(name.dropFirst(5)))))")
        case "tree": onPaneKey?()
        case "closeTab": closeActiveTab()
        default: break
        }
    }

    // MARK: Messages from the page

    func handle(_ body: [String: Any]) {
        guard let kind = body["t"] as? String else { return }
        let path = body["path"] as? String
        let index = body["index"] as? Int ?? -1
        switch kind {
        case "ready":
            ready = true
            pushAll()
        case "error":
            Self.logger.error("page error \(body["message"] as? String ?? "", privacy: .public)")
        case "tab":
            tabs.activate(index)
            if body["pin"] as? Bool == true { tabs.pin(at: index) }
            pushChrome()
        case "closeTab": closeTab(at: index)
        case "closePane": closePane()
        case "dragFile":
            if let path { onFileDrag?(PageFileDrag(path: path, moves: body["tab"] as? Bool == true, sole: tabs.tabs.count == 1)) }
        case "dragEnd": onFileDrag?(nil)
        case "toggleTree":
            // The Files button: the tree of a pane with files; a pane with no file has nothing else.
            if hidePaneIfEmpty() { return }
            toggleTree()
        case "hideTree":
            if hidePaneIfEmpty() { return }
            treeVisible = false
            pushChrome()
            onFocus?()
        case "treeToggle":
            if let path { tree.toggle(path) }
            pushChrome()
        case "treeOpen":
            if let path {
                let opened = open(OpenTarget(path: path), pin: body["pin"] as? Bool == true)
                // Enter on a file moves the keyboard into it; a file that did not open leaves it in the tree.
                if opened, body["enter"] as? Bool == true { focusContentInPage() }
            }
        case "edit":
            if let path, let text = body["text"] as? String, isCurrent(path, body) { edit(path, text) }
        case "save":
            if let path { save(path) }
        case "task":
            if let path, let line = body["line"] as? Int {
                setTask(path, line: line, checked: body["checked"] as? Bool == true, current: isCurrent(path, body))
            }
        case "take":
            update(path) { $0.takeDisk() }
        case "keep":
            update(path) { $0.keepMine() }
        case "link":
            if let href = body["href"] as? String { follow(href, from: body["from"] as? String) }
        case "copy":
            if let text = body["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        default:
            Self.logger.info("unknown page message \(kind, privacy: .public)")
        }
    }

    /// A message made against an older text than the model holds is dropped: the page has been
    /// sent the newer one.
    private func isCurrent(_ path: String, _ body: [String: Any]) -> Bool {
        guard let doc = docs[path] else { return false }
        return body["rev"] as? Int == doc.revision
    }

    private func edit(_ path: String, _ text: String) {
        guard var doc = docs[path], doc.text != text else { return }
        doc.edit(text)
        docs[path] = doc
        tabs.pin(path: path)
        pushChrome(rescan: false)
    }

    private func update(_ path: String?, _ change: (inout ViewerDocument) -> Void) {
        guard let path, var doc = docs[path] else { return }
        change(&doc)
        docs[path] = doc
        pushDocument(path, reason: "open")
        pushChrome()
    }

    func save(_ path: String) {
        guard var doc = docs[path] else { return }
        if case .notice = doc.content { return }
        guard doc.isDirty || doc.conflict || doc.isMissing else { return toast("No changes") }
        // The disk may have changed before the watcher fired: never write over the agent's version.
        let disk = FileRead.read(path)
        if case .notice = disk {
            return toast("The file on disk is no longer text this viewer can edit: not saved")
        }
        if !doc.conflict, [.conflict, .reloaded].contains(doc.diskChanged(disk)) {
            docs[path] = doc
            pushChrome()
            return toast("The file changed on disk: take the agent version or keep yours first")
        }
        if doc.conflict { return toast("The file changed on disk: take the agent version or keep yours first") }
        do {
            try Self.write(doc.text, to: path)
        } catch {
            Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
            return toast("Cannot save: \(error.localizedDescription)")
        }
        doc.saved(stamp: FileStamp.of(path))
        docs[path] = doc
        pushChrome()
        toast("Saved")
    }

    /// Writes through a symlink and keeps the file mode; the write is atomic.
    private static func write(_ text: String, to path: String) throws {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let mode = try? FileManager.default.attributesOfItem(atPath: resolved.path)[.posixPermissions]
        try text.write(to: resolved, atomically: true, encoding: .utf8)
        if let mode { try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: resolved.path) }
    }

    private func setTask(_ path: String, line: Int, checked: Bool, current: Bool) {
        guard var doc = docs[path] else { return }
        guard current, !doc.isDirty, !doc.conflict else {
            pushDocument(path, reason: "revert")
            return toast("Save or discard your edits before ticking a box")
        }
        guard doc.setTask(line: line, checked: checked) else {
            pushDocument(path, reason: "revert")
            return toast("This checkbox no longer matches the file")
        }
        docs[path] = doc
        save(path)
        pushDocument(path, reason: "task")
    }

    private func follow(_ href: String, from: String?) {
        if href.lowercased().hasPrefix("http://") || href.lowercased().hasPrefix("https://") || href.hasPrefix("mailto:") {
            if let url = URL(string: href) { NSWorkspace.shared.open(url) }
            return
        }
        let bare = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
        let decoded = bare.removingPercentEncoding ?? bare
        let folder = from.map { ($0 as NSString).deletingLastPathComponent } ?? tree.root
        guard let target = ViewerPaths.resolve(decoded, cwd: folder) else { return }
        switch ViewerPaths.classify(target.path) {
        case .text: open(target)
        case .system:
            // A link in a document is as untrusted as terminal output: same policy as upstream.
            if case let .allow(url) = UntrustedURL(URL(fileURLWithPath: target.path).absoluteString).decision {
                NSWorkspace.shared.open(url)
            } else {
                toast("Blocked: open \(decoded) from the terminal")
            }
        case .directory, .special, .missing: toast("No such file: \(decoded)")
        }
    }

    // MARK: Documents

    private func ensureDocument(_ path: String) -> Bool {
        if docs[path] != nil { return true }
        guard let doc = ViewerDocument(path: path) else { return false }
        docs[path] = doc
        watchers[path] = FileWatcher(path: path) { [weak self] in self?.diskChanged(path) }
        return true
    }

    private func diskChanged(_ path: String) {
        guard var doc = docs[path] else { return }
        // Folder events are frequent: the stamp is cheap, the read is not.
        if let stamp = FileStamp.of(path), stamp == doc.stamp, !doc.isMissing { return }
        let change = doc.diskChanged(FileRead.read(path))
        docs[path] = doc
        switch change {
        case .none: break
        case .reloaded:
            pushDocument(path, reason: "external")
            pushChrome()
        case .conflict:
            pushChrome()
        case .deleted:
            toast("\((path as NSString).lastPathComponent) was deleted on disk. Save writes it again.")
        }
    }

    private func confirmDiscard(_ path: String) -> Bool {
        guard let doc = docs[path], doc.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \((path as NSString).lastPathComponent)?"
        alert.informativeText = "Your changes are lost if you do not save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save(path)
            return docs[path]?.isDirty != true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: Pushing state to the page

    private func pushAll() {
        for path in docs.keys { pushDocument(path, reason: "open") }
        pushChrome()
    }

    private func pushDocument(_ path: String, reason: String) {
        guard let doc = docs[path] else { return }
        var object: [String: Any] = [
            "path": path, "rev": doc.revision, "reason": reason,
            "dir": (path as NSString).deletingLastPathComponent,
            "lang": ViewerPaths.language(path),
        ]
        switch doc.content {
        case .markdown:
            object["kind"] = "md"
            object["text"] = doc.text
        case .code:
            object["kind"] = "code"
            object["text"] = doc.text
        case let .notice(message):
            object["kind"] = "notice"
            object["notice"] = message
            object["text"] = ""
        }
        if let tab = tabs.tabs.first(where: { $0.path == path }), let line = tab.line {
            object["line"] = line
            object["jump"] = tab.jump
        }
        runScript("tarn.setDoc(\(json(object)))")
    }

    /// `rescan: false` reuses the last folder listing: a keystroke changes only the dirty marks, and
    /// listing up to 5000 entries on the main thread every 120 ms is not free.
    private func pushChrome(rescan: Bool = true) {
        if rescan { rowCache = treeVisible ? tree.rows() : [] }
        let rows: [[String: Any]] = treeVisible ? rowCache.map { row in
            [
                "path": row.path, "name": row.name, "depth": row.depth,
                "kind": row.isDirectory ? "dir" : "file", "open": row.isOpen,
                "mod": docs[row.path]?.isDirty ?? false,
            ]
        } : []
        let object: [String: Any] = [
            "tabs": tabs.tabs.map { tab in
                [
                    "path": tab.path, "name": (tab.path as NSString).lastPathComponent,
                    "preview": tab.preview, "dirty": docs[tab.path]?.isDirty ?? false,
                ] as [String: Any]
            },
            "active": tabs.active,
            "tree": ["visible": treeVisible, "root": (tree.root as NSString).lastPathComponent, "rows": rows] as [String: Any],
            "dark": dark,
            "conflicts": docs.values.filter(\.conflict).map(\.path),
        ]
        runScript("tarn.setChrome(\(json(object)))")
    }

    func toast(_ text: String) {
        runScript("tarn.toast(\(literal(text)))")
    }

    private func runScript(_ call: String) {
        guard ready else { return }
        script?(call)
    }

    private func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return "null" }
        return text
    }

    private func literal(_ text: String) -> String {
        json([text]).dropFirst().dropLast().description
    }
}
