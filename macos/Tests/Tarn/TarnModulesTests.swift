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

    // `-TarnModule.workspaces NO` on the command line is a string in the argument domain.
    @Test(arguments: [("NO", false), ("YES", true), ("false", false), ("1", true), ("0", false)])
    func commandLineWordsAreRead(word: String, expected: Bool) {
        defaults.set(word, forKey: TarnModule.workspaces.key)
        #expect(TarnModules.isOn(.workspaces, in: defaults) == expected)
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

    // MARK: Viewer

    @Test func viewerPanesAreDrawnOnlyWhenNotHiddenAndTheModuleIsOn() {
        #expect(ViewerHost.isShown(hidden: false, moduleOn: true))
        #expect(!ViewerHost.isShown(hidden: true, moduleOn: true))
        #expect(!ViewerHost.isShown(hidden: false, moduleOn: false))
        #expect(!ViewerHost.isShown(hidden: true, moduleOn: false))
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

    @Test func theBinaryIsLookedForInTheKnownPlacesFirst() {
        let paths = AgentChecks.candidates(home: "/h")
        #expect(paths == ["/h/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "/h/.claude/local/claude"])
    }
}
