// Based on the vertical tab sidebar from ghostty-org/ghostty PR #14562
// by Somnathumapathi and Priyans-hu, MIT License. See THIRD_PARTY.md.

import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when the tabs of any terminal window may have changed: their order, titles,
    /// colors, key equivalents, or which one is selected.
    static let terminalTabsDidChange = Notification.Name("com.daniil4545.tarn.terminalTabsDidChange")
}

/// The tabs of one terminal window's tab group, by section. Every tab is its own window with
/// its own model; only the selected tab's copy is on screen.
@MainActor
final class SidebarModel: ObservableObject {
    struct Tab: Identifiable, Equatable {
        let id: ObjectIdentifier
        /// The registry's key of the tab window; drag payloads carry it.
        let key: TabKey

        /// The 1-based position of the tab in its window.
        let index: Int
        let title: String
        /// The agent the tab runs, as `AgentProcess` names it.
        let agentProcess: String?
        let keyEquivalent: String?
        let color: TerminalTabColor
        let isSelected: Bool
        /// The agent session of the tab that needs the user most, if any surface runs one.
        let agent: AgentSession?
        /// The name of the workspace the tab sits in.
        let workspace: String
        /// The working directory of the focused surface, with the home folder as "~".
        let folder: String?
    }

    /// A workspace and its tabs in tab order. A folded workspace still lists its tabs here;
    /// the view hides them.
    struct Group: Identifiable, Equatable {
        let workspace: Workspace
        let tabs: [Tab]

        var id: Workspace.ID { workspace.id }

        /// The session among the tabs that needs the user most.
        var worstAgent: AgentSession? { SidebarModel.mostUrgent(tabs.compactMap(\.agent)) }
    }

    @Published private(set) var groups: [Group] = []

    /// The modules that are on; a change redraws what depends on them.
    @Published private(set) var modules = TarnModules.effective()

    /// The one group of the flat list shown while Workspaces is off. It has no header.
    private static let flatWorkspace = Workspace(id: UUID(uuidString: "00000000-0000-0000-0000-00000000F1A7")!, name: "")

    /// Where a drop in progress would land; the rows draw a line there.
    @Published var dropSlot: SidebarDropSlot?

    /// The tab whose card is open, if any.
    var cardTab: ObjectIdentifier? {
        didSet { if cardTab != oldValue { updateCard() } }
    }

    /// The AppKit view behind each row, which the card popover points at.
    var rowAnchors: [ObjectIdentifier: WeakView] = [:]

    /// A quick answer was given on this tab's card; it stays closed until the pointer leaves.
    var answeredTab: ObjectIdentifier?

    /// The one card popover, made when the first card opens: an `NSPopover` with its hosting
    /// controller cost about 4 ms of a window's first layout (T-149) and most windows never open one.
    private var cardStorage: TabCardPopover?

    private var card: TabCardPopover {
        if let cardStorage { return cardStorage }
        let card = TabCardPopover()
        card.onClose = { [weak self] in self?.cardTab = nil }
        card.onHoverChange = { [weak self] in
            guard let self, !self.card.isHovering, let id = self.cardTab else { return }
            self.closeCardSoon(id)
        }
        cardStorage = card
        return card
    }

    /// The tab under the pointer; a force click there opens its card at once.
    var hoveredTab: ObjectIdentifier?
    /// A force click starts as a plain click; its mouse up must not switch tabs.
    var forceClicked = false
    private var pressureMonitor: Any?

    /// The window this sidebar is shown in.
    weak var window: NSWindow? {
        didSet {
            observeWindowClose()
            // A new window is an event the registry may not have heard of yet; this is the one
            // place the sidebar asks it to look, and a redraw never reaches it.
            WorkspaceRegistry.shared.sync()
            refresh()
        }
    }

    private var observer: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var processTimer: Timer?

    init() {
        SessionRegistry.shared.start()
        TarnModuleWatcher.shared.start()

        pressureMonitor = NSEvent.addLocalMonitorForEvents(matching: .pressure) { [weak self] event in
            MainActor.assumeIsolated {
                guard event.stage == 2, let self, let hovered = self.hoveredTab,
                      self.groups.contains(where: { $0.tabs.contains { $0.id == hovered } })
                else { return }
                self.cardTab = hovered
                self.forceClicked = true
            }
            return event
        }

        observer = NotificationCenter.default.addObserver(
            forName: .terminalTabsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The observer is delivered on the main queue.
            MainActor.assumeIsolated {
                self?.refresh()

                // The tab group takes an event loop cycle to settle after a tab is added or closed.
                DispatchQueue.main.async { self?.refresh() }
            }
        }

        // The core has no event for a new foreground process. A title change catches most
        // agent starts and exits; this timer catches the rest. Hidden and covered windows skip it.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window?.occlusionState.contains(.visible) == true else { return }
                self.refresh()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        processTimer = timer
    }

