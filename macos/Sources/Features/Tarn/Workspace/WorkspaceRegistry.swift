import AppKit
import GhosttyKit
import OSLog

/// A workspace and the tab windows in it, top to bottom.
struct WorkspaceRun {
    let workspace: Workspace
    let windows: [NSWindow]
}

/// Which workspace every tab window belongs to. The single writer of membership, names and
/// fold; Ghostty stays the single writer of tab order (`docs/modules/workspaces.md`).
/// The rules live in `WorkspaceBook`; this class maps them onto windows, makes
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
    /// `publish` is delivering its notification; a nested publish only asks for another round.
    private var isPosting = false
    private var repost = false
    private static let maxRounds = 3
    /// Our own moves are under way: ignore the notifications they cause.
    private var isBusy = false
    /// Windows raised by `moveNatively`; their key notifications arrive after `isBusy` is over.
    private var hops = KeyHops()

    /// Closed tabs whose undo is still on Ghostty's stack.
    private let shelf = TombstoneShelf()
    /// Surface ids of every tab window as last seen. A close of a whole window empties the
    /// surface trees before the windows close (`TerminalController.swift:872`), so the ids are
    /// read from here then.
    private var surfaceCache: [ObjectIdentifier: Set<UUID>] = [:]

    private init() {
        book.frozen = !TarnModules.isOn(.workspaces)
        let center = NotificationCenter.default
        center.addObserver(forName: .terminalTabsDidChange, object: nil, queue: .main) { [weak self] note in
            // Delivered synchronously on the main thread. Our own `publish` posts with `self` as the
            // object: following it would re-enter `sync` once per level until the stack ends.
            MainActor.assumeIsolated {
                guard let self, note.object as AnyObject? !== self else { return }
                self.sync()
            }
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

    /// The workspace of a tab window.
    func workspace(of window: NSWindow) -> Workspace? {
        entries[ObjectIdentifier(window)].flatMap { book.workspace(of: $0.key) }
    }

    // MARK: Module switch

    /// Workspaces off freezes the workspaces as they are; on again draws them by membership. The
    /// pass runs now and tells the sidebars.
    var isFrozen: Bool { book.frozen }

    func setFrozen(_ frozen: Bool) {
        guard book.frozen != frozen else { return }
        book.frozen = frozen
        sync()
        NotificationCenter.default.post(name: .terminalTabsDidChange, object: self)
    }

    // MARK: Following Ghostty

    /// Looks at every tab group and brings workspaces in line with it. Safe to call often.
    func sync() {
        guard !isBusy else { return }
        isBusy = true
        entries = entries.filter { $0.value.window != nil }
        claimTombstones()
        cacheSurfaces()

        let outcome = book.reconcile(bookGroups())
        for note in outcome.notes { Self.logger.error("\(note, privacy: .public)") }
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
            // `tabGroup` makes AppKit build a tab bar for a lone window (startup cost); a lone tab is selected.
            let selected = windows.count > 1 ? (window.tabGroup?.selectedWindow ?? window) : window
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
        guard !isBusy, !hops.contains(window), let entry = entries[ObjectIdentifier(window)], let id = book.selected(entry.key) else { return }
        publish([id])
    }

    private func windowWillClose(_ window: NSWindow) {
        guard let entry = entries[ObjectIdentifier(window)] else { return }
        closing.add(window)
        entries[ObjectIdentifier(window)] = nil
        guard let closed = book.closing(entry.key) else { return }
        shelve(window, closed: closed)
        publish([closed.set.id])
    }

    // MARK: Tombstones

    /// Registers the tombstone in the undo manager of the window, in the same group as
    /// Ghostty's own close undo. The closure holds the tombstone, so it expires with
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
        let token = TombstoneToken(.init(closed: closed, surfaces: surfaces, viewers: controller.viewerHost.snapshot()))
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
    /// viewers.
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
    ///
    /// The sidebar used to redraw by calling `sync`, and `sync` publishes: a post delivered on the
    /// spot re-entered `publish` through every redraw until the stack ended (a window close in a
    /// window with several workspaces did it). The sidebar only reads now; this stays as a net. A publish made while observers run only asks for one
    /// more round, and the rounds are capped.
    func publish(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for entry in entries.values where ids.contains(book.set(of: entry.key)?.id ?? UUID()) {
            entry.window?.invalidateRestorableState()
        }
        guard !isPosting else {
            repost = true
            return
        }
        isPosting = true
        defer { isPosting = false }
        var rounds = 0
        repeat {
            repost = false
            rounds += 1
            NotificationCenter.default.post(name: .terminalTabsDidChange, object: self)
        } while repost && rounds < Self.maxRounds
        if repost {
            Self.logger.error("workspace: sets still changing after \(Self.maxRounds, privacy: .public) redraws")
        }
        repost = false
    }

    // MARK: Native moves

    /// Moves a tab by `delta` places with Ghostty's own `move_tab` action. The action acts on
    /// the selected tab, so the tab is selected for the move and the selection is restored.
    private func moveNatively(_ window: NSWindow, by delta: Int) {
        guard delta != 0, let controller = window.windowController as? TerminalController,
              let surface = controller.focusedSurface ?? controller.surfaceTree.first
        else { return }
        let previous = window.tabGroup?.selectedWindow
        hops.mark(window)
        if let previous { hops.mark(previous) }
        if previous !== window { window.makeKeyAndOrderFront(nil) }
        controller.performAction("move_tab:\(delta)", on: surface)
        if let previous, previous !== window { previous.makeKeyAndOrderFront(nil) }
        // The key notifications are queued, and Ghostty returns the key one turn later on macOS 26.
        DispatchQueue.main.async { DispatchQueue.main.async { [self] in hops.clear() } }
    }

    // MARK: Sidebar commands

    /// M1, the insertion point of `AppDelegate.ghosttyNewTab`: the tab Ghostty just opened from
    /// `window` takes its workspace, when the two share a native tab group.
    func opened(_ controller: TerminalController?, from window: NSWindow) {
        guard !book.frozen, let tab = controller?.window, group(of: window).contains(tab) else { return }
        publish(book.opened(key(for: tab), from: key(for: window)))
    }

    /// A new tab in `workspace`, right after its last tab: Ghostty's `newTab(from:)` with that tab as
    /// the parent, inheriting from it as Cmd+T inherits from the focused tab.
    func newTab(in workspace: Workspace.ID, from window: NSWindow) {
        guard !book.frozen else {
            (window.windowController as? TerminalController)?.newTab(nil)
            return
        }
        let set = book.set(of: key(for: window))
        let order = group(of: window).map(key(for:))
        let last = set?.lastTab(of: workspace, order: order).flatMap { self.window(for: $0) } ?? window
        opened(openTab(after: last, inheritingFrom: last, folder: set?.workspace(workspace)?.folder), from: last)
    }

    /// Ghostty's new tab with `parent` as the parent, configured as a tab of `source` would be;
    /// `folder` replaces the working directory. Nil when no tab came.
    private func openTab(after parent: NSWindow, inheritingFrom source: NSWindow, folder: String? = nil) -> TerminalController? {
        guard let controller = parent.windowController as? TerminalController else { return nil }
        let sourceController = source.windowController as? TerminalController
        var config = (sourceController?.focusedSurface ?? sourceController?.surfaceTree.first)?.surface.map {
            Ghostty.SurfaceConfiguration(from: ghostty_surface_inherited_config($0, GHOSTTY_SURFACE_CONTEXT_TAB))
        }
        if let folder {
            config = config ?? Ghostty.SurfaceConfiguration()
            config?.workingDirectory = folder
        }
        guard let config else { return nil }
        return TerminalController.newTab(controller.ghostty, from: parent, withBaseConfig: config)
    }

    /// A new workspace named `name` with one new tab. False for a blank name. No UI asks for
    /// a name any more (Q2); the model keeps the entry point.
    @discardableResult
    func createWorkspace(named name: String, from window: NSWindow) -> Bool {
        openWorkspace(name: name, folder: nil, from: window)
    }

    /// A workspace for `folder` with one new tab that starts in it (D19). A folder this window's
    /// set already has selects that workspace's first tab and creates nothing (Q1). False for a
    /// path that is not absolute.
    @discardableResult
    func createWorkspace(folder: String, from window: NSWindow) -> Bool {
        guard !book.frozen else { return false }
        guard let path = WorkspaceFolder.standardized(folder) else {
            Self.logger.error("workspace: folder not absolute value=\(folder, privacy: .public)")
            return false
        }
        if selectFirstTab(inFolder: path, from: window) { return true }
        // The name comes from the folder as picked: a symlink `proj` names the workspace `proj`.
        let name = WorkspaceFolder.name(of: URL(fileURLWithPath: folder).standardized.path)
        return openWorkspace(name: name, folder: path, from: window)
    }

    private func selectFirstTab(inFolder folder: String, from window: NSWindow) -> Bool {
        let order = group(of: window).map(key(for:))
        guard let set = book.set(of: key(for: window)),
              let tab = set.firstTab(inFolder: folder, order: order),
              let target = self.window(for: tab)
        else { return false }
        target.makeKeyAndOrderFront(nil)
        return true
    }

    private func openWorkspace(name: String, folder: String?, from window: NSWindow) -> Bool {
        guard !book.frozen, WorkspaceSet.cleaned(name) != nil else { return false }
        // The group stands at the bottom: its tab opens from the last tab of the window (G8).
        guard let tabWindow = openTab(after: group(of: window).last ?? window, inheritingFrom: window, folder: folder)?.window,
              group(of: window).contains(tabWindow)
        else { return false }
        sync()
        let tab = key(for: tabWindow)
        let changed = book.edit(tab) { set in
            if let created = set.create(name: name, folder: folder) { set.join(tab, to: created) }
        }
        publish(changed.map { [$0] } ?? [])
        return changed != nil
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

    /// Deletes the workspace; its tabs move up, or down for the first one.
    @discardableResult
    func delete(_ workspace: Workspace.ID, in window: NSWindow) -> Bool {
        let order = group(of: window).map(key(for:))
        var deleted = false
        edit(window) { deleted = $0.delete(workspace, order: order) }
        return deleted
    }

    /// Puts `window` in `workspace`, before `neighbour` or at the end of the workspace:
    /// membership first, then one native move.
    func moveTab(_ window: NSWindow, to workspace: Workspace.ID, before neighbour: NSWindow? = nil) {
        let tab = key(for: window)
        let order = group(of: window).map(key(for:))
        guard let index = order.firstIndex(of: tab) else { return }
        isBusy = true
        let changed = book.frozen ? nil : book.edit(tab) { $0.join(tab, to: workspace) }
        let destination = Self.destination(
            of: tab,
            in: order,
            before: neighbour.map(key(for:)),
            isMember: { [frozen = book.frozen] in frozen || book.workspace(of: $0)?.id == workspace }
        )
        moveNatively(window, by: destination - index)
        isBusy = false
        sync()
        publish(changed.map { [$0] } ?? [])
    }

    /// The place of `tab` among the other tabs of `order` after a move: before `neighbour`, or
    /// after the last other member of the workspace. A tab that is the only member of the
    /// workspace stays where it is.
    nonisolated static func destination(
        of tab: TabKey,
        in order: [TabKey],
        before neighbour: TabKey?,
        isMember: (TabKey) -> Bool
    ) -> Int {
        let others = order.filter { $0 != tab }
        if let neighbour, let at = others.firstIndex(of: neighbour) { return at }
        if let last = others.lastIndex(where: isMember) { return last + 1 }
        return order.firstIndex(of: tab) ?? others.count
    }

    /// Moves a whole workspace before `other`, or to the end: one native move per tab.
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
}
