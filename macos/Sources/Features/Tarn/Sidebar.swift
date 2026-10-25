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

    private let card = TabCardPopover()

    /// The tab under the pointer; a force click there opens its card at once.
    var hoveredTab: ObjectIdentifier?
    /// A force click starts as a plain click; its mouse up must not switch tabs.
    var forceClicked = false
    private var pressureMonitor: Any?

    /// The window this sidebar is shown in.
    weak var window: NSWindow? {
        didSet {
            observeWindowClose()
            refresh()
        }
    }

    private var observer: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var processTimer: Timer?

    init() {
        SessionRegistry.shared.start()

        card.onClose = { [weak self] in self?.cardTab = nil }
        card.onHoverChange = { [weak self] in
            guard let self, !self.card.isHovering, let id = self.cardTab else { return }
            self.closeCardSoon(id)
        }

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
        // The registry follows Ghostty's tab order first, so the runs below are current.
        let registry = WorkspaceRegistry.shared
        registry.sync()
        guard let window else {
            if !groups.isEmpty { groups = [] }
            return
        }

        // The window only carries a key equivalent label while it is in a tab group, so a
        // lone tab would have none. Look the shortcuts up from the keybinds instead.
        let config = (window.windowController as? BaseTerminalController)?.ghostty.config
        let positions = Dictionary(uniqueKeysWithValues: tabWindows.enumerated().map { (ObjectIdentifier($1), $0 + 1) })

        let newGroups = registry.runs(for: window).map { run in
            Group(workspace: run.workspace, tabs: run.windows.compactMap { tabWindow -> Tab? in
                guard let index = positions[ObjectIdentifier(tabWindow)], let key = registry.tabKey(of: tabWindow)
                else { return nil }
                let shortcut = index <= 9 ? config?.keyboardShortcut(for: "goto_tab:\(index)") : nil
                return makeTab(tabWindow, key: key, index: index, workspace: run.workspace.name, shortcut: shortcut.map { "\($0)" })
            })
        }
        guard newGroups != groups else { return }
        groups = newGroups
        if cardTab != nil { updateCard() }
    }

    private func makeTab(_ tabWindow: NSWindow, key: TabKey, index: Int, workspace: String, shortcut: String?) -> Tab {
        let controller = tabWindow.windowController as? BaseTerminalController
        let running = controller?.surfaceTree.lazy
            .compactMap { view in
                view.surfaceModel?.foregroundPID
                    .flatMap { pid_t(exactly: $0) }
                    .flatMap(AgentProcess.agent)
                    .map { (view: view, agent: $0) }
            }
            .first
        let pwd = (running?.view ?? controller?.focusedSurface)?.pwd
        return Tab(
            id: ObjectIdentifier(tabWindow),
            key: key,
            index: index,
            title: Self.displayTitle(tabWindow.title, pwd: pwd, agent: running?.agent),
            agentProcess: running?.agent,
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
            card.close()
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

    /// A tab in the current workspace (D2).
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

    func newWorkspace() {
        guard let window else { return }
        WorkspacePrompt.askName(title: "New Workspace", message: "The workspace opens with one new tab.", initial: "", in: window) { [weak self] name in
            guard let self, let window = self.window else { return }
            self.registry.createWorkspace(named: name, from: window)
        }
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
        guard controllers.contains(where: { $0.surfaceTree.contains { $0.needsConfirmQuit } }) else {
            closeAll()
            return
        }
        anchor.confirmClose(
            messageText: "\(title)?",
            informativeText: "At least one of these tabs still has a running process. If you close the tab the process will be killed.",
            completion: closeAll
        )
    }

    /// The tabs of `tab`'s workspace (Q8: the close commands stay inside it).
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
        menu.addItem(moveTo)
        menu.addItem(.separator())
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

    /// A drag is over a row or header. True when the drop would do something.
    func dragOver(_ kind: SidebarDragKind, over target: SidebarDropTarget, lowerHalf: Bool) -> Bool {
        let slot = Self.dropSlot(dragging: kind, over: target, lowerHalf: lowerHalf, in: groups)
        if dropSlot != slot { dropSlot = slot }
        return slot != nil
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
    /// window of its own (S21).
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
        let item = NSMenuItem(title: title, action: #selector(MenuAction.perform(_:)), keyEquivalent: "")
        item.target = action
        // The item's target is weak, so the item itself keeps the action alive.
        item.representedObject = action
        item.isEnabled = isEnabled
        return item
    }

    /// Runs a closure as a menu item's action.
    private final class MenuAction: NSObject {
        private let handler: () -> Void

        init(_ handler: @escaping () -> Void) {
            self.handler = handler
        }

        @objc func perform(_ sender: Any?) {
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

    init(model: SidebarModel, ghostty: Ghostty.App, @ViewBuilder content: () -> Content) {
        self.model = model
        self.ghostty = ghostty
        self.content = content()
    }

    var body: some View {
        if tabStyle == .top {
            content
        } else {
            sidebarAndContent
        }
    }

    private var sidebarAndContent: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, isCollapsed: $isCollapsed)
                .frame(width: isCollapsed ? Sidebar.collapsedWidth : dragWidth ?? width)
                .background(ghostty.config.backgroundColor.opacity(ghostty.config.backgroundOpacity))
                .environment(\.colorScheme, NSColor(ghostty.config.backgroundColor).isLightColor ? .light : .dark)
                .overlay(alignment: .trailing) {
                    if !isCollapsed { resizeHandle }
                }

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: Sidebar.dividerWidth)

            content
        }
    }

    /// An invisible strip along the sidebar's right edge that resizes it. It lies inside
    /// the sidebar: the terminal view next to it would take the clicks and set its own cursor.
    private var resizeHandle: some View {
        Color.clear
            .frame(width: 10)
            .contentShape(Rectangle())
            .gesture(resizeGesture)
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = widthAtDragStart ?? width
                widthAtDragStart = start
                let range = Sidebar.widthRange
                dragWidth = min(max((start + value.translation.width).rounded(), range.lowerBound), range.upperBound)
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
    static let collapsedWidth: Double = 40
    static let dividerWidth: Double = 1

    /// The width the sidebar and its divider currently take out of a window's content.
    static var occupiedWidth: CGFloat {
        let defaults = UserDefaults.standard
        if TabStyle.current == .top {
            return 0
        }
        if defaults.bool(forKey: collapsedKey) {
            return collapsedWidth + dividerWidth
        }

        let width = defaults.object(forKey: widthKey) as? Double ?? defaultWidth
        return width + dividerWidth
    }

    @ObservedObject var model: SidebarModel
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isCollapsed {
                VStack(spacing: 4) {
                    collapseButton
                    newTabButton
                }
                .padding(.vertical, 6)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
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
                    Spacer()
                    newWorkspaceButton
                    newTabButton
                }
                .padding(.horizontal, 6)
                .frame(height: 36)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.groups) { group in
                            WorkspaceHeader(model: model, group: group)
                            ForEach(visibleTabs(of: group)) { tab in
                                SidebarRow(model: model, tab: tab, isCompact: false)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A folded workspace shows no tabs (D6); selecting one of them unfolds it (Q9).
    private func visibleTabs(of group: SidebarModel.Group) -> [SidebarModel.Tab] {
        group.workspace.collapsed ? [] : group.tabs
    }

    private var collapseButton: some View {
        SidebarButton(systemName: "sidebar.left", label: isCollapsed ? "Show Sidebar" : "Hide Sidebar") {
            isCollapsed.toggle()
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

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .medium))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(isHovering ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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

    var body: some View {
        content
            .font(.system(size: 13))
            .foregroundStyle(Color.primary.opacity(tab.isSelected ? 1 : 0.7))
            .background(RoundedRectangle(cornerRadius: 5).fill(fill))
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
            .overlay(interaction)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(tab.isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.select(tab) }
    }

    /// The drop line goes under the last tab of a workspace dropped at its end.
    private var endsHere: Bool {
        guard case .endOfWorkspace(let id) = model.dropSlot,
              let group = model.groups.first(where: { $0.id == id })
        else { return false }
        return group.tabs.last?.key == tab.key
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
            dragOver: { kind, lowerHalf in
                model.dragOver(kind, over: .tab(tab.key), lowerHalf: lowerHalf)
            },
            dragExit: { model.dragExit() },
            drop: { kind, value, lowerHalf in
                model.drop(kind, value: value, over: .tab(tab.key), lowerHalf: lowerHalf)
            },
            dragEnded: { point, accepted in model.dragEnded(tab, at: point, accepted: accepted) },
            // The close button of an expanded row sits in its first 22 points.
            excludedLeading: isCompact ? 0 : 22
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
        if tab.isSelected { return Color.primary.opacity(0.14) }
        return Color.primary.opacity(isHovering ? 0.07 : 0)
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

    private var row: some View {
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

            Text(tab.title)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if let agent = tab.agent {
                AgentBadge(agent: agent)
            }

            if let keyEquivalent = tab.keyEquivalent {
                Text(keyEquivalent)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 26)
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
        if tabStyle == .top, let tab = model.groups.lazy.flatMap(\.tabs).first(where: { $0.id == id }),
           tab.agentProcess != nil {
            HStack(spacing: 6) {
                if let agent = tab.agent {
                    AgentBadge(agent: agent)
                }
                TabIcon(agentProcess: tab.agentProcess, size: 12)
            }
            .padding(.horizontal, 4)
        }
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