    deinit {
        processTimer?.invalidate()
        if let pressureMonitor {
            NSEvent.removeMonitor(pressureMonitor)
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
    }

    /// Forgets the window once it closes. Asking AppKit for a closed window's tabs (as a
    /// late refresh would) registers it with a tab group again, which keeps it alive.
    private func observeWindowClose() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        guard let window else { return }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window = nil
            }
        }
    }

    /// The windows in our tab group in tab order. A window that isn't tabbed is its own only tab.
    private var tabWindows: [NSWindow] {
        guard let window else { return [] }
        return window.tabbedWindows ?? [window]
    }

    func refresh() {
        // Read only: the registry follows Ghostty by its own observers. A redraw that asked it to
        // look again made `sync` -> `publish` -> redraw -> `sync` a loop.
        let registry = WorkspaceRegistry.shared
        guard let window else {
            if !groups.isEmpty { groups = [] }
            return
        }
        WorkspaceTitle.apply(to: window)
        let effective = TarnModules.effective()
        if modules != effective { modules = effective }
        let flat = !effective.contains(.workspaces)

        // The window only carries a key equivalent label while it is in a tab group, so a
        // lone tab would have none. Look the shortcuts up from the keybinds instead.
        let config = (window.windowController as? BaseTerminalController)?.ghostty.config
        let positions = Dictionary(uniqueKeysWithValues: tabWindows.enumerated().map { (ObjectIdentifier($1), $0 + 1) })

        // Workspaces off: one flat list in the order of the native tabs, whatever the frozen workspaces say.
        let runs = flat
            ? [WorkspaceRun(workspace: Self.flatWorkspace, windows: tabWindows)]
            : registry.runs(for: window)
        let newGroups = runs.map { run in
            Group(workspace: run.workspace, tabs: run.windows.compactMap { tabWindow -> Tab? in
                guard let index = positions[ObjectIdentifier(tabWindow)], let key = registry.tabKey(of: tabWindow)
                else { return nil }
                let shortcut = index <= 9 ? config?.keyboardShortcut(for: "goto_tab:\(index)") : nil
                return makeTab(tabWindow, key: key, index: index, workspace: flat ? "" : run.workspace.name, shortcut: shortcut.map { "\($0)" })
            })
        }
        guard newGroups != groups else { return }
        groups = newGroups
        if cardTab != nil { updateCard() }
    }

    private func makeTab(_ tabWindow: NSWindow, key: TabKey, index: Int, workspace: String, shortcut: String?) -> Tab {
        let controller = tabWindow.windowController as? BaseTerminalController
        let views = controller.map { Array($0.surfaceTree) } ?? []
        let agents = views.map { view in
            view.surfaceModel?.foregroundPID
                .flatMap { pid_t(exactly: $0) }
                .flatMap(AgentProcessCache.agent)
        }
        let pane = Self.textPane(views.map(\.id), agents: agents, sessions: SessionRegistry.shared.sessions)
        let agent = pane.flatMap { agents[$0] } ?? agents.lazy.compactMap { $0 }.first
        let pwd = (pane.map { views[$0] } ?? controller?.focusedSurface)?.workingDirectory
        // The window title is the focused pane's; a split tab names the pane of its dot.
        let paneTitle = views.count > 1 ? pane.map { views[$0].title }.flatMap { $0.isEmpty ? nil : $0 } : nil
        return Tab(
            id: ObjectIdentifier(tabWindow),
            key: key,
            index: index,
            title: Self.displayTitle(paneTitle ?? tabWindow.title, pwd: pwd, agent: agent),
            agentProcess: agent,
            keyEquivalent: shortcut,
            color: (tabWindow as? TerminalWindow)?.tabColor ?? .none,
            // Our window is only on screen while it is the selected tab.
            isSelected: tabWindow === window,
            agent: Self.agent(in: controller),
            workspace: workspace,
            folder: pwd.map { Self.displayTitle("/", pwd: $0) }
        )
    }

    /// The session that needs the user most: permission, then working, then done and unseen.
    /// The pane whose folder and agent name the row shows: the pane of its state dot, else the
    /// first pane running an agent. Text and dot then speak of one pane in a split tab.
    nonisolated static func textPane(_ panes: [UUID], agents: [String?], sessions: [UUID: AgentSession]) -> Int? {
        if let urgent = mostUrgent(panes.compactMap { sessions[$0] }) {
            return panes.firstIndex(of: urgent.surfaceID)
        }
        return agents.firstIndex { $0 != nil }
    }

    nonisolated static func mostUrgent(_ sessions: [AgentSession]) -> AgentSession? {
        sessions
            .filter { $0.state != .idle }
            .max { a, b in (a.state, a.isUnseenDone ? 1 : 0) < (b.state, b.isUnseenDone ? 1 : 0) }
    }

    /// Shows the card of `cardTab` beside its row, or closes it.
    private func updateCard() {
        guard let id = cardTab,
              let tab = groups.lazy.flatMap(\.tabs).first(where: { $0.id == id }),
              let anchor = rowAnchors[id]?.view, anchor.window != nil
        else {
            cardStorage?.close()
            return
        }
        card.show(tab, anchor: anchor) { [weak self] in
            self?.answeredTab = id
            self?.cardTab = nil
        }
    }

    /// Closes `id`'s card unless the pointer comes back to its row or the card.
    func closeCardSoon(_ id: ObjectIdentifier) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.cardTab == id, self.hoveredTab != id, !self.card.isHovering else { return }
            self.cardTab = nil
        }
    }

    /// The session among the tab's splits that needs the user most.
    private static func agent(in controller: BaseTerminalController?) -> AgentSession? {
        guard let controller else { return nil }
        let sessions = SessionRegistry.shared.sessions
        return mostUrgent(controller.surfaceTree.compactMap { sessions[$0.id] })
    }

    /// The tab title to show: a shell's path title becomes the full working directory with "~";
    /// under an agent, a shell title becomes the agent's name and an own title loses its mark.
    nonisolated static func displayTitle(_ title: String, pwd: String?, agent: String? = nil) -> String {
        if let agent, let name = AgentProcess.displayNames[agent] {
            // Agents lead their titles with a spinner or a mark (`✳`, `⠏`); the icon and
            // the state dot already show both.
            let text = String(title.drop { !$0.isLetter && !$0.isNumber && !"/~…".contains($0) })
            if isShellTitle(text, pwd: pwd) { return name }
            if text != title { return text }
        }
        guard let pwd, !pwd.isEmpty, let first = title.first, "/~…".contains(first) else { return title }
        let home = NSHomeDirectory()
        if pwd == home { return "~" }
        if pwd.hasPrefix(home + "/") { return "~" + pwd.dropFirst(home.count) }
        return pwd
    }

    /// A title a shell sets: empty, a path, or the name of the working folder.
    private nonisolated static func isShellTitle(_ title: String, pwd: String?) -> Bool {
        guard let first = title.first else { return true }
        if "/~…".contains(first) { return true }
        guard let pwd, !pwd.isEmpty else { return false }
        return title == (pwd as NSString).lastPathComponent
    }

    // MARK: Commands

    private var registry: WorkspaceRegistry { .shared }

    /// A tab in the current workspace.
    func newTab() {
        guard let window else { return }
        if let workspace = registry.workspace(of: window) {
            registry.newTab(in: workspace.id, from: window)
        } else {
            (window.windowController as? TerminalController)?.newTab(nil)
        }
    }

    func newTab(in group: Group) {
        guard let window else { return }
        registry.newTab(in: group.workspace.id, from: window)
    }

    /// Opens, shows or hides the viewer pane of the window, as Cmd+B does.
    func toggleViewer() {
        (window?.windowController as? TerminalController)?.toggleViewer(nil)
    }

    func newWorkspace() {
        guard let window else { return }
        WorkspacePrompt.newWorkspace(in: window)
    }

    func rename(_ group: Group) {
        guard let window else { return }
        WorkspacePrompt.askName(title: "Rename Workspace", message: "", initial: group.workspace.name, in: window) { [weak self] name in
            guard let self, let window = self.window else { return }
            self.registry.rename(group.workspace.id, to: name, in: window)
        }
    }

    func delete(_ group: Group) {
        guard let window, let index = groups.firstIndex(where: { $0.id == group.id }), groups.count > 1 else { return }
        let heir = groups[index > 0 ? index - 1 : index + 1].workspace.name
        WorkspacePrompt.confirmDelete(group.workspace.name, tabCount: group.tabs.count, heir: heir, in: window) { [weak self] in
            guard let self, let window = self.window else { return }
            self.registry.delete(group.workspace.id, in: window)
        }
    }

    func toggleFold(_ group: Group) {
        guard let window else { return }
        registry.setCollapsed(group.workspace.id, !group.workspace.collapsed, in: window)
    }

    func select(_ tab: Tab) {
        tabWindow(for: tab)?.makeKeyAndOrderFront(nil)
    }

    func close(_ tab: Tab) {
        controller(for: tab)?.closeTab(nil)
    }

    /// Closes `tabs` as one undoable step. A tab with a running process asks first.
    private func close(_ tabs: [Tab], title: String, from tab: Tab) {
        let controllers = tabs.compactMap { controller(for: $0) }
        guard let anchor = controller(for: tab), !controllers.isEmpty else { return }
        let closeAll = {
            anchor.undoManager?.beginUndoGrouping()
            for controller in controllers { controller.closeTabImmediately(registerRedo: false) }
            anchor.undoManager?.setActionName(title)
            anchor.undoManager?.endUndoGrouping()
        }
        // Unsaved viewer edits of any closing tab are settled first (never lost).
        let settled = { [window] in
            if ViewerClose.intercept(controllers, window: window, proceed: closeAll) { return }
            closeAll()
        }
        guard controllers.contains(where: { $0.surfaceTree.contains { $0.needsConfirmQuit } }) else {
            settled()
            return
        }
        anchor.confirmClose(
            messageText: "\(title)?",
            informativeText: "At least one of these tabs still has a running process. If you close the tab the process will be killed.",
            completion: settled
        )
    }

    /// The tabs of `tab`'s workspace (the close commands stay inside it).
    private func siblings(of tab: Tab) -> [Tab] {
        groups.first { $0.tabs.contains { $0.id == tab.id } }?.tabs ?? []
    }

    /// The right-click menu for a tab, with the items of a native tab's menu.
    func contextMenu(for tab: Tab) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let siblings = siblings(of: tab)
        let below = siblings.filter { $0.index > tab.index }
        menu.addItem(menuItem("Close Tab") { [weak self] in
            self?.close(tab)
        })
        menu.addItem(menuItem("Close Other Tabs", isEnabled: siblings.count > 1) { [weak self] in
            self?.close(siblings.filter { $0.id != tab.id }, title: "Close Other Tabs", from: tab)
        })
        menu.addItem(menuItem("Close Tabs Below", isEnabled: !below.isEmpty) { [weak self] in
            self?.close(below, title: "Close Tabs Below", from: tab)
        })
        menu.addItem(menuItem("Move Tab to New Window", isEnabled: tabWindows.count > 1) { [weak self] in
            self?.tabWindow(for: tab)?.moveTabToNewWindow(nil)
        })
        menu.addItem(.separator())

        let moveTo = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for group in groups {
            let isCurrent = group.tabs.contains { $0.id == tab.id }
            submenu.addItem(menuItem(group.workspace.name, isEnabled: !isCurrent) { [weak self] in
                guard let window = self?.tabWindow(for: tab) else { return }
                self?.registry.moveTab(window, to: group.workspace.id)
            })
        }
        moveTo.submenu = submenu
        moveTo.isEnabled = groups.count > 1
        if modules.contains(.workspaces) {
            menu.addItem(moveTo)
            menu.addItem(.separator())
        }
        menu.addItem(menuItem("Rename Tab...") { [weak self] in
            self?.select(tab)
            self?.controller(for: tab)?.promptTabTitle()
        })

        return menu
    }

    /// The right-click menu for a workspace header.
    func contextMenu(for group: Group) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem("New Tab") { [weak self] in
            self?.newTab(in: group)
        })
        menu.addItem(menuItem(group.workspace.collapsed ? "Expand" : "Collapse") { [weak self] in
            self?.toggleFold(group)
        })
        menu.addItem(.separator())
        menu.addItem(menuItem("Rename Workspace...") { [weak self] in
            self?.rename(group)
        })
        menu.addItem(menuItem("Delete Workspace...", isEnabled: groups.count > 1) { [weak self] in
            self?.delete(group)
        })
        return menu
    }

    // MARK: Drag and drop

    /// A drag is over a row or header. True when the drop would do something: a payload from
    /// another window shows no line, as its drop is refused.
    func dragOver(_ kind: SidebarDragKind, value: String, over target: SidebarDropTarget, lowerHalf: Bool) -> Bool {
        let slot = isOwn(kind, value: value)
            ? Self.dropSlot(dragging: kind, over: target, lowerHalf: lowerHalf, in: groups)
            : nil
        if dropSlot != slot { dropSlot = slot }
        return slot != nil
    }

    /// The dragged tab or workspace belongs to this window.
    private func isOwn(_ kind: SidebarDragKind, value: String) -> Bool {
        guard let id = UUID(uuidString: value) else { return false }
        switch kind {
        case .tab: return tab(withKey: id) != nil
        case .workspace: return groups.contains { $0.id == id }
        }
    }

    func dragExit() {
        if dropSlot != nil { dropSlot = nil }
    }

    /// Carries out a drop; `value` is the payload of the drag. A payload from another window
    /// is refused: moving tabs between windows is Ghostty's.
    func drop(_ kind: SidebarDragKind, value: String, over target: SidebarDropTarget, lowerHalf: Bool) -> Bool {
        guard let window, let id = UUID(uuidString: value),
              let slot = Self.dropSlot(dragging: kind, over: target, lowerHalf: lowerHalf, in: groups)
        else { return false }

        switch (kind, slot) {
        case (.tab, .beforeTab(let key)):
            guard let moving = tab(withKey: id).flatMap(tabWindow(for:)),
                  let group = groups.first(where: { $0.tabs.contains { $0.key == key } }),
                  let neighbour = group.tabs.first(where: { $0.key == key }).flatMap(tabWindow(for:))
            else { return false }
            if moving !== neighbour { registry.moveTab(moving, to: group.workspace.id, before: neighbour) }
            return true

        case (.tab, .endOfWorkspace(let workspace)):
            guard let moving = tab(withKey: id).flatMap(tabWindow(for:)) else { return false }
            registry.moveTab(moving, to: workspace)
            return true

        case (.workspace, .beforeWorkspace(let other)):
            guard groups.contains(where: { $0.id == id }) else { return false }
            if other != id { registry.moveWorkspace(id, before: other, in: window) }
            return true

        case (.workspace, .end):
            guard groups.contains(where: { $0.id == id }) else { return false }
            registry.moveWorkspace(id, before: nil, in: window)
            return true

        default:
            return false
        }
    }

    /// A tab drag ended. Nobody took it and it is outside every window: the tab leaves for a
    /// window of its own.
    func dragEnded(_ tab: Tab, at screenPoint: NSPoint, accepted: Bool) {
        dragExit()
        guard !accepted, tabWindows.count > 1,
              !NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(screenPoint) })
        else { return }
        tabWindow(for: tab)?.moveTabToNewWindow(nil)
    }

    private func tab(withKey key: TabKey) -> Tab? {
        groups.lazy.flatMap(\.tabs).first { $0.key == key }
    }

    private func menuItem(_ title: String, isEnabled: Bool = true, handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run(_:)), keyEquivalent: "")
        item.target = action
        // The item's target is weak, so the item itself keeps the action alive.
        item.representedObject = action
        item.isEnabled = isEnabled
        return item
    }

    /// Runs a closure as a menu item's action. The method is not called `perform`: the
    /// selector `MenuAction.perform(_:)` resolves to `NSObject.perform(_:)` (`performSelector:`),
    /// so every item of the menus once sent the wrong message and did nothing.
    private final class MenuAction: NSObject {
        private let handler: () -> Void

        init(_ handler: @escaping () -> Void) {
            self.handler = handler
        }

        @objc func run(_ sender: Any?) {
            handler()
        }
    }

    private func tabWindow(for tab: Tab) -> NSWindow? {
        tabWindows.first { ObjectIdentifier($0) == tab.id }
    }

    private func controller(for tab: Tab) -> TerminalController? {
        tabWindow(for: tab)?.windowController as? TerminalController
    }
}

