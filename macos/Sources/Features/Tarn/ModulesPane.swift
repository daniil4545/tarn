import SwiftUI

/// Settings > Modules: one switch per module and the Claude Code line.
struct ModulesSettingsPane: View {
    @AppStorage(TabStyle.key) private var style: TabStyle = .sidebar
    @AppStorage(TarnModule.workspaces.key) private var workspaces = true
    @AppStorage(TarnModule.permissionCard.key) private var permissionCard = true
    @AppStorage(TarnModule.notifications.key) private var notifications = true
    @AppStorage(FileViewerSetting.key) private var viewer = true
    @State private var checks: AgentChecks?
    @State private var eventsSeen = SessionRegistry.shared.eventsSeen
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                row(.sidebar, isOn: Binding(
                    get: { style == .sidebar },
                    set: { style = $0 ? .sidebar : .top }
                ))
                row(.viewer, isOn: $viewer)
                row(.workspaces, isOn: $workspaces)
                row(.permissionCard, isOn: $permissionCard)
                row(.notifications, isOn: $notifications)
            }
            Section("Agents") { agentLine }
        }
        .formStyle(.grouped)
        .navigationTitle("Modules")
        .task { await runChecks() }
        .onReceive(tick) { _ in eventsSeen = SessionRegistry.shared.eventsSeen }
    }

    @ViewBuilder
    private func row(_ module: TarnModule, isOn: Binding<Bool>) -> some View {
        let blocked = module.needs.map { !TarnModules.isOn($0) } ?? false
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(module.title)
                    if let needed = module.needs, blocked {
                        Text("needs \(needed.title)").font(.caption).foregroundStyle(.orange)
                    }
                }
                Text(module.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(blocked)
        .accessibilityIdentifier("module-\(module.rawValue)")
    }

    @ViewBuilder
    private var agentLine: some View {
        if let checks {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(checks.version.map { "Claude Code \($0)" } ?? "Claude Code")
                    Spacer()
                    check("found", checks.version != nil)
                    check("plugin", checks.pluginInstalled)
                    check("events", eventsSeen)
                }
                if checks.version == nil { hint(AgentChecks.notFoundHint) }
                if !checks.pluginInstalled { hint(AgentChecks.pluginHint) }
                if !eventsSeen { hint(AgentChecks.eventsHint) }
            }
        } else {
            HStack {
                Text("Claude Code")
                Spacer()
                ProgressView().controlSize(.small)
            }
        }
    }

    private func check(_ name: String, _ ok: Bool) -> some View {
        Label(name, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(ok ? Color.green : Color.orange)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }

    /// The checks run off the main thread when the pane opens.
    private func runChecks() async {
        let seen = SessionRegistry.shared.eventsSeen
        checks = await Task.detached { AgentChecks.run(eventsSeen: seen) }.value
    }
}
