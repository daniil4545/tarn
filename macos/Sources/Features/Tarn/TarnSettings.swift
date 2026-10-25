import AppKit
import SwiftUI

/// Where a terminal window lists its tabs.
enum TabStyle: String, CaseIterable, Identifiable {
    /// The tarn sidebar on the left; the native tab bar is hidden.
    case sidebar
    /// The native tab bar at the top, as in Ghostty; no sidebar.
    case top

    static let key = "TarnTabStyle"

    static var current: TabStyle {
        UserDefaults.standard.string(forKey: key).flatMap(TabStyle.init(rawValue:)) ?? .sidebar
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sidebar: "Sidebar"
        case .top: "Tabs at the top"
        }
    }

    var detail: String {
        switch self {
        case .sidebar: "Tabs grouped by project with agent state, on the left of the window."
        case .top: "The native tab bar, as in Ghostty. Agent state is not shown."
        }
    }

    /// Shows or hides the native tab bar of every open terminal window to match the style.
    /// The sidebar follows the style by itself through `SidebarLayout`.
    @MainActor static func applyToOpenWindows() {
        let hidden = current == .sidebar
        for window in NSApp.windows {
            guard let window = window as? TerminalWindow else { continue }
            for controller in window.titlebarAccessoryViewControllers
            where controller.identifier == TerminalWindow.tabBarIdentifier {
                controller.isHidden = hidden
                controller.view.isHidden = hidden
            }
        }
    }
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
}

extension AppDelegate {
    @IBAction func showTarnSettings(_ sender: Any?) {
        TarnSettingsController.shared.show()
    }
}

struct TarnSettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case tabs, appearance, terminal, windows, help

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tabs: "Tabs"
            case .appearance: "Appearance"
            case .terminal: "Terminal"
            case .windows: "Windows"
            case .help: "Help"
            }
        }

        var icon: String {
            switch self {
            case .tabs: "sidebar.left"
            case .appearance: "paintpalette"
            case .terminal: "terminal"
            case .windows: "macwindow"
            case .help: "keyboard"
            }
        }
    }

    @State private var section: Section? = .tabs
    @StateObject private var store = GhosttyOptionStore.shared

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(170)
            .safeAreaInset(edge: .bottom) { ghosttyConfigButton }
        } detail: {
            switch section ?? .tabs {
            case .tabs: TabsSettingsPane()
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

private struct TabsSettingsPane: View {
    @AppStorage(TabStyle.key) private var style: TabStyle = .sidebar

    var body: some View {
        Form {
            Picker("Tab style", selection: $style) {
                ForEach(TabStyle.allCases) { style in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.title)
                        Text(style.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(style)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .formStyle(.grouped)
        .navigationTitle("Tabs")
        .onChange(of: style) { _ in
            TabStyle.applyToOpenWindows()
        }
    }
}