/// Places the sidebar beside a terminal window's content.
struct SidebarLayout<Content: View>: View {
    @ObservedObject var model: SidebarModel
    @ObservedObject var ghostty: Ghostty.App
    let content: Content

    @AppStorage(Sidebar.collapsedKey) private var isCollapsed = false
    @AppStorage(Sidebar.widthKey) private var width = Sidebar.defaultWidth
    @AppStorage(TabStyle.key) private var tabStyle: TabStyle = .sidebar

    /// The sidebar width when the current resize drag began.
    @State private var widthAtDragStart: Double?
    /// The width during a resize drag. It is stored once the drag ends: a stored width
    /// re-lays out every tab window, hidden ones included, which made the drag stutter.
    @State private var dragWidth: Double?
    @State private var dividerHovered = false

    /// `dragWidth` starts a layout as if a resize drag were under way; tests use it.
    init(model: SidebarModel, ghostty: Ghostty.App, dragWidth: Double? = nil, @ViewBuilder content: () -> Content) {
        self.model = model
        self.ghostty = ghostty
        self.content = content()
        _dragWidth = State(initialValue: dragWidth)
    }

    var body: some View {
        if tabStyle == .top {
            content
        } else {
            sidebarAndContent
        }
    }

    private var layoutWidth: Double {
        Sidebar.widths(isCollapsed: isCollapsed, stored: width, drag: dragWidth).layout
    }

