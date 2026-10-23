import SwiftUI

/// The agent state of a tab as a colored dot in its sidebar row.
struct AgentBadge: View {
    let agent: AgentSession

    var body: some View {
        if let color {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .help(TabCard.stateText(agent))
        }
    }

    private var color: Color? {
        switch agent.state {
        case .working: .blue
        case .permission: .orange
        case .waiting where agent.failed: .red
        case .waiting: agent.seen ? Color.secondary.opacity(0.35) : .green
        case .idle: nil
        }
    }
}

/// What a request asks and the buttons that answer it.
struct AgentQuickActions: View {
    let agent: AgentSession
    let request: AgentRequest
    var onAnswer: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !request.detail.isEmpty {
                Text(request.kind == .tool ? "\(request.tool): \(request.detail)" : request.detail)
                    .font(.system(size: 11, design: request.kind == .tool ? .monospaced : .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }

            switch request.kind {
            case .tool:
                HStack(spacing: 6) {
                    Button("Allow") { answer(0) }
                        .buttonStyle(SidebarActionStyle(isPrimary: true))
                    Button("Deny") { answer(1) }
                        .buttonStyle(SidebarActionStyle())
                }
            case .question:
                ForEach(Array(request.options.prefix(9).enumerated()), id: \.offset) { index, label in
                    Button("\(index + 1). \(label)") { answer(index) }
                        .buttonStyle(SidebarActionStyle(alignment: .leading))
                }
            }
        }
    }

    private func answer(_ option: Int) {
        onAnswer()
        SessionRegistry.shared.answer(agent.surfaceID, option: option)
    }
}

/// A flat sidebar button that fills its share of the row, so paired buttons are equal.
/// The primary one is tinted with the accent color.
private struct SidebarActionStyle: ButtonStyle {
    var isPrimary = false
    var alignment: Alignment = .center

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: alignment)
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill(pressed: configuration.isPressed)))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovering = $0 }
    }

    private func fill(pressed: Bool) -> Color {
        let boost = pressed ? 0.15 : (isHovering ? 0.08 : 0)
        return isPrimary
            ? Color.accentColor.opacity(0.85 + boost)
            : Color.primary.opacity(0.10 + boost)
    }
}

/// The hover card of a tab: title, project and folder, and for an agent its state, how
/// long, what it waits for, and quick answers to a permission request or a question.
struct TabCard: View {
    let tab: SidebarModel.Tab
    var onAnswer: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                if !tab.project.isEmpty {
                    Text(tab.project)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let folder = tab.folder, folder != tab.title {
                    Text(folder)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            if let agent = tab.agent {
                HStack(spacing: 6) {
                    AgentBadge(agent: agent)
                    Text(Self.stateText(agent))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.elapsed(from: agent.since, to: context.date))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 12))

                if let request = agent.request {
                    AgentQuickActions(agent: agent, request: request, onAnswer: onAnswer)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func stateText(_ agent: AgentSession) -> String {
        switch agent.state {
        case .working: "Working"
        case .permission: agent.request?.kind == .question ? "Asks a question" : "Needs permission"
        case .waiting where agent.failed: "Stopped with an error"
        case .waiting: agent.seen ? "Done" : "Done, not seen"
        case .idle: "No agent"
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}
