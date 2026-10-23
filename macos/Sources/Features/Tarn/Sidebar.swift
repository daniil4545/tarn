// Based on the vertical tab sidebar from ghostty-org/ghostty PR #14562
// by Somnathumapathi and Priyans-hu, MIT License. See THIRD_PARTY.md.

import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when the tabs of any terminal window may have changed: their order, titles,
    /// colors, key equivalents, or which one is selected.
    static let terminalTabsDidChange = Notification.Name("com.daniil4545.tarn.terminalTabsDidChange")
}

/// The tabs of one terminal window's tab group, grouped by project.
///
/// Every tab is its own window, so each window owns a model and shows its own copy of the
/// sidebar. Only the selected tab's window is on screen, so that is the copy the user sees.
@MainActor
final class SidebarModel: ObservableObject {
    struct Tab: Identifiable, Equatable {
        let id: ObjectIdentifier

        /// The 1-based position of the tab in its window.
        let index: Int
        let title: String
        let keyEquivalent: String?
        let color: TerminalTabColor
        let isSelected: Bool
        /// The agent session of the tab that needs the user most, if any surface runs one.
        let agent: AgentSession?
        let project: String
        /// The working directory of the focused surface, with the home folder as "~".
        let folder: String?
    }

    struct Group: Identifiable, Equatable {
        /// The project name: the git root folder of the tab's focused surface, or its folder.
        let id: String
        let tabs: [Tab]
    }

    @Published private(set) var groups: [Group] = []

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

    /// Project names by working directory, so a refresh does not walk the file system again.
    private var projects: [String: String] = [:]

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
    }

    deinit {
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
        // The window only carries a key equivalent label while it is in a tab group, so a
        // lone tab would have none. Look the shortcuts up from the keybinds instead.
        let config = (window?.windowController as? BaseTerminalController)?.ghostty.config
        var order: [String] = []
        var byProject: [String: [Tab]] = [:]

        for (offset, tabWindow) in tabWindows.enumerated() {
            let index = offset + 1
            let shortcut = index <= 9 ? config?.keyboardShortcut(for: "goto_tab:\(index)") : nil
            let controller = tabWindow.windowController as? BaseTerminalController
            let pwd = controller?.focusedSurface?.pwd
            let name = project(for: pwd)
            let tab = Tab(
                id: ObjectIdentifier(tabWindow),
                index: index,
                title: Self.displayTitle(tabWindow.title, pwd: pwd),
                keyEquivalent: shortcut.map { "\($0)" },
                color: (tabWindow as? TerminalWindow)?.tabColor ?? .none,
                // Our window is only on screen while it is the selected tab.
                isSelected: tabWindow === window,
                agent: Self.agent(in: controller),
                project: name,
                folder: pwd.map { Self.displayTitle("/", pwd: $0) }
            )

            if byProject[name] == nil { order.append(name) }
            byProject[name, default: []].append(tab)
        }

        let newGroups = order.map { Group(id: $0, tabs: byProject[$0] ?? []) }
        guard newGroups != groups else { return }
        groups = newGroups
        if cardTab != nil { updateCard() }
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
        return controller.surfaceTree
            .compactMap { sessions[$0.id] }
            .filter { $0.state != .idle }
            .max { a, b in
                (a.state, a.isUnseenDone ? 1 : 0) < (b.state, b.isUnseenDone ? 1 : 0)
            }
    }

    /// The tab title to show. A shell titles its window with a path, often cut with "…";
    /// such a title is replaced by the full working directory with the home folder as "~".
    /// Any other title, such as one set by a running program, is kept.
    static func displayTitle(_ title: String, pwd: String?) -> String {
        guard let pwd, !pwd.isEmpty, let first = title.first, "/~…".contains(first) else { return title }
        let home = NSHomeDirectory()
        if pwd == home { return "~" }
        if pwd.hasPrefix(home + "/") { return "~" + pwd.dropFirst(home.count) }
        return pwd
    }

    /// The name of the git root above `pwd`, or the last folder of `pwd` outside git.
    private func project(for pwd: String?) -> String {
        guard let pwd, !pwd.isEmpty else { return "" }
        if let cached = projects[pwd] { return cached }

        let fm = FileManager.default
        var url = URL(fileURLWithPath: pwd)
        var name = url.lastPathComponent
        while url.path != "/" {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
                name = url.lastPathComponent
                break
            }
            url.deleteLastPathComponent()
        }

        projects[pwd] = name
        return name
    }

    func newTab() {
        (window?.windowController as? TerminalController)?.newTab(nil)
    }

    func select(_ tab: Tab) {
        tabWindow(for: tab)?.makeKeyAndOrderFront(nil)
    }

    func close(_ tab: Tab) {
        controller(for: tab)?.closeTab(nil)
    }

    /// The right-click menu for a tab, with the items of a native tab's menu.
    func contextMenu(for tab: Tab) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let count = tabWindows.count
        menu.addItem(menuItem("Close Tab") { [weak self] in
            self?.close(tab)
        })
        menu.addItem(menuItem("Close Other Tabs", isEnabled: count > 1) { [weak self] in
            self?.select(tab)
            self?.controller(for: tab)?.closeOtherTabs(nil)
        })
        menu.addItem(menuItem("Close Tabs Below", isEnabled: tab.index < count) { [weak self] in
            self?.select(tab)
            self?.controller(for: tab)?.closeTabsOnTheRight(nil)
        })
        menu.addItem(menuItem("Move Tab to New Window", isEnabled: count > 1) { [weak self] in
            self?.tabWindow(for: tab)?.moveTabToNewWindow(nil)
        })
        menu.addItem(.separator())
        menu.addItem(menuItem("Rename Tab...") { [weak self] in
            self?.select(tab)
            self?.controller(for: tab)?.promptTabTitle()
        })

        return menu
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

    /// The sidebar width when the current resize drag began.
    @State private var widthAtDragStart: Double?

    init(model: SidebarModel, ghostty: Ghostty.App, @ViewBuilder content: () -> Content) {
        self.model = model
        self.ghostty = ghostty
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, isCollapsed: $isCollapsed)
                .frame(width: isCollapsed ? Sidebar.collapsedWidth : width)
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
                width = min(max(start + value.translation.width, range.lowerBound), range.upperBound)
            }
            .onEnded { _ in
                widthAtDragStart = nil
            }
    }
}

