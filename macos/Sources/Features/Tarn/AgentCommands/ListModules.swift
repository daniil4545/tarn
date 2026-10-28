import Foundation

/// `tarn module ls`: the modules of Settings > Modules and their switches (`docs/specs/agent-cli.md`
/// 4.9), in the table form of `tarn ls`. Read only.
enum ListModules {
    static let columns = ["MODULE", "STATE"]

    @MainActor
    static func run(_ message: [String: Any], _: AgentScope) -> Result<[String: Any], AgentRefusal> {
        let rows = TarnModule.allCases.map { [name($0), state($0)] }
        return message["json"] as? Bool == true
            ? .success(["modules": rows.map { ["module": $0[0], "state": $0[1]] }])
            : .success(["text": text(rows)])
    }

    /// The module id in kebab case: `permissionCard` prints as `permission-card`.
    static func name(_ module: TarnModule) -> String {
        module.rawValue.map { $0.isUppercase ? "-\($0.lowercased())" : String($0) }.joined()
    }

    /// `unavailable`: switched on, but a module it needs is off (Permission card without Sidebar).
    static func state(_ module: TarnModule, in defaults: UserDefaults = .standard) -> String {
        guard TarnModules.stored(module, in: defaults) else { return "off" }
        return TarnModules.isOn(module, in: defaults) ? "on" : "unavailable"
    }

    /// Names are ASCII, so padding by UTF-16 units is exact.
    static func text(_ rows: [[String]]) -> String {
        let width = ([columns] + rows).map { $0[0].count }.max() ?? 0
        return ([columns] + rows).map { $0[0].padding(toLength: width, withPad: " ", startingAt: 0) + "  " + $0[1] + "\n" }.joined()
    }
}
