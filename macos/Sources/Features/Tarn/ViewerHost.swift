import AppKit
import OSLog
import SwiftUI

/// The viewers of one window tab and their layout. The layout is a `SplitTree` of leaves
/// (`AreaTree`): the terminal block is one leaf, each viewer is another. Reuses Ghostty's
/// `SplitTree` for the structure and its undo manager and timeout for closing a viewer; the
/// SwiftUI side is `ViewerLayout` (`AreaView.swift`), the drops are `AreaDrop.swift`.
@MainActor
final class ViewerHost: ObservableObject {
    struct Pane {
        let leaf: AreaLeaf
        let model: ViewerModel
        let web: ViewerWebController
    }

    @Published private(set) var tree: AreaTree
    /// What the user is dragging over this tab, if it is a pane.
    @Published private(set) var drag: AreaPayload?
    private var blockLeaf: AreaLeaf
    private var panes: [UUID: Pane] = [:]
    private var lastViewer: UUID?
    private var focusObserver: NSKeyValueObservation?

    weak var window: NSWindow? {
        didSet {
            focusObserver = window?.observe(\.firstResponder) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.noteFocus() }
            }
        }
    }

    init() {
        let leaf = AreaLeaf(kind: .block)
        blockLeaf = leaf
        tree = .block(leaf)
    }

    private var controller: TerminalController? {
        window?.windowController as? TerminalController
    }

    /// The viewers in layout order.
    var models: [ViewerModel] {
        tree.viewers.compactMap { panes[$0.id]?.model }
    }

    /// The viewer that holds the keyboard, else the one used last, else the first.
    var activeModel: ViewerModel? { (focusedPane ?? lastPane)?.model }

    private var focusedPane: Pane? {
        tree.viewers.compactMap { panes[$0.id] }.first { $0.model.hasFocus() }
    }

    private var lastPane: Pane? {
        lastViewer.flatMap { panes[$0] } ?? tree.viewers.first.flatMap { panes[$0.id] }
    }

    private func noteFocus() {
        if let pane = focusedPane { lastViewer = pane.leaf.id }
    }

    func pane(for id: UUID) -> Pane? { panes[id] }

    // MARK: Opening

    /// Opens a file in the viewer in use, creating a viewer beside the terminal block when the tab
    /// has none. `focus` is true for a user's click; an agent's `tarn open` never moves focus.
    @discardableResult
    func open(_ target: OpenTarget, root: String?, focus: Bool) -> Bool {
        // A layout change takes the first responder from the terminal; an agent's open gives it back.
        let responder = focus ? nil : window?.firstResponder
        let existing = focusedPane ?? lastPane
        let typingInPane = !focus && (existing?.model.hasFocus() ?? false)
        let pane = existing ?? makeViewer(root: root ?? NSHomeDirectory(), beside: blockLeaf, edge: .right, share: 0.6)
        guard pane.model.open(target, background: typingInPane) else {
            if pane.model.snapshot.isEmpty { discard(pane.leaf.id) }
            return false
        }
        lastViewer = pane.leaf.id
        if focus {
            DispatchQueue.main.async { pane.model.onFocus?() }
        } else if let responder {
            for delay in [0.0, 0.15] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let window = self?.window, window.firstResponder !== responder else { return }
                    window.makeFirstResponder(responder)
                }
            }
        }
        return true
    }

    /// A new, empty viewer on `edge` of `anchor`; `share` is the part of the room that `anchor` keeps.
    private func makeViewer(root: String, beside anchor: AreaLeaf, edge: AreaEdge, share: Double) -> Pane {
        let pane = makePane(AreaLeaf(kind: .viewer), root: root)
        tree = tree.opening(pane.leaf, beside: anchor, direction: edge.direction, share: share)
        return pane
    }

    /// The model and page of a viewer leaf. The caller puts the leaf into the layout.
    private func makePane(_ leaf: AreaLeaf, root: String) -> Pane {
        let id = leaf.id
        let model = ViewerModel(root: root)
        let web = ViewerWebController(model: model)
        model.onClosePane = { [weak self] saved, active in self?.close(id, saved: saved, active: active) }
        model.onLayout = { [weak self] command in self?.layout(command, from: id) }
        model.onFileDrag = { [weak self] file in
            self?.drag = file.map { .file(FileDrag(path: $0.path, viewer: id, moves: $0.moves, sole: $0.sole)) }
        }
        let grip = web.container.grip
        grip.viewerID = id
        grip.title = { [weak model] in (model?.tabs.activePath).map { ($0 as NSString).lastPathComponent } ?? "Viewer" }
        grip.onDragState = { [weak self] dragging in self?.drag = dragging ? .viewer(id) : nil }
        grip.onEndedOutside = { [weak self] point in self?.detach(id, at: point) }
        let pane = Pane(leaf: leaf, model: model, web: web)
        panes[id] = pane
        lastViewer = id
        web.start()
        return pane
    }

    // MARK: Snapshot

    /// The viewers for a tombstone, or nil when the tab has none.
    func snapshot() -> ViewerSnapshot? {
        let viewers = tree.viewers.compactMap { leaf in
            panes[leaf.id].map { ViewerSnapshot.Viewer(id: leaf.id, root: $0.model.tree.root, tabs: $0.model.snapshot, active: $0.model.tabs.active) }
        }
        guard !viewers.isEmpty, let layout = try? JSONEncoder().encode(tree) else { return nil }
        return ViewerSnapshot(layout: layout, viewers: viewers)
    }

    /// Brings the viewers of a closed tab back into a tab that has none (undo of S16).
    func restore(_ snapshot: ViewerSnapshot) {
        guard panes.isEmpty, let decoded = try? JSONDecoder().decode(AreaTree.self, from: snapshot.layout),
              let block = decoded.block
        else { return }
        blockLeaf = block
        tree = decoded
        for viewer in snapshot.viewers {
            guard let leaf = decoded.leaf(id: viewer.id) else { continue }
            let pane = makePane(leaf, root: viewer.root)
            pane.model.reopen(viewer.tabs, active: viewer.active)
        }
        lastViewer = nil
    }

    // MARK: Closing

    /// Closes a viewer. A close with files registers an undo that puts the viewer back where it was,
    /// with Ghostty's timeout.
    private func close(_ id: UUID, saved: [ViewerTab], active: Int) {
        guard let pane = panes[id] else { return }
        let slot = tree.slot(of: pane.leaf)
        let root = pane.model.tree.root
        discard(id)
        if let surface = controller?.focusedSurface { Ghostty.moveFocus(to: surface) }
        guard !saved.isEmpty, let controller, let undoManager = controller.undoManager else { return }
        undoManager.setActionName("Close Viewer")
        undoManager.registerUndo(withTarget: self, expiresAfter: controller.undoExpiration) { host in
            let anchor = slot.flatMap { host.tree.leaf(id: $0.anchor.id) }
            let reopened = host.makeViewer(
                root: root, beside: anchor ?? host.blockLeaf,
                edge: anchor == nil ? .right : AreaEdge(slot?.direction ?? .right), share: anchor == nil ? 0.6 : 0.5)
            reopened.model.reopen(saved, active: active)
            DispatchQueue.main.async { reopened.model.onFocus?() }
        }
    }

    /// Takes a viewer out of the layout and stops its page. No undo: a moved viewer lives on elsewhere.
    private func discard(_ id: UUID) {
        guard let pane = panes.removeValue(forKey: id) else { return }
        tree = tree.removing(pane.leaf)
        pane.model.shutdown()
        pane.web.stop()
        if lastViewer == id { lastViewer = nil }
    }

    // MARK: Layout commands

    private func layout(_ command: ViewerLayoutCommand, from id: UUID) {
        guard let pane = panes[id] else { return }
        switch command {
        case let .split(edge):
            // S14: the file of the viewer opens in a new viewer beside it.
            guard let path = pane.model.tabs.activePath else { return }
            let new = makeViewer(root: pane.model.tree.root, beside: pane.leaf, edge: edge, share: 0.5)
            guard new.model.open(OpenTarget(path: path), pin: true) else {
                discard(new.leaf.id)
                return
            }
            DispatchQueue.main.async { new.model.onFocus?() }
        case let .focus(direction):
            _ = focus(from: pane.leaf, direction)
        }
    }

    /// Moves the keyboard from the terminal block to the neighbour viewer. False when there is none.
    func focusFromBlock(_ direction: AreaTree.FocusDirection) -> Bool {
        focus(from: blockLeaf, direction)
    }

    private func focus(from leaf: AreaLeaf, _ direction: AreaTree.FocusDirection) -> Bool {
        guard let target = tree.neighbor(of: leaf, direction), target !== leaf else { return false }
        if target.kind == .block {
            guard let surface = controller?.focusedSurface else { return false }
            Ghostty.moveFocus(to: surface)
        } else if let pane = panes[target.id] {
            lastViewer = target.id
            pane.model.onFocus?()
        }
        return true
    }

    func resize(_ node: AreaTree.Node, to ratio: Double) {
        guard let resized = try? tree.replacing(node: node, with: node.resizing(to: ratio)) else { return }
        tree = resized
    }

    func equalize() {
        tree = tree.equalized()
    }

    // MARK: Drops

    /// Called by the terminal pane drag, which Ghostty's grab handle publishes (`DraggingSurfaceKey`).
    /// A drag that came from a page ends with the AppKit session; a click proves it is over.
    func cancelFileDrag() {
        if case .file = drag { drag = nil }
    }

    func terminalDragged(_ id: UUID?) {
        if case .viewer = drag { return }
        drag = id.map { .terminal($0) }
    }

    func dropTarget(at point: CGPoint, in size: CGSize, payload: AreaPayload) -> AreaDropTarget? {
        let lone = (controller?.surfaceTree.count ?? 1) <= 1
        return AreaDrop.target(at: point, in: size, tree: tree, payload: payload, loneTerminal: lone)
    }

    func drop(_ payload: AreaPayload, _ plan: AreaPlan) {
        switch payload {
        case let .viewer(id):
            guard let pane = panes[id] else { return }
            if case let .into(destination) = plan {
                guard destination != id, let target = panes[destination] else { return }
                guard target.model.canAbsorb(pane.model) else {
                    target.model.toast("A file is open here with other edits: save one copy first")
                    return
                }
                target.model.absorb(pane.model)
                discard(id)
                lastViewer = destination
                DispatchQueue.main.async { target.model.onFocus?() }
                return
            }
            tree = tree.placing(pane.leaf, plan)
            lastViewer = id
            DispatchQueue.main.async { pane.model.onFocus?() }
        case let .file(file):
            dropFile(file, plan)
        case .terminal:
            let surface = controller?.focusedSurface
            tree = tree.placing(blockLeaf, plan)
            DispatchQueue.main.async {
                if let surface { Ghostty.moveFocus(to: surface) }
            }
        }
    }

    /// A file tab or tree row dropped on a zone: it joins the viewer under the pointer or opens in a
    /// new viewer there. A tab leaves its viewer with its edits; an emptied viewer closes.
    private func dropFile(_ file: FileDrag, _ plan: AreaPlan) {
        drag = nil
        let source = panes[file.viewer]
        let destination: Pane
        if case let .into(id) = plan {
            guard id != file.viewer, let existing = panes[id] else { return }
            if let source, file.moves, !existing.model.canTake(file.path, from: source.model) {
                existing.model.toast("\((file.path as NSString).lastPathComponent) is open here with other edits")
                return
            }
            destination = existing
        } else {
            destination = makePane(AreaLeaf(kind: .viewer), root: source?.model.tree.root ?? NSHomeDirectory())
            tree = tree.placing(destination.leaf, plan)
        }
        // A tab moves with its edits; a tree row opens the file from disk.
        let placed: Bool
        if let source, file.moves {
            placed = destination.model.take(file.path, from: source.model)
        } else {
            placed = destination.model.open(OpenTarget(path: file.path), pin: true)
        }
        guard placed else {
            // The file did not open (gone, binary, too big): no empty viewer is left behind.
            if destination.model.isEmpty { discard(destination.leaf.id) }
            return
        }
        if let source, file.moves {
            source.model.release(file.path)
            if source.model.isEmpty { discard(file.viewer) }
        }
        lastViewer = destination.leaf.id
        DispatchQueue.main.async { destination.model.onFocus?() }
    }

    /// S14a: a viewer dropped outside every window opens in a new window.
    private func detach(_ id: UUID, at point: NSPoint) {
        guard let pane = panes[id], let controller else { return }
        let created = TerminalController.newWindow(controller.ghostty)
        created.window?.setFrameTopLeftPoint(point)
        let moved = created.viewerHost.makeViewer(
            root: pane.model.tree.root, beside: created.viewerHost.blockLeaf, edge: .right, share: 0.6)
        moved.model.absorb(pane.model)
        discard(id)
    }
}