    private var shownWidth: Double {
        Sidebar.widths(isCollapsed: isCollapsed, stored: width, drag: dragWidth).shown
    }

    private var sidebarAndContent: some View {
        HStack(spacing: 0) {
            sidebarColumn
                // Above the terminal beside it: the grab zone and, while the sidebar is
                // dragged wider, the sidebar itself lie over the terminal.
                .zIndex(1)

            content
        }
    }

    /// Live resize without a terminal resize. Every frame of a drag would give the terminal a new
    /// size, and each size is a pty resize, a reflow and a SIGWINCH for the shell. The column
    /// therefore holds its space in the layout at the width the drag began with, and the
    /// sidebar and its divider are drawn over that space, reaching past it when the sidebar
    /// grows. The terminal keeps its size until the mouse is released; then the stored width
    /// changes the layout once. This is the deferred resize of an `NSSplitView` that
    /// does not adjust its subviews while the divider moves, and the same idea as cmux's
    /// coalesced resizes during a divider drag (changelog 0.64.20; behavior only, not code).
    private var sidebarColumn: some View {
        Color.clear
            .frame(width: layoutWidth + Sidebar.dividerWidth)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    Sidebar(model: model, isCollapsed: $isCollapsed)
                        .frame(width: shownWidth)
                        .background(sidebarFill)
                        .environment(\.colorScheme, isLightTheme ? .light : .dark)
                        .environment(\.chromeInk, ink)
                        .foregroundStyle(ink.text())

                    divider
                        .zIndex(1)

                    // The sidebar is narrower than its held space: the rest takes the sidebar's fill, so the
                    // edge moves with the pointer and the terminal stays where it is.
                    if shownWidth < layoutWidth {
                        sidebarFill.frame(width: layoutWidth - shownWidth).allowsHitTesting(false)
                    }
                }
            }
    }

    /// The colors of the terminal theme (`window-theme` auto or ghostty), or nil for the built-in
    /// palettes. Config changes arrive through `ghostty.config`, so a theme change repaints at once.
    private var ink: ChromeInk {
        ChromeInk(theme: ThemeChrome.current(for: ghostty.config))
    }

    private var isLightTheme: Bool {
        ink.theme?.isLight ?? NSColor(ghostty.config.backgroundColor).isLightColor
    }

    private var sidebarFill: Color {
        let base = ink.theme?.surface.color ?? ghostty.config.backgroundColor
        return base.opacity(ghostty.config.backgroundOpacity)
    }

    /// The line between the sidebar and the terminal. In the expanded sidebar it carries the
    /// grab zone that resizes it, the way Ghostty's `SplitView.Divider` does: a visible line
    /// in a wider transparent frame that straddles the edge.
    private var divider: some View {
        ZStack {
            if !isCollapsed {
                Color.clear
                    .frame(width: Sidebar.edgeGrabWidth)
                    .contentShape(Rectangle())
                    .gesture(resizeGesture)
                    .backport.pointerStyle(.resizeLeftRight)
                    .onHover { isHovering in
                        // macOS 15 and later use the pointer style above.
                        if #available(macOS 15, *) { return }
                        if isHovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .onHover { dividerHovered = $0 }
                    // Most of the zone lies over the sidebar: the terminal keeps its first columns.
                    .offset(x: -Sidebar.edgeGrabOffset)
            }
            Rectangle()
                // The theme's accent marks the grab zone while the pointer is on it or it is dragged.
                .fill(dividerHovered || dragWidth != nil ? ink.accent : ink.divider)
                .frame(width: Sidebar.dividerWidth)
        }
        .frame(width: Sidebar.dividerWidth)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = widthAtDragStart ?? Sidebar.clampedWidth(width)
                widthAtDragStart = start
                dragWidth = Sidebar.clampedWidth(start + value.translation.width)
            }
            .onEnded { _ in
                if let dragWidth { width = dragWidth }
                dragWidth = nil
                widthAtDragStart = nil
            }
    }
}

