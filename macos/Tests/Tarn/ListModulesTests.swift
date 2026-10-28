import Foundation
import Testing
@testable import Ghostty

/// `tarn module ls` (`docs/specs/agent-cli.md` 4.9).
@Suite
struct ListModulesTests {
    private let defaults: UserDefaults

    init() {
        let name = "tarn.module.ls.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    @Test func namesAreKebabCase() {
        #expect(TarnModule.allCases.map(ListModules.name) == ["sidebar", "viewer", "workspaces", "permission-card", "notifications"])
    }

    @Test func stateIsOnOffOrUnavailableWhenANeededModuleIsOff() {
        #expect(ListModules.state(.permissionCard, in: defaults) == "on")
        defaults.set("top", forKey: TarnModule.sidebar.key)
        #expect(ListModules.state(.sidebar, in: defaults) == "off")
        #expect(ListModules.state(.permissionCard, in: defaults) == "unavailable")
        defaults.set(false, forKey: TarnModule.permissionCard.key)
        #expect(ListModules.state(.permissionCard, in: defaults) == "off")
    }

    @Test func textIsAPaddedTableWithAHeader() {
        let text = ListModules.text([["viewer", "on"], ["permission-card", "unavailable"]])
        #expect(text == "MODULE           STATE\nviewer           on\npermission-card  unavailable\n")
    }

    @Test @MainActor func replyListsEveryModule() throws {
        let caller = PaneRow(pane: UUID(), tab: UUID(), workspace: UUID())
        let message: [String: Any] = ["version": 1, "cmd": "modules", "surface": caller.pane.uuidString, "json": true]
        let data = AgentCommands.answer("modules", ListModules.run, message: message, panes: [caller])
        let reply = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(reply["modules"] as? [[String: String]])
        #expect(rows.compactMap { $0["module"] } == TarnModule.allCases.map(ListModules.name))
        #expect(rows.allSatisfy { ["on", "off", "unavailable"].contains($0["state"]) })
    }
}
