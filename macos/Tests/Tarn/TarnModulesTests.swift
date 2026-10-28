import AppKit
import Foundation
import Testing
@testable import Ghostty

/// Effective state, needs, odd stored values and the menu items of the modules.
@MainActor
@Suite
struct TarnModulesTests {
    private let defaults: UserDefaults

    init() {
        let name = "tarn.modules.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    @Test func everyModuleIsOnByDefault() {
        #expect(TarnModules.effective(in: defaults) == Set(TarnModule.allCases))
    }

    @Test func sidebarFollowsTheTabStyleKeyOfEarlierVersions() {
        defaults.set("top", forKey: "TarnTabStyle")
        #expect(!TarnModules.isOn(.sidebar, in: defaults))
        defaults.set("sidebar", forKey: "TarnTabStyle")
        #expect(TarnModules.isOn(.sidebar, in: defaults))
        #expect(TarnModule.sidebar.key == "TarnTabStyle")
        #expect(TarnModule.viewer.key == "TarnFileViewer")
    }

    @Test func theFileViewerKeepsItsKey() {
        defaults.set(false, forKey: "TarnFileViewer")
        #expect(!TarnModules.isOn(.viewer, in: defaults))
    }

    @Test func permissionCardNeedsTheSidebarAndKeepsItsStoredValue() {
        defaults.set("top", forKey: "TarnTabStyle")
        #expect(TarnModules.stored(.permissionCard, in: defaults))
        #expect(!TarnModules.isOn(.permissionCard, in: defaults))
        defaults.set("sidebar", forKey: "TarnTabStyle")
        #expect(TarnModules.isOn(.permissionCard, in: defaults))
        #expect(TarnModule.allCases.filter { $0.needs != nil } == [.permissionCard])
    }

    @Test func workspacesAndNotificationsWorkWithoutTheSidebar() {
        defaults.set("top", forKey: "TarnTabStyle")
        #expect(TarnModules.isOn(.workspaces, in: defaults))
        #expect(TarnModules.isOn(.notifications, in: defaults))
    }

    @Test func aValueOfTheWrongTypeCountsAsOn() {
        defaults.set(["x"], forKey: TarnModule.workspaces.key)
        defaults.set("maybe", forKey: TarnModule.notifications.key)
        defaults.set(7, forKey: TarnModule.permissionCard.key)
        #expect(TarnModules.isOn(.workspaces, in: defaults))
        #expect(TarnModules.isOn(.notifications, in: defaults))
        #expect(TarnModules.isOn(.permissionCard, in: defaults))
    }

    // `-TarnModule.workspaces NO` on the command line is a string in the argument domain; the
    // domain is process-wide, so the test reads the parser the flag uses for it.
    @Test(arguments: [("NO", false), ("YES", true), ("false", false), ("1", true), ("0", false)])
    func launchArgumentWordsAreRead(word: String, expected: Bool) {
        #expect(TarnModules.parse(word, strict: false) == expected)
        #expect(TarnModules.parse(word, strict: true) == nil)
    }

    // Stored elsewhere, a word or an integer is a wrong type and counts as on.
    @Test(arguments: ["NO", "false", "0"] as [Any])
    func wordsAndIntegersOutsideTheLaunchArgumentsCountAsOn(value: Any) {
        defaults.set(value, forKey: TarnModule.workspaces.key)
        #expect(TarnModules.isOn(.workspaces, in: defaults))
    }

    @Test func aSwitchedBoolIsRead() {
        defaults.set(false, forKey: TarnModule.notifications.key)
        #expect(!TarnModules.isOn(.notifications, in: defaults))
        #expect(TarnModules.effective(in: defaults) == Set(TarnModule.allCases).subtracting([.notifications]))
    }

    // MARK: Menu items

    @Test func menuItemsOfAnOffModuleAreHidden() {
        let menu = NSMenu()
        let names = ["newWorkspace:", "toggleViewer:", "jumpToWaitingSession:", "copy:"]
        for name in names {
            menu.addItem(NSMenuItem(title: name, action: NSSelectorFromString(name), keyEquivalent: ""))
        }
        let sub = NSMenuItem(title: "Sub", action: nil, keyEquivalent: "")
        sub.submenu = NSMenu()
        sub.submenu?.addItem(NSMenuItem(title: "v", action: NSSelectorFromString("toggleViewer:"), keyEquivalent: ""))
        menu.addItem(sub)

        TarnModules.applyMenus(menu) { $0 == .workspaces }
        #expect(menu.items.map(\.isHidden) == [false, true, true, false, false])
        #expect(sub.submenu?.items.first?.isHidden == true)

        TarnModules.applyMenus(menu) { _ in true }
        #expect(menu.items.allSatisfy { !$0.isHidden })
    }

    // MARK: Agent checks

    @Test func theVersionIsTheLineOfClaudeCode() {
        #expect(AgentChecks.version(from: "2.1.311 (Claude Code)\n") == "2.1.311")
        #expect(AgentChecks.version(from: "Last login: today\n2.1.311 (Claude Code)\n") == "2.1.311")
        #expect(AgentChecks.version(from: "claude: command not found\n") == nil)
        #expect(AgentChecks.version(from: "") == nil)
    }

