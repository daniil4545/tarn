import AppKit
import OSLog

/// A tarn feature with one switch in Settings > Modules (`docs/modules/settings.md`).
enum TarnModule: String, CaseIterable, Identifiable {
    case sidebar, viewer, workspaces, permissionCard, notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sidebar: "Sidebar"
        case .viewer: "File viewer"
        case .workspaces: "Workspaces"
        case .permissionCard: "Permission card"
        case .notifications: "Notifications"
        }
    }

    var detail: String {
        switch self {
        case .sidebar: "Tabs in workspaces with agent state, on the left. Off: the native tab bar at the top."
        case .viewer: "Files, markdown and code next to the terminal."
        case .workspaces: "Tab groups per project. Without the sidebar the top tabs carry the workspace name."
        case .permissionCard: "Allow or deny from the sidebar card."
        case .notifications: "A banner when an agent needs you; Cmd+U jumps to it."
        }
    }

    /// The UserDefaults key. Sidebar and File viewer keep the keys of 1.2.0.
    var key: String {
        switch self {
        case .sidebar: TabStyle.key
        case .viewer: FileViewerSetting.key
        case .workspaces, .permissionCard, .notifications: "TarnModule.\(rawValue)"
        }
    }

    /// The module that must be on for this one to work.
    var needs: TarnModule? {
        self == .permissionCard ? .sidebar : nil
    }
}

/// The state of the modules. A switch is read at the moment a path draws UI or creates an
/// object, so a switch applies at once and a path added later follows the same rule
/// (`docs/modules/settings.md`).
enum TarnModules {
    private static let logger = Logger(subsystem: "tarn", category: "settings")

    /// Keys whose bad value was already logged, so a hot path logs it once.
    nonisolated(unsafe) private static var reported = Set<String>()

    /// A switch as the user left it, whatever the needed module says. A missing key is on; a value
    /// of the wrong type counts as on too and is logged once.
    static func stored(_ module: TarnModule, in defaults: UserDefaults = .standard) -> Bool {
        if module == .sidebar { return TabStyle.current(in: defaults) == .sidebar }
        return flag(module.key, in: defaults)
    }

    /// The state the UI follows: stored on and every needed module effectively on.
    static func isOn(_ module: TarnModule, in defaults: UserDefaults = .standard) -> Bool {
        guard stored(module, in: defaults) else { return false }
        return module.needs.map { isOn($0, in: defaults) } ?? true
    }

    static func effective(in defaults: UserDefaults = .standard) -> Set<TarnModule> {
        Set(TarnModule.allCases.filter { isOn($0, in: defaults) })
    }

    /// A Bool key. `-Key NO` on the command line lands in the argument domain as a string, so
    /// the words YES and NO count as well.
    static func flag(_ key: String, in defaults: UserDefaults = .standard) -> Bool {
        guard let value = defaults.object(forKey: key) else { return true }
        if let parsed = parse(value) { return parsed }
        if reported.insert(key).inserted {
            logger.error("\(key, privacy: .public) has a value of the wrong type; counted as on")
        }
        return true
    }

    static func parse(_ value: Any) -> Bool? {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        if let number = value as? NSNumber, number == 0 || number == 1 { return number.boolValue }
        guard let text = value as? String else { return nil }
        switch text.lowercased() {
        case "yes", "true", "1": return true
        case "no", "false", "0": return false
        default: return nil
        }
    }

    // MARK: Menu items

    /// The menu actions that belong to a module; the item is hidden while the module is off.
    static let menuActions: [String: TarnModule] = [
        "newWorkspace:": .workspaces,
        "toggleViewer:": .viewer,
        "jumpToWaitingSession:": .notifications,
    ]

    /// Shows or hides the items of `menuActions` by walking the main menu, so no Ghostty file
    /// needs a hook of its own.
    @MainActor
    static func applyMenus(_ menu: NSMenu? = NSApp?.mainMenu, on: (TarnModule) -> Bool = { isOn($0) }) {
        guard let menu else { return }
        for item in menu.items {
            if let action = item.action, let module = menuActions[NSStringFromSelector(action)] {
                item.isHidden = !on(module)
            }
            if let submenu = item.submenu { applyMenus(submenu, on: on) }
        }
    }
}

extension Notification.Name {
    /// Posted when the effective set of modules changed; `userInfo["changed"]` is the set.
    static let tarnModulesDidChange = Notification.Name("com.daniil4545.tarn.modulesDidChange")
}

/// Watches UserDefaults for any writer (the pane, `defaults write`) and acts on the difference
/// between the effective set and the last one.
@MainActor
final class TarnModuleWatcher {
    static let shared = TarnModuleWatcher()

    private var last = TarnModules.effective()
    private var observer: NSObjectProtocol?

    /// Starts watching; the first sidebar of the app calls it. Safe to call again.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        TarnModules.applyMenus()
    }

    func check() {
        let now = TarnModules.effective()
        let changed = now.symmetricDifference(last)
        guard !changed.isEmpty else { return }
        last = now
        apply(changed, now: now)
    }

    /// What each owner does when its module flips.
    func apply(_ changed: Set<TarnModule>, now: Set<TarnModule>) {
        if changed.contains(.sidebar) { TabStyle.applyToOpenWindows() }
        if changed.contains(.workspaces) { WorkspaceRegistry.shared.setFrozen(!now.contains(.workspaces)) }
        if changed.contains(.permissionCard) { SessionRegistry.shared.permissionCardChanged() }
        if changed.contains(.viewer) {
            for controller in TerminalController.all { controller.viewerHost.moduleChanged() }
        }
        TarnModules.applyMenus()
        NotificationCenter.default.post(name: .tarnModulesDidChange, object: nil, userInfo: ["changed": changed])
        NotificationCenter.default.post(name: .terminalTabsDidChange, object: nil)
    }
}
