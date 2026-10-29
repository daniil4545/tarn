import AppKit
import OSLog

/// A tarn feature with one switch in Settings > Modules (`docs/modules/settings.md`).
enum TarnModule: String, CaseIterable, Identifiable {
    case sidebar, viewer, permissionCard, notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sidebar: "Sidebar"
        case .viewer: "File viewer"
        case .permissionCard: "Permission card"
        case .notifications: "Notifications"
        }
    }

    var detail: String {
        switch self {
        case .sidebar: "Tabs in workspaces with agent state, on the left. Off: the native tab bar at the top."
        case .viewer: "Cmd+B, path clicks and agents open files in a pane beside the terminal. "
            + "When off, path clicks open files in their default app; open panes are hidden and come back when you switch it on."
        case .permissionCard: "Allow or deny from the sidebar card."
        case .notifications: "A banner when an agent needs you; Cmd+U jumps to it."
        }
    }

    /// The UserDefaults key. Sidebar and File viewer keep their original keys.
    var key: String {
        switch self {
        case .sidebar: TabStyle.key
        case .viewer: FileViewerSetting.key
        case .permissionCard, .notifications: "TarnModule.\(rawValue)"
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
    private static let reportedLock = NSLock()
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
        // Words and 0/1 count only from the launch arguments; stored elsewhere they are a wrong type.
        let fromArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)[key] != nil
        if let parsed = parse(value, strict: !fromArguments) { return parsed }
        reportedLock.lock()
        let first = reported.insert(key).inserted
        reportedLock.unlock()
        if first {
            logger.error("\(key, privacy: .public) has a value of the wrong type; counted as on")
        }
        return true
    }

    static func parse(_ value: Any, strict: Bool = false) -> Bool? {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        if strict { return nil }
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

/// What each owner does when its module flips. Tests replace the closures with spies.
struct ModuleOwners {
    var tabStyle: @MainActor () -> Void = { TabStyle.applyToOpenWindows() }
    var releasePermissions: @MainActor () -> Void = { SessionRegistry.shared.permissionCardChanged() }
    var viewerChanged: @MainActor () -> Void = {
        for controller in TerminalController.all { controller.viewerHost.moduleChanged() }
    }
    var menus: @MainActor () -> Void = { TarnModules.applyMenus() }
}

/// Watches UserDefaults for any writer (the pane, `defaults write`) and acts on the difference
/// between the effective set and the last one.
@MainActor
final class TarnModuleWatcher {
    static let shared = TarnModuleWatcher()

    private let defaults: UserDefaults
    private let owners: ModuleOwners
    private var last: Set<TarnModule>
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, owners: ModuleOwners = ModuleOwners()) {
        self.defaults = defaults
        self.owners = owners
        last = TarnModules.effective(in: defaults)
    }

    /// Starts watching; the first sidebar of the app calls it. Safe to call again.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        owners.menus()
    }

    func check() {
        let now = TarnModules.effective(in: defaults)
        let changed = now.symmetricDifference(last)
        guard !changed.isEmpty else { return }
        last = now
        apply(changed)
    }

    func apply(_ changed: Set<TarnModule>) {
        if changed.contains(.sidebar) { owners.tabStyle() }
        if changed.contains(.permissionCard) { owners.releasePermissions() }
        if changed.contains(.viewer) { owners.viewerChanged() }
        owners.menus()
        NotificationCenter.default.post(name: .terminalTabsDidChange, object: nil)
    }
}