    @Test func thePluginIsFoundUnderPlugins() {
        let ok = Data(#"{"version":2,"plugins":{"tarn@tarn":[{"scope":"user"}]}}"#.utf8)
        let other = Data(#"{"plugins":{"x@y":[]}}"#.utf8)
        #expect(AgentChecks.hasPlugin(in: ok))
        #expect(!AgentChecks.hasPlugin(in: other))
        #expect(!AgentChecks.hasPlugin(in: Data("junk".utf8)))
    }

    // A child that outlives the limit is gone when the call returns, also one that ignores SIGTERM.
    @Test(arguments: [["30"], ["-c", "trap '' TERM; sleep 30"]])
    func aChildOverTheLimitIsKilled(arguments: [String]) async throws {
        let path = arguments.count == 1 ? "/bin/sleep" : "/bin/sh"
        var pid: pid_t = 0
        let started = Date()
        let output = AgentChecks.capture(path, arguments, timeout: 0.2) { pid = $0 }
        #expect(output == nil)
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(pid > 0)
        var gone = false
        for _ in 0..<50 where !gone {
            gone = kill(pid, 0) == -1 && errno == ESRCH
            if !gone { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(gone)
    }

    @Test func theBinaryIsLookedForInTheKnownPlacesFirst() {
        let paths = AgentChecks.candidates(home: "/h")
        #expect(paths == ["/h/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "/h/.claude/local/claude"])
    }
}

/// Each switch flips through the watcher and reaches its owner or its guarded entry point.
@MainActor
@Suite
struct ModuleWatcherTests {
    private final class Spy {
        var tabStyle = 0
        var frozen: [Bool] = []
        var released = 0
        var viewer = 0
        var menus = 0
    }

    private let defaults: UserDefaults
    private let spy = Spy()
    private let watcher: TarnModuleWatcher

    init() {
        let name = "tarn.watcher.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        self.defaults = defaults
        let spy = spy
        watcher = TarnModuleWatcher(defaults: defaults, owners: ModuleOwners(
            tabStyle: { spy.tabStyle += 1 },
            freezeWorkspaces: { spy.frozen.append($0) },
            releasePermissions: { spy.released += 1 },
            viewerChanged: { spy.viewer += 1 },
            menus: { spy.menus += 1 }
        ))
    }

    @Test func nothingHappensWithoutAChange() {
        watcher.check()
        #expect(spy.tabStyle + spy.frozen.count + spy.released + spy.viewer + spy.menus == 0)
    }

    @Test func workspacesFreezeAndThawThroughTheWatcher() {
        defaults.set(false, forKey: TarnModule.workspaces.key)
        watcher.check()
        #expect(spy.frozen == [true])
        defaults.set(true, forKey: TarnModule.workspaces.key)
        watcher.check()
        #expect(spy.frozen == [true, false])
        watcher.check()
        #expect(spy.frozen.count == 2)
    }

    @Test func switchingThePermissionCardOffReleasesWaitingHooks() {
        defaults.set(false, forKey: TarnModule.permissionCard.key)
        watcher.check()
        #expect(spy.released == 1)
    }

    @Test func switchingTheSidebarOffReleasesThemToo() {
        defaults.set("top", forKey: TabStyle.key)
        watcher.check()
        #expect(spy.tabStyle == 1)
        #expect(spy.released == 1)
        #expect(spy.frozen.isEmpty)
        defaults.set("sidebar", forKey: TabStyle.key)
        watcher.check()
        #expect(spy.tabStyle == 2)
        #expect(spy.released == 2)
    }

    @Test func theViewerSwitchReachesTheHosts() {
        defaults.set(false, forKey: TarnModule.viewer.key)
        watcher.check()
        #expect(spy.viewer == 1)
        #expect(spy.menus == 1)
    }

    @Test func theNotificationsGateFollowsTheSwitch() {
        let registry = SessionRegistry()
        registry.isOn = { TarnModules.isOn($0, in: defaults) }
        let surface = SurfaceContext(id: UUID(), focused: false, pwd: nil)
        defaults.set(false, forKey: TarnModule.notifications.key)
        watcher.check()
        #expect(registry.notify("x", surface: surface) == "notifications are off in Settings")
        defaults.set(true, forKey: TarnModule.notifications.key)
        watcher.check()
        #expect(registry.notify("x", surface: surface) == nil)
    }

    // MARK: Guarded entry points of the viewer

    @Test func theViewerEntryPointsDoNothingWhileOff() {
        let host = ViewerHost()
        host.isViewerOn = { false }
        host.toggleFromKey(root: "/tmp")
        #expect(host.models.isEmpty)
        #expect(host.focusFromBlock(.next) == false)
        let message: [String: Any] = ["version": 1, "cmd": "open", "surface": UUID().uuidString, "path": "/tmp/x"]
        #expect(ViewerRouter.openFromSocket(message, viewerOn: false) == "the file viewer is off in Settings")
    }

    @Test func aRestoreWhileOffWaitsAndMakesNoPane() {
        let host = ViewerHost()
        host.isViewerOn = { false }
        host.reopen([], active: 0, root: "/tmp")
        #expect(host.models.isEmpty)
        #expect(host.tree.viewers.isEmpty)
    }
}