/// The vertical list of a terminal window's tabs, replacing the native tab bar.
struct Sidebar: View {
    static let collapsedKey = "TarnSidebarCollapsed"
    static let widthKey = "TarnSidebarWidth"
    static let defaultWidth: Double = 200
    static let widthRange: ClosedRange<Double> = 120...400
    /// The width of the transparent zone over the sidebar's edge that takes the resize drag.
    /// Mostly over the sidebar: `edgeGrabOverTerminal` points of it reach the terminal.
    static let edgeGrabWidth: CGFloat = 14
    /// How much of the zone lies over the terminal: its first column and the click or selection
    /// that starts at the edge of a line must reach the terminal (3 pt, as Ghostty's divider takes).
    static let edgeGrabOverTerminal: CGFloat = 3
    /// How far the zone moves left of its centered place on the line.
    static var edgeGrabOffset: CGFloat { (edgeGrabWidth - CGFloat(dividerWidth)) / 2 - edgeGrabOverTerminal }
    static let collapsedWidth: Double = 40
    static let dividerWidth: Double = 1
    /// The space at the sides of the list and between rows. Rows and headers pad themselves
    /// with it instead of the list, so their drop targets touch and a drag over a gap keeps
    /// its line.
    static let listInset: CGFloat = 6
    static let rowGap: CGFloat = 2

