import AppKit
import OSLog

/// A workspace and the tab windows in it, top to bottom.
struct WorkspaceRun {
    let workspace: Workspace
    let windows: [NSWindow]
}

/// Which workspace every tab window belongs to. The single writer of membership, names and
/// fold; Ghostty stays the single writer of tab order (`docs/plans/s3-windows-contracts.md`
/// section 1). The rules live in `WorkspaceBook`; this class maps them onto windows, makes
/// the native moves they ask for, and tells restoration and the sidebar about changes.
@MainActor
final class WorkspaceRegistry {
    static let shared = WorkspaceRegistry()

    private static let logger = Logger(subsystem: "tarn", category: "workspace")

    private struct Entry {
        weak var window: NSWindow?
        let key: TabKey
    }

    private var book = WorkspaceBook()
    private var entries: [ObjectIdentifier: Entry] = [:]
    /// Windows that posted `willClose`; AppKit may still list them in their tab group.
    private let closing = NSHashTable<NSWindow>.weakObjects()
    /// Our own moves are under way: ignore the notifications they cause.
    private var isBusy = false

    /// Closed tabs whose undo is still on Ghostty's stack (S15 to S18).
    private let shelf = TombstoneShelf()
    /// Surface ids of every tab window as last seen. A close of a whole window empties the
    /// surface trees before the windows close (`TerminalController.swift:872`), so the ids are
    /// read from here then.
    private var surfaceCache: [ObjectIdentifier: Set<UUID>] = [:]

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: .terminalTabsDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if let window = note.object as? NSWindow { self?.windowDidBecomeKey(window) }
            }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if let window = note.object as? NSWindow { self?.windowWillClose(window) }
            }
        }
    }

    // MARK: Reading

    /// The workspaces of the window's tab group, top to bottom.
    func runs(for window: NSWindow) -> [WorkspaceRun] {
        let windows = group(of: window)
        return book.runs(for: windows.map(key(for:))).map { run in
            WorkspaceRun(workspace: run.workspace, windows: run.tabs.compactMap(self.window(for:)))
        }
    }

    /// The key of a tab window, if it has one yet.
    func tabKey(of window: NSWindow) -> TabKey? {
        entries[ObjectIdentifier(window)]?.window === window ? entries[ObjectIdentifier(window)]?.key : nil
    }

    /// The workspace of a tab window (S12 asks for it).
    func workspace(of window: NSWindow) -> Workspace? {
        entries[ObjectIdentifier(window)].flatMap { book.workspace(of: $0.key) }
    }

    // MARK: Following Ghostty

    /// Looks at every tab group and brings workspaces in line with it. Safe to call often.
    func sync() {
        guard !isBusy else { return }
        isBusy = true
        entries = entries.filter { $0.value.window != nil }
        claimTombstones()
        cacheSurfaces()

        var outcome = book.reconcile(bookGroups())
        for note in outcome.notes { Self.logger.error("\(note, privacy: .public)") }
        if !outcome.reorders.isEmpty {
            for reorder in outcome.reorders {
                guard let window = window(for: reorder.tab) else { continue }
                moveNatively(window, by: reorder.delta)
            }
            outcome.changed.formUnion(book.reconcile(bookGroups()).changed)
        }
        isBusy = false
        publish(outcome.changed)
    }

    private func bookGroups() -> [WorkspaceBook.Group] {
        var seen = Set<ObjectIdentifier>()
        var groups: [WorkspaceBook.Group] = []
        for window in NSApp.windows where isTab(window) {
            guard seen.insert(ObjectIdentifier(window)).inserted else { continue }
            let windows = group(of: window)
            seen.formUnion(windows.map(ObjectIdentifier.init))
            let selected = window.tabGroup?.selectedWindow ?? window
            groups.append(.init(tabs: windows.map(key(for:)), selected: key(for: selected)))
        }
        return groups
    }

    private func isTab(_ window: NSWindow) -> Bool {
        window.windowController is TerminalController && !closing.contains(window)
    }

    private func group(of window: NSWindow) -> [NSWindow] {
        (window.tabbedWindows ?? [window]).filter(isTab)
    }

    private func key(for window: NSWindow) -> TabKey {
        let id = ObjectIdentifier(window)
        if let entry = entries[id], entry.window === window { return entry.key }
        let entry = Entry(window: window, key: TabKey())
        entries[id] = entry
        return entry.key
    }

    private func window(for key: TabKey) -> NSWindow? {
        entries.values.first { $0.key == key }?.window
    }

    private func windowDidBecomeKey(_ window: NSWindow) {
        claimTombstones()
        guard !isBusy, let entry = entries[ObjectIdentifier(window)], let id = book.selected(entry.key) else { return }
        publish([id])
    }

    private func windowWillClose(_ window: NSWindow) {
        guard let entry = entries[ObjectIdentifier(window)] else { return }
        let order = group(of: window).map(key(for:))
        closing.add(window)
        entries[ObjectIdentifier(window)] = nil
        guard let closed = book.closing(entry.key, order: order) else { return }
        shelve(window, closed: closed)
        publish([closed.set.id])
    }

    // MARK: Tombstones

    /// Registers the tombstone in the undo manager of the window, in the same group as
    /// Ghostty's own close undo (Q11). The closure holds the tombstone, so it expires with
    /// Ghostty's undo and we run no timer. Undo runs the last registered action first: ours
    /// only arms the tombstone, Ghostty's action then creates the window, and `claimTombstones`
    /// matches the two.
    private func shelve(_ window: NSWindow, closed: WorkspaceBook.ClosedTab) {
        guard let controller = window.windowController as? TerminalController,
              let undoManager = controller.undoManager
        else { return }
        let live = Set(controller.surfaceTree.map(\.id))
        let surfaces = live.isEmpty ? (surfaceCache[ObjectIdentifier(window)] ?? []) : live
        surfaceCache[ObjectIdentifier(window)] = nil
        guard !surfaces.isEmpty else {
            Self.logger.error("workspace: tombstone without surfaces window=\(closed.tab, privacy: .public) set=\(closed.set.id, privacy: .public)")
            return
        }
        let token = shelf.add(.init(closed: closed, surfaces: surfaces, viewers: controller.viewerHost.snapshot()))
        undoManager.registerUndo(withTarget: controller.ghostty, expiresAfter: controller.undoExpiration) { [weak self] _ in
            self?.undoRan(token)
        }
    }

    private func undoRan(_ token: TombstoneToken) {
        shelf.arm(token)
        // Ghostty's closure of the same undo creates the windows right after ours; once the
        // undo has finished, whatever no window claimed is dropped (section 8).
        DispatchQueue.main.async { [self] in
            claimTombstones()
            let lost = shelf.settle()
            if lost > 0 { Self.logger.error("workspace: tombstone not matched count=\(lost, privacy: .public)") }
        }
    }

    /// Gives a window that Ghostty's undo created its place back: workspace, run position and
    /// viewers (S15 to S18).
    private func claimTombstones() {
        guard shelf.armedCount > 0 else { return }
        for window in NSApp.windows where isTab(window) {
            guard let controller = window.windowController as? TerminalController,
                  let tombstone = shelf.claim(surfaces: Set(controller.surfaceTree.map(\.id)))
            else { continue }
            book.reinsert(key(for: window), from: tombstone.closed)
            if let viewers = tombstone.viewers { controller.viewerHost.restore(viewers) }
            publish([tombstone.closed.set.id])
        }
    }

    private func cacheSurfaces() {
        var cache: [ObjectIdentifier: Set<UUID>] = [:]
        for window in NSApp.windows where isTab(window) {
            guard let controller = window.windowController as? TerminalController else { continue }
            let id = ObjectIdentifier(window)
            let live = Set(controller.surfaceTree.map(\.id))
            cache[id] = live.isEmpty ? surfaceCache[id] ?? [] : live
        }
        surfaceCache = cache
    }

    /// Windows of the changed sets save their state again, and observers redraw.
    private func publish(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for entry in entries.values where ids.contains(book.set(of: entry.key)?.id ?? UUID()) {
            entry.window?.invalidateRestorableState()
        }
        NotificationCenter.default.post(name: .terminalTabsDidChange, object: nil)
    }

    // MARK: Native moves

    /// Moves a tab by `delta` places with Ghostty's own `move_tab` action. The action acts on
    /// the selected tab, so the tab is selected for the move and the selection is restored.
    private func moveNatively(_ window: NSWindow, by delta: Int) {
        guard delta != 0, let controller = window.windowController as? TerminalController,
              let surface = controller.focusedSurface ?? controller.surfaceTree.first
        else { return }
        let previous = window.tabGroup?.selectedWindow
        if previous !== window { window.makeKeyAndOrderFront(nil) }
        controller.performAction("move_tab:\(delta)", on: surface)
        if let previous, previous !== window { previous.makeKeyAndOrderFront(nil) }
    }

    // MARK: Sidebar commands

    /// A new tab in `workspace` (S3), after its last tab (D2).
    func newTab(in workspace: Workspace.ID, from window: NSWindow) {
        book.setPendingTarget(workspace, for: key(for: window))
        (window.windowController as? TerminalController)?.newTab(nil)
    }

    /// A new workspace with one new tab (S4). False for a blank name.
    @discardableResult
    func createWorkspace(named name: String, from window: NSWindow) -> Bool {
        let tab = key(for: window)
        var created: Workspace.ID?
        let changed = book.edit(tab) { created = $0.create(name: name) }
        guard let created else { return false }
        book.setPendingTarget(created, for: tab)
        publish(changed.map { [$0] } ?? [])
        (window.windowController as? TerminalController)?.newTab(nil)
        return true
    }

    @discardableResult
    func rename(_ workspace: Workspace.ID, to name: String, in window: NSWindow) -> Bool {
        var renamed = false
        edit(window) { renamed = $0.rename(workspace, to: name) }
        return renamed
    }

    func setCollapsed(_ workspace: Workspace.ID, _ collapsed: Bool, in window: NSWindow) {
        edit(window) { $0.setCollapsed(workspace, collapsed) }
    }

    /// Deletes the workspace; its tabs move up, or down for the first one (D13).
    @discardableResult
    func delete(_ workspace: Workspace.ID, in window: NSWindow) -> Bool {
        let order = group(of: window).map(key(for:))
        var deleted = false
        edit(window) { deleted = $0.delete(workspace, order: order) }
        return deleted
    }

    /// Puts `window` in `workspace`, before `neighbour` or at the end of the workspace
    /// (S7, S8): membership first, then one native move.
    func moveTab(_ window: NSWindow, to workspace: Workspace.ID, before neighbour: NSWindow? = nil) {
        let tab = key(for: window)
        let order = group(of: window).map(key(for:))
        guard let index = order.firstIndex(of: tab) else { return }
        isBusy = true
        let changed = book.edit(tab) { $0.join(tab, to: workspace) }
        let others = order.filter { $0 != tab }
        let destination: Int
        if let neighbour, let at = others.firstIndex(of: key(for: neighbour)) {
            destination = at
        } else {
            let last = others.lastIndex { book.workspace(of: $0)?.id == workspace }
            destination = last.map { $0 + 1 } ?? others.count
        }
        moveNatively(window, by: destination - index)
        isBusy = false
        sync()
        publish(changed.map { [$0] } ?? [])
    }

    /// Moves a whole workspace before `other`, or to the end (S9): one native move per tab.
    func moveWorkspace(_ workspace: Workspace.ID, before other: Workspace.ID?, in window: NSWindow) {
        var order = group(of: window).map(key(for:))
        var runs = book.runs(for: order)
        guard let from = runs.firstIndex(where: { $0.workspace.id == workspace }) else { return }
        let moving = runs.remove(at: from)
        runs.insert(moving, at: runs.firstIndex { $0.workspace.id == other } ?? runs.count)

        isBusy = true
        for (place, tab) in runs.flatMap(\.tabs).enumerated() {
            guard let current = order.firstIndex(of: tab), current != place else { continue }
            order.remove(at: current)
            order.insert(tab, at: place)
            if let tabWindow = self.window(for: tab) { moveNatively(tabWindow, by: place - current) }
        }
        isBusy = false
        sync()
    }

    private func edit(_ window: NSWindow, _ change: (inout WorkspaceSet) -> Void) {
        if let id = book.edit(key(for: window), change) { publish([id]) }
    }

    // MARK: Restore

    /// The table a window saves with its state, or nil when it has none yet.
    func snapshot(for window: NSWindow) -> WorkspaceSnapshot? {
        guard let entry = entries[ObjectIdentifier(window)] else { return nil }
        return book.snapshot(of: entry.key, order: group(of: window).map(key(for:)))
    }

    /// A restored window brings its table and its key.
    func restore(_ snapshot: WorkspaceSnapshot, for window: NSWindow) {
        if let taken = self.window(for: snapshot.tabKey), taken !== window {
            Self.logger.error("workspace: duplicate key window=\(snapshot.tabKey, privacy: .public) set=\(snapshot.setID, privacy: .public)")
            return
        }
        entries[ObjectIdentifier(window)] = Entry(window: window, key: snapshot.tabKey)
        book.adopt(snapshot)
    }

    /// Puts a reopened tab window back where `closed` says (S15 to S18).
    func reinsert(_ window: NSWindow, from closed: WorkspaceBook.ClosedTab) {
        book.reinsert(key(for: window), from: closed)
        publish([closed.set.id])
    }
}