/// Where a path click or `tarn open` goes.
enum ViewerRouter {
    private static let logger = Logger(subsystem: "tarn", category: "viewer")

    /// Opens a clicked path in the viewer of the clicked surface's window. Returns false to let the
    /// default opener run: URLs, directories, a missing file without a pane, clicks without a
    /// terminal. Files of media, document and archive types open in their own app.
    @MainActor
    static func handle(_ raw: String, from surface: Ghostty.SurfaceView?) -> Bool {
        guard !ViewerPaths.isURL(raw), let surface,
              let controller = surface.window?.windowController as? TerminalController,
              let target = ViewerPaths.resolve(raw, cwd: surface.pwd)
        else { return false }
        switch ViewerPaths.classify(target.path) {
        case .text:
            _ = controller.viewerHost.open(target, root: surface.pwd, focus: true)
        case .system, .directory, .special:
            // Upstream opens these through its untrusted-target policy.
            return false
        case .missing:
            // A pane that is already open says so; without one the default opener runs.
            guard let model = controller.viewerHost.activeModel else { return false }
            model.toast("No such file: \(raw)")
        }
        return true
    }

    /// Ghostty's split keys when the terminal block has no target in that direction: the keyboard
    /// goes to the viewer that lies there (D8). Called from `Ghostty.App.gotoSplit` (insertion
    /// point 14); true if focus moved, so a performable keybind consumes the key.
    @MainActor
    static func focusNeighbor(from surface: Ghostty.SurfaceView, direction: Ghostty.SplitFocusDirection) -> Bool {
        guard let controller = surface.window?.windowController as? TerminalController else { return false }
        return controller.viewerHost.focusFromBlock(direction.toSplitTreeFocusDirection())
    }