    /// `width` held in `widthRange`. A stored value outside the range, or not a number, would
    /// draw a sidebar that is hidden, too wide or of no width, so it falls back instead.
    static func clampedWidth(_ width: Double) -> Double {
        guard width.isFinite else { return defaultWidth }
        return min(max(width.rounded(), widthRange.lowerBound), widthRange.upperBound)
    }

    /// The width the sidebar holds in the layout, which sets the terminal's size, and the width it
    /// is drawn at. They differ only during a resize drag: the drag moves the drawn width and
    /// leaves the layout alone until it ends.
    static func widths(isCollapsed: Bool, stored: Double, drag: Double?) -> (layout: Double, shown: Double) {
        guard !isCollapsed else { return (collapsedWidth, collapsedWidth) }
        let layout = clampedWidth(stored)
        return (layout, drag.map(clampedWidth) ?? layout)
    }

    /// The width the sidebar and its divider currently take out of a window's content.
    static var occupiedWidth: CGFloat {
        let defaults = UserDefaults.standard
        if TabStyle.current == .top {
            return 0
        }
        if defaults.bool(forKey: collapsedKey) {
            return collapsedWidth + dividerWidth
        }

        let width = clampedWidth(defaults.object(forKey: widthKey) as? Double ?? defaultWidth)
        return width + dividerWidth
    }

