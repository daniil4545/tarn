import AppKit
import SwiftUI

/// Where a terminal window lists its tabs.
enum TabStyle: String {
    /// The tarn sidebar on the left; the native tab bar is hidden.
    case sidebar
    /// The native tab bar at the top, as in Ghostty; no sidebar.
    case top

    static let key = "TarnTabStyle"

    static var current: TabStyle { current(in: .standard) }

    static func current(in defaults: UserDefaults) -> TabStyle {
        defaults.string(forKey: key).flatMap(TabStyle.init(rawValue:)) ?? .sidebar
    }

    /// Shows or hides the native tab bar of every open terminal window to match the style.
    /// The sidebar follows the style by itself through `SidebarLayout`.
    @MainActor static func applyToOpenWindows() {
        let hidden = current == .sidebar
        for window in NSApp.windows {
            guard let window = window as? TerminalWindow else { continue }
            WorkspaceTitle.apply(to: window)
            for controller in window.titlebarAccessoryViewControllers
            where controller.identifier == TerminalWindow.tabBarIdentifier {
                controller.isHidden = hidden
                controller.view.isHidden = hidden
            }
        }
    }
}

/// How tall a tab row of the sidebar is.
enum TabRows: String, CaseIterable, Identifiable {
    /// Two lines: the title (the task, as the agent sets it), then the folder and the time in state.
    case wide
    /// One line: icon, title, state badge and key.
    case narrow

    static let key = "TarnTabRows"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wide: "Wide"
        case .narrow: "Narrow"
        }
    }

    var detail: String {
        switch self {
        case .wide: "Two lines: the task on top, then the folder and the time in its state."
        case .narrow: "One line per tab: icon, title, state dot and key."
        }
    }

    /// The second line of a wide row for an agent tab: the folder and the time in its state, in
    /// minutes ("now" under one).
    static func secondLine(folder: String, since: Date, now: Date) -> String {
        let time = now.timeIntervalSince(since) < 60 ? "now" : TabCard.elapsed(from: since, to: now)
        return folder.isEmpty ? time : "\(folder) · \(time)"
    }
}

/// The File viewer switch. Off: panes are not drawn (their tabs and edits stay), Cmd+B does
/// nothing, path clicks go to Ghostty's opener, agents get an error.
enum FileViewerSetting {
    static let key = "TarnFileViewer"

    static var isOn: Bool { TarnModules.isOn(.viewer) }
}

/// The tarn settings window: tarn's own features, a short list of Ghostty options (written to
/// tarn's options file) and Help. Everything else stays in the Ghostty config file.
final class TarnSettingsController: NSWindowController, NSWindowDelegate {
    static let shared = TarnSettingsController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: TarnSettingsView())
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Escape closes the window, as in the About window.
    @objc func cancel(_ sender: Any?) {
        window?.performClose(sender)
    }

    /// Close and Close Window send `close:` and `closeWindow:` down the responder chain;
    /// `NSWindow` answers neither, so without these Cmd+W does nothing.
    @IBAction func close(_ sender: Any?) {
        window?.performClose(sender)
    }

    @IBAction func closeWindow(_ sender: Any?) {
        window?.performClose(sender)
    }
}

extension AppDelegate {
    @IBAction func showTarnSettings(_ sender: Any?) {
        TarnSettingsController.shared.show()
    }
}

struct TarnSettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case modules, appearance, terminal, windows, help

        var id: String { rawValue }

        var title: String {
            switch self {
            case .modules: "Modules"
            case .appearance: "Appearance"
            case .terminal: "Terminal"
            case .windows: "Windows"
            case .help: "Help"
            }
        }

        var icon: String {
            switch self {
            case .modules: "switch.2"
            case .appearance: "paintpalette"
            case .terminal: "terminal"
            case .windows: "macwindow"
            case .help: "keyboard"
            }
        }
    }

    @State private var section: Section? = .modules
    @StateObject private var store = GhosttyOptionStore.shared

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(170)
            .safeAreaInset(edge: .bottom) { ghosttyConfigButton }
        } detail: {
            switch section ?? .modules {
            case .modules: ModulesSettingsPane()
            case .appearance: GhosttyOptionsPane(section: .appearance, title: "Appearance", store: store)
            case .terminal: GhosttyOptionsPane(section: .terminal, title: "Terminal", store: store)
            case .windows: GhosttyOptionsPane(section: .windows, title: "Windows", store: store)
            case .help: HelpPane()
            }
        }
        .frame(minWidth: 640, minHeight: 400)
    }

    private var ghosttyConfigButton: some View {
        Button {
            (NSApp.delegate as? AppDelegate)?.ghostty.openConfig()
        } label: {
            Label("Ghostty Config…", systemImage: "doc.text")
        }
        .buttonStyle(.borderless)
        .help("Terminal settings: fonts, colors, keys. Opens the Ghostty config file.")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