    /// `{"version":1,"cmd":"open","surface":<uuid>,"path":<absolute>,"line":<n>}` from the control
    /// socket. Replies `{"ok":true}` or `{"ok":false,"error":...}`. It opens text files only and
    /// never moves focus (`docs/spec.md` 2.2 and 2.5). Returns false for lines that are not commands.
    @MainActor
    static func handleCommand(_ line: Data, reply: ControlSocket.Reply) -> Bool {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              message["cmd"] as? String == "open"
        else { return false }
        let error = openFromSocket(message)
        if let error {
            logger.info("open refused: \(error, privacy: .public) surface=\(message["surface"] as? String ?? "-", privacy: .public)")
        }
        let answer: [String: Any] = error.map { ["ok": false, "error": $0] } ?? ["ok": true]
        reply.send((try? JSONSerialization.data(withJSONObject: answer)).map { $0 + Data("\n".utf8) } ?? Data())
        return true
    }

    @MainActor
    private static func openFromSocket(_ message: [String: Any]) -> String? {
        guard message["version"] as? Int == 1 else { return "tarn: unsupported version" }
        guard let path = message["path"] as? String, path.hasPrefix("/") else {
            return "tarn: the path must be absolute"
        }
        guard let id = (message["surface"] as? String).flatMap(UUID.init(uuidString:)),
              let surface = SessionRegistry.surfaceView(id),
              let controller = surface.window?.windowController as? TerminalController
        else { return "tarn: unknown surface" }
        switch ViewerPaths.classify(path) {
        case .missing: return "tarn: no such file: \(path)"
        case .directory, .special: return "tarn: not a file: \(path)"
        case .system: return "tarn: not a text file: \(path)"
        case .text where ViewerPaths.isBinary(path): return "tarn: not a text file: \(path)"
        case .text:
            let target = OpenTarget(path: URL(fileURLWithPath: path).standardizedFileURL.path, line: message["line"] as? Int)
            return controller.viewerHost.open(target, root: surface.pwd, focus: false) ? nil : "tarn: cannot open: \(path)"
        }
    }
}