    @ObservedObject var model: SidebarModel
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isCollapsed {
                VStack(spacing: 4) {
                    collapseButton
                    if model.modules.contains(.viewer) { viewerButton }
                    newTabButton
                }
                .padding(.vertical, 6)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // The rail has no headers, so it lists every tab, folded or not.
                        ForEach(model.groups) { group in
                            ForEach(group.tabs) { tab in
                                SidebarRow(model: model, tab: tab, isCompact: true)
                            }
                        }
                    }
                }
            } else {
                HStack {
                    collapseButton
                    // New Workspace sits next to Hide Sidebar, as in the demo.
                    if model.modules.contains(.workspaces) { newWorkspaceButton }
                    Spacer()
                    if model.modules.contains(.viewer) { viewerButton }
                    newTabButton
                }
                .padding(.horizontal, 6)
                .frame(height: 36)

                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(model.groups) { group in
                                    if model.modules.contains(.workspaces) {
                                        WorkspaceHeader(model: model, group: group)
                                    }
                                    ForEach(visibleTabs(of: group)) { tab in
                                        SidebarRow(model: model, tab: tab, isCompact: false)
                                            .transition(.opacity)
                                    }
                                }
                            }
                            // Only a fold or unfold animates: a title change or a reorder keeps
                            // its jump, as the rows of a moved tab are not new rows.
                            .animation(Motion.fold, value: foldedWorkspaces)
                            // The rest of the height takes drops after the last row.
                            tail.frame(maxWidth: .infinity, minHeight: 24, maxHeight: .infinity)
                        }
                        .frame(minHeight: proxy.size.height)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The workspaces that are folded, which the fold animation follows.
    private var foldedWorkspaces: [Workspace.ID] {
        model.groups.filter(\.workspace.collapsed).map(\.id)
    }

    /// A folded workspace shows no tabs; selecting one of them unfolds it.
    private func visibleTabs(of group: SidebarModel.Group) -> [SidebarModel.Tab] {
        group.workspace.collapsed ? [] : group.tabs
    }

    private var tail: some View {
        Color.clear.overlay(
            SidebarInteraction(
                onClick: {},
                dragOver: { kind, value, _ in model.dragOver(kind, value: value, over: .tail, lowerHalf: true) },
                dragExit: { model.dragExit() },
                drop: { kind, value, _ in model.drop(kind, value: value, over: .tail, lowerHalf: true) }
            )
        )
    }

    private var collapseButton: some View {
        SidebarButton(systemName: "sidebar.left", label: isCollapsed ? "Show Sidebar" : "Hide Sidebar") {
            isCollapsed.toggle()
        }
    }

    private var viewerButton: some View {
        SidebarButton(systemName: "sidebar.right", label: "Toggle File Viewer") {
            model.toggleViewer()
        }
    }

    private var newWorkspaceButton: some View {
        SidebarButton(systemName: "folder.badge.plus", label: "New Workspace") {
            model.newWorkspace()
        }
    }

    private var newTabButton: some View {
        SidebarButton(systemName: "plus", label: "New Tab") {
            model.newTab()
        }
    }
}

/// A flat icon button in the sidebar.
private struct SidebarButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 26
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.chromeInk) private var ink

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .medium))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(ink.text(isHovering ? 0.12 : 0))
                        .animation(Motion.hover, value: isHovering)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink.muted)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// One tab in the sidebar: a row when the sidebar is expanded, or a tile showing its key
/// equivalent in the collapsed rail.
private struct SidebarRow: View {
    @ObservedObject var model: SidebarModel
    let tab: SidebarModel.Tab
    let isCompact: Bool

    @State private var isHovering = false
    @AppStorage(TabRows.key) private var rows: TabRows = .wide
    @Environment(\.chromeInk) private var ink

