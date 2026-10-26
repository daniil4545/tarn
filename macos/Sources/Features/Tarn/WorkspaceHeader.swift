import AppKit
import SwiftUI

/// The header of a workspace in the sidebar: fold arrow, name, and for a folded workspace
/// the tab count and the state of its most urgent agent (a dot, nothing more). A click
/// folds; the + button opens a tab in it; the header drags the whole workspace.
struct WorkspaceHeader: View {
    @ObservedObject var model: SidebarModel
    let group: SidebarModel.Group

    @State private var isHovering = false
    @Environment(\.chromeInk) private var ink

    var body: some View {
        HStack(spacing: 4) {
            // One arrow turned a quarter: the fold animates it instead of swapping two symbols.
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(group.workspace.collapsed ? 0 : 90))
                .animation(Motion.fold, value: group.workspace.collapsed)
                .frame(width: 10)
            Text(group.workspace.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            if group.workspace.collapsed {
                if let agent = group.worstAgent { AgentBadge(agent: agent) }
                Text("\(group.tabs.count)")
                    .foregroundStyle(ink.faint)
            }
            if isHovering {
                Button {
                    model.newTab(in: group)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Tab in \(group.workspace.name)")
                .accessibilityLabel("New Tab in \(group.workspace.name)")
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(ink.muted)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .frame(height: 26)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .overlay(alignment: .top) { dropLine(model.dropSlot == .beforeWorkspace(group.workspace.id)) }
        .overlay(alignment: .bottom) { dropLine(endsHere) }
        .padding(.vertical, Sidebar.rowGap / 2)
        .padding(.horizontal, Sidebar.listInset)
        .overlay(
            SidebarInteraction(
                payload: { (.workspace, group.workspace.id.uuidString) },
                onClick: { model.toggleFold(group) },
                menu: { model.contextMenu(for: group) },
                dragOver: { kind, value, lowerHalf in
                    model.dragOver(kind, value: value, over: .header(group.workspace.id), lowerHalf: lowerHalf)
                },
                dragExit: { model.dragExit() },
                drop: { kind, value, lowerHalf in
                    model.drop(kind, value: value, over: .header(group.workspace.id), lowerHalf: lowerHalf)
                },
                dragEnded: { _, _ in model.dragExit() },
                excludedTrailing: isHovering ? Sidebar.listInset + 24 : 0
            )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(group.workspace.collapsed ? "Expand \(group.workspace.name)" : "Collapse \(group.workspace.name)")
        .accessibilityAction { model.toggleFold(group) }
    }

    /// A workspace dropped after every workspace draws its line under a folded last header.
    private var endsHere: Bool {
        group.workspace.collapsed && model.dropSlot == .end && model.groups.last?.id == group.id
    }
}

/// The line that shows where a drop lands.
func dropLine(_ isShown: Bool) -> some View {
    Rectangle()
        .fill(Color.accentColor)
        .frame(height: 2)
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(false)
}

/// The sheets of the workspace commands: a name, and a delete confirmation.
@MainActor
enum WorkspacePrompt {
    /// Asks for a name; `done` gets the trimmed text of an OK, never a blank one.
    static func askName(
        title: String,
        message: String,
        initial: String,
        in window: NSWindow,
        done: @escaping (String) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { done(name) }
        }
    }

    /// Asks for a name and creates the workspace with one new tab in `window`.
    static func newWorkspace(in window: NSWindow) {
        askName(title: "New Workspace", message: "The workspace opens with one new tab.", initial: "", in: window) { [weak window] name in
            guard let window else { return }
            WorkspaceRegistry.shared.createWorkspace(named: name, from: window)
        }
    }

    /// Names the count of tabs that move.
    static func confirmDelete(
        _ name: String,
        tabCount: Int,
        heir: String,
        in window: NSWindow,
        done: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Delete Workspace \u{201C}\(name)\u{201D}?"
        alert.informativeText = tabCount == 0
            ? "The workspace is empty."
            : "Its \(tabCount == 1 ? "tab moves" : "\(tabCount) tabs move") to \u{201C}\(heir)\u{201D}. No tab is closed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { done() }
        }
    }
}

extension TerminalController {
    /// The File menu item "New Workspace" (Shift+Cmd+T), found through the responder chain.
    @IBAction func newWorkspace(_ sender: Any?) {
        guard let window else { return }
        WorkspacePrompt.newWorkspace(in: window)
    }
}