/// The vertical list of a terminal window's tabs, replacing the native tab bar.
struct Sidebar: View {
    static let collapsedKey = "TarnSidebarCollapsed"
    static let widthKey = "TarnSidebarWidth"
    static let foldedKey = "TarnSidebarFoldedProjects"
    static let defaultWidth: Double = 200
    static let widthRange: ClosedRange<Double> = 120...400
    static let collapsedWidth: Double = 40
    static let dividerWidth: Double = 1

    /// The width the sidebar and its divider currently take out of a window's content.
    static var occupiedWidth: CGFloat {
        let defaults = UserDefaults.standard
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
                    newTabButton
                }
                .padding(.horizontal, 6)
                .frame(height: 36)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.groups) { group in
                            let isFolded = folded.contains(group.id)
                            if !group.id.isEmpty {
                                header(group, isFolded: isFolded)
                            }
                            // A folded project still shows its selected tab, so the
                            // current tab never disappears from the list.
                            ForEach(group.tabs.filter { !isFolded || $0.isSelected }) { tab in
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
        .background {
            // ⌘⇧U jumps to the session that needs the user most.
            Button("") { SessionRegistry.shared.focusNextWaiting() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .hidden()
        }
    }

    /// A project header. A click folds or unfolds the project's tabs.
    private func header(_ group: SidebarModel.Group, isFolded: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isFolded ? "chevron.right" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 10)
            Text(group.id)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isFolded {
                Text("\(group.tabs.count)")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onTapGesture { toggleFold(group.id) }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isFolded ? "Expand \(group.id)" : "Collapse \(group.id)")
    }

    /// Folded project names, one per line. Stored app-wide, so every window agrees.
    @AppStorage(Sidebar.foldedKey) private var foldedList = ""

    private var folded: Set<String> {
        Set(foldedList.split(separator: "\n").map(String.init))
    }

    private func toggleFold(_ project: String) {
        var names = folded
        if names.contains(project) {
            names.remove(project)
        } else {
            names.insert(project)
        }
        foldedList = names.sorted().joined(separator: "\n")
    }

    private var collapseButton: some View {
        SidebarButton(systemName: "sidebar.left", label: isCollapsed ? "Show Sidebar" : "Hide Sidebar") {
            isCollapsed.toggle()
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
            .onTapGesture {
                if model.forceClicked {
                    model.forceClicked = false
                } else {
                    model.select(tab)
                }
            }
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
            .overlay(SidebarMenuArea { model.contextMenu(for: tab) })
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(tab.isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.select(tab) }
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
            Text(tab.keyEquivalent ?? "\(tab.index)")
                .font(.system(size: 11))
                .frame(width: 30, height: 28)
                .overlay(alignment: .topTrailing) {
                    if let agent = tab.agent { AgentBadge(agent: agent).scaleEffect(0.8) }
                }
        } else {
            row
        }
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

/// Shows an AppKit menu when its area is right-clicked or control-clicked, and lets every
/// other mouse event through to the SwiftUI views beneath it.
private struct SidebarMenuArea: NSViewRepresentable {
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> MenuAreaView {
        let view = MenuAreaView()
        view.menuProvider = menu
        return view
    }

    func updateNSView(_ nsView: MenuAreaView, context: Context) {
        nsView.menuProvider = menu
    }

    final class MenuAreaView: NSView {
        var menuProvider: (() -> NSMenu)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only claim the clicks that open a context menu. Everything else, such as
            // selecting the tab or pressing its close button, belongs to the row beneath.
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp:
                return super.hitTest(point)
            case .leftMouseDown where event.modifierFlags.contains(.control):
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            menuProvider?()
        }
    }
}