    var body: some View {
        content
            .font(.system(size: 13))
            .foregroundStyle(ink.text(tab.isSelected ? 1 : 0.7))
            // Scoped to the fill: the close button and the card logic still switch at once.
            .background(RoundedRectangle(cornerRadius: 5).fill(fill).animation(Motion.hover, value: fill))
            .background(RowAnchor { model.rowAnchors[tab.id] = WeakView(view: $0) })
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    model.hoveredTab = tab.id
                } else if model.hoveredTab == tab.id {
                    model.hoveredTab = nil
                }
                scheduleCard()
            }
            .help(isCompact ? tab.title : "")
            .overlay(alignment: .top) { dropLine(model.dropSlot == .beforeTab(tab.key)) }
            .overlay(alignment: .bottom) { dropLine(endsHere) }
            .padding(.vertical, Sidebar.rowGap / 2)
            .padding(.horizontal, isCompact ? 0 : Sidebar.listInset)
            .overlay(interaction)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rows == .wide && !folder.isEmpty ? "\(tab.title), \(folder)" : tab.title)
            .accessibilityAddTraits(tab.isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.select(tab) }
    }

    /// The drop line goes under the last tab of a workspace dropped at its end, and under the
    /// last tab of the last workspace for a drop after every workspace.
    private var endsHere: Bool {
        let group: SidebarModel.Group?
        switch model.dropSlot {
        case .endOfWorkspace(let id): group = model.groups.first { $0.id == id }
        case .end: group = model.groups.last
        default: group = nil
        }
        return group?.tabs.last?.key == tab.key
    }

    private var interaction: some View {
        SidebarInteraction(
            payload: { (.tab, tab.key.uuidString) },
            onClick: {
                if model.forceClicked {
                    model.forceClicked = false
                } else {
                    model.select(tab)
                }
            },
            menu: { model.contextMenu(for: tab) },
            dragOver: { kind, value, lowerHalf in
                model.dragOver(kind, value: value, over: .tab(tab.key), lowerHalf: lowerHalf)
            },
            dragExit: { model.dragExit() },
            drop: { kind, value, lowerHalf in
                model.drop(kind, value: value, over: .tab(tab.key), lowerHalf: lowerHalf)
            },
            dragEnded: { point, accepted in model.dragEnded(tab, at: point, accepted: accepted) },
            // The close button of an expanded row sits in its first 22 points after the inset.
            excludedLeading: isCompact ? 0 : Sidebar.listInset + 22
        )
    }

    /// Hover opens the card only for a tab with an agent; any tab's card opens with a force
    /// click. While a card is open it moves at once to the next agent row, like tooltips do.
    private func scheduleCard() {
        if !isHovering && model.answeredTab == tab.id { model.answeredTab = nil }
        let opens = tab.agent != nil && isHovering && model.answeredTab != tab.id

        if opens && model.cardTab != nil && model.cardTab != tab.id {
            model.cardTab = tab.id
            return
        }

        if isHovering {
            guard opens else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if isHovering && model.answeredTab != tab.id { model.cardTab = tab.id }
            }
        } else {
            model.closeCardSoon(tab.id)
        }
    }

    private var fill: Color {
        if tab.isSelected { return ink.text(0.14) }
        return ink.text(isHovering ? 0.07 : 0)
    }

    @ViewBuilder
    private var content: some View {
        if isCompact {
            // Only icons: the agent's logo, or a terminal for a plain tab. The title is in the tooltip.
            icon(size: 14)
                .frame(width: 30, height: 28)
                .overlay(alignment: .topTrailing) {
                    if let agent = tab.agent { AgentBadge(agent: agent).scaleEffect(0.8) }
                }
        } else {
            row
        }
    }

    private func icon(size: CGFloat) -> some View {
        TabIcon(agentProcess: tab.agentProcess, size: size)
    }

    /// A wide row puts the second line under the title; badge and key stay on the first line.
    private var row: some View {
        VStack(alignment: .leading, spacing: 1) {
            firstLine
            if rows == .wide {
                detail
                    .padding(.leading, tab.agentProcess != nil ? 38 : 22)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: rows == .wide ? 40 : 26)
    }

    private var firstLine: some View {
        HStack(spacing: 4) {
            // The close button only shows on hover. Its slot is always reserved so the
            // title doesn't shift.
            ZStack {
                if isHovering {
                    SidebarButton(systemName: "xmark", label: "Close Tab", size: 16) {
                        model.close(tab)
                    }
                } else if let color = tab.color.displayColor {
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 7, height: 7)
                }
            }
            .frame(width: 18, height: 18)

            if tab.agentProcess != nil {
                icon(size: 12)
            }

            title

            Spacer(minLength: 4)

            if let agent = tab.agent {
                AgentBadge(agent: agent)
            }

            if let keyEquivalent = tab.keyEquivalent {
                Text(keyEquivalent)
                    .font(.system(size: 11))
                    .foregroundStyle(ink.faint)
            }
        }
    }

    private var title: some View {
        Text(tab.title)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// The second line of a wide row: the folder, and for an agent the time in its state. The
    /// icon names the agent. Minutes only, so the row redraws once a minute, not every second.
    /// A plain shell often has its folder as the title, which the line then leaves out.
    private var folder: String {
        guard let folder = tab.folder, tab.agent != nil || folder != tab.title else { return "" }
        return folder
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            if let agent = tab.agent {
                TimelineView(.everyMinute) { context in
                    Text(TabRows.secondLine(folder: folder, since: agent.since, now: context.date))
                }
            } else {
                Text(folder)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(ink.faint)
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

/// A tab's agent logo, or a terminal for a plain tab.
struct TabIcon: View {
    let agentProcess: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let name = agentProcess.flatMap({ AgentProcess.icons[$0] }) {
                Image(name).resizable()
            } else {
                Image(systemName: "terminal").resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The state dot and agent logo of a native tab, used when tabs are at the top.
/// It reads the same `SidebarModel` the sidebar draws from.
struct NativeTabMark: View {
    @ObservedObject var model: SidebarModel
    let id: ObjectIdentifier

    @AppStorage(TabStyle.key) private var tabStyle: TabStyle = .sidebar

    var body: some View {
        if tabStyle == .top, let tab = model.groups.lazy.flatMap(\.tabs).first(where: { $0.id == id }) {
            let name = Self.workspaceName(tab.workspace, workspacesOn: model.modules.contains(.workspaces))
            if name != nil || tab.agentProcess != nil {
                HStack(spacing: 6) {
                    if let name {
                        Text(name)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 90)
                    }
                    if let agent = tab.agent {
                        AgentBadge(agent: agent)
                    }
                    if tab.agentProcess != nil {
                        TabIcon(agentProcess: tab.agentProcess, size: 12)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// The workspace name a native tab shows, or nil while Workspaces is off or the name is empty.
    nonisolated static func workspaceName(_ name: String, workspacesOn: Bool) -> String? {
        workspacesOn && !name.isEmpty ? name : nil
    }

    /// Puts the mark first in the accessory stack Ghostty gives every native tab.
    @MainActor static func install(in window: NSWindow, model: SidebarModel) {
        guard let stack = window.tab.accessoryView as? NSStackView else { return }
        stack.insertArrangedSubview(NSHostingView(rootView: NativeTabMark(model: model, id: ObjectIdentifier(window))), at: 0)
    }
}

struct WeakView {
    weak var view: NSView?
}

/// An empty AppKit view behind a row, so the card popover can point at the row itself.
private struct RowAnchor: NSViewRepresentable {
    let register: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        register(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        register(nsView)
    }
}
