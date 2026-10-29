import AppKit
import SwiftUI

/// The header of a workspace in the sidebar: fold arrow, name, and for a folded workspace
/// the tab count and the state of its most urgent agent (a dot, nothing more). A click
/// folds; the + button opens a tab in it; the header drags the whole workspace.
struct WorkspaceHeader: View {
    @ObservedObject var model: SidebarModel
    let group: SidebarModel.Group
    let workspace: Workspace

    @State private var isHovering = false
    @Environment(\.chromeInk) private var ink

    var body: some View {
        HStack(spacing: 4) {
            // One arrow turned a quarter: the fold animates it instead of swapping two symbols.
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(workspace.collapsed ? 0 : 90))
                .animation(Motion.fold, value: workspace.collapsed)
                .frame(width: 10)
            Text(workspace.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            if workspace.collapsed {
                if let agent = group.worstAgent { AgentBadge(agent: agent) }
                Text("\(group.tabs.count)")
                    .foregroundStyle(ink.faint)
            }
            if isHovering {
                Button {
                    model.newTab(in: workspace)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Tab in \(workspace.name)")
                .accessibilityLabel("New Tab in \(workspace.name)")
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
        .overlay(alignment: .top) { dropLine(model.dropSlot == .beforeWorkspace(workspace.id)) }
        .overlay(alignment: .bottom) { dropLine(endsHere) }
        .padding(.vertical, Sidebar.rowGap / 2)
        .padding(.horizontal, Sidebar.listInset)
        .overlay(
            SidebarInteraction(
                payload: { (.workspace, workspace.id.uuidString) },
                onClick: { model.toggleFold(workspace) },
                menu: { model.contextMenu(for: workspace) },
                dragOver: { kind, value, lowerHalf in
                    model.dragOver(kind, value: value, over: .header(workspace.id), lowerHalf: lowerHalf)
                },
                dragExit: { model.dragExit() },
                drop: { kind, value, lowerHalf in
                    model.drop(kind, value: value, over: .header(workspace.id), lowerHalf: lowerHalf)
                },
                dragEnded: { _, _ in model.dragExit() },
                excludedTrailing: isHovering ? Sidebar.listInset + 24 : 0,
                toolTip: Self.tip(group, workspace)
            )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(workspace.collapsed ? "Expand \(workspace.name)" : "Collapse \(workspace.name)")
        .accessibilityAction { model.toggleFold(workspace) }
    }

    /// The folder with `~` for home, and the number of tabs (the demo's tooltip).
    static func tip(_ group: SidebarModel.Group, _ workspace: Workspace) -> String {
        let count = "\(group.tabs.count) tab\(group.tabs.count == 1 ? "" : "s")"
        return workspace.folder.map { "\(WorkspaceFolder.display($0)) \u{B7} \(count)" } ?? count
    }

    /// A workspace dropped after every workspace draws its line under a folded last header.
    private var endsHere: Bool {
        workspace.collapsed && model.dropSlot == .end && model.groups.last?.id == group.id
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

/// The sheets of the workspace commands: a folder, a name, and a delete confirmation.
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

    /// Asks for a group name or a project folder (G2) and creates it. Cancel does nothing (S2).
    static func newGroup(in window: NSWindow) {
        let form = NewGroupForm()
        let alert = NSAlert()
        alert.messageText = "New group"
        alert.accessoryView = form
        let create = alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = form.nameField
        form.onChange = { [weak create, weak form] in create?.isEnabled = form?.choice(confirmed: true) != nil }
        alert.beginSheetModal(for: window) { [weak window] response in
            guard let window, let choice = form.choice(confirmed: response == .alertFirstButtonReturn) else { return }
            WorkspaceRegistry.shared.create(choice, from: window)
        }
    }

    /// Asks before a group goes; `done` gets whether its tabs close with it (G7), unchecked by default.
    static func confirmDelete(
        _ name: String,
        tabCount: Int,
        in window: NSWindow,
        done: @escaping (_ closeTabs: Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Delete group \(name)?"
        alert.alertStyle = .warning
        let close = NSButton(checkboxWithTitle: "Also close its \(tabCount) tab\(tabCount == 1 ? "" : "s")", target: nil, action: nil)
        alert.accessoryView = close
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { done(close.state == .on) }
        }
    }
}

/// What the New Group dialog asks for: a plain group by name, or a workspace by folder (G2).
enum NewGroupChoice: Equatable {
    case group(name: String)
    case workspace(folder: String)

    /// The choice of a closed dialog; nil for Cancel and for a workspace whose folder is not an
    /// existing directory (`~` is the home folder). The sheet disables Create for such a path.
    static func make(confirmed: Bool, isWorkspace: Bool, name: String, folder: String) -> NewGroupChoice? {
        guard confirmed else { return nil }
        if !isWorkspace { return .group(name: WorkspaceSet.cleaned(name) ?? "Group") }
        guard let typed = WorkspaceSet.cleaned(folder) else { return nil }
        let path = (typed as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return .workspace(folder: URL(fileURLWithPath: path).standardized.path)
    }
}

/// The accessory of the New Group dialog: the kind, a name and a typed folder path, as in the demo.
@MainActor
final class NewGroupForm: NSView {
    let nameField = NSTextField(string: "")
    let folderField = NSTextField(string: "")
    /// Called when the kind or a field changes, to enable Create only for a usable choice.
    var onChange: () -> Void = {}
    let groupRadio = NSButton(radioButtonWithTitle: "Group", target: nil, action: nil)
    let workspaceRadio = NSButton(radioButtonWithTitle: "Workspace", target: nil, action: nil)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: 56))
        nameField.placeholderString = "Name"
        folderField.placeholderString = "~/code/project"
        for radio in [groupRadio, workspaceRadio] {
            radio.target = self
            radio.action = #selector(kindChanged)
            radio.widthAnchor.constraint(equalToConstant: 90).isActive = true
        }
        groupRadio.state = .on
        folderField.delegate = self
        nameField.delegate = self
        let rows = NSStackView(views: [
            NSStackView(views: [groupRadio, nameField]),
            NSStackView(views: [workspaceRadio, folderField]),
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func choice(confirmed: Bool) -> NewGroupChoice? {
        .make(confirmed: confirmed, isWorkspace: workspaceRadio.state == .on, name: nameField.stringValue, folder: folderField.stringValue)
    }

    @objc private func kindChanged(_ sender: NSButton) {
        defer { onChange() }
        // The radios stand in different stacks, so AppKit does not pair them.
        groupRadio.state = sender === groupRadio ? .on : .off
        workspaceRadio.state = sender === groupRadio ? .off : .on
        window?.makeFirstResponder(sender === groupRadio ? nameField : folderField)
    }
}

extension TerminalController {
    /// The File menu item "New Group..." (Shift+Cmd+T), found through the responder chain.
    @IBAction func newWorkspace(_ sender: Any?) {
        guard let window else { return }
        WorkspacePrompt.newGroup(in: window)
    }
}

extension NewGroupForm: NSTextFieldDelegate {
    /// A field takes the kind it belongs to, as in the demo.
    func controlTextDidBeginEditing(_ obj: Notification) {
        let isFolder = (obj.object as? NSTextField) === folderField
        workspaceRadio.state = isFolder ? .on : .off
        groupRadio.state = isFolder ? .off : .on
    }

    func controlTextDidChange(_ obj: Notification) {
        onChange()
    }
}
