import AppKit
import OSLog
import SwiftUI

/// The temporary home of the viewer pane: one pane to the right of the terminal area of a window
/// tab, until the window layout is decided. Everything that depends on this placement is here,
/// so the layout can replace this file. Reuses `SplitView` (as `InspectorView` does) and the
/// window's undo manager.
@MainActor
final class ViewerHost: ObservableObject {
    @Published private(set) var model: ViewerModel?
    @Published var split: CGFloat = 0.6
    /// The pane is hidden with Cmd+B: the model, its tabs and unsaved edits live on, only the
    /// view is out of the layout. Closing the pane (`closePane`) ends it.
    @Published private(set) var hidden = false
    private var web: ViewerWebController?
    weak var window: NSWindow?

    private var controller: TerminalController? {
        window?.windowController as? TerminalController
    }

    /// Opens a file in the pane, creating the pane when needed. `focus` is true for a user's
    /// click; an agent's `tarn open` never moves focus.
    @discardableResult
    func open(_ target: OpenTarget, root: String?, focus: Bool) -> Bool {
        // A layout change takes the first responder from the terminal; an agent's open gives it back.
        let responder = focus ? nil : window?.firstResponder
        let typingInPane = !focus && (model?.hasFocus() ?? false)
        let created = model == nil
        // A click shows a hidden pane (the user acted); an agent's open leaves it hidden.
        if focus { hidden = false }
        let model = model ?? makePane(root: root ?? NSHomeDirectory())
        guard model.open(target, background: typingInPane) else {
            // A pane this call created for a file that cannot open does not stay; a tree-only pane does.
            if created, model.snapshot.isEmpty { closePane(saved: [], active: -1) }
            return false
        }
        if focus {
            DispatchQueue.main.async { model.onFocus?() }
        } else {
            keepFocus(responder)
        }
        return true
    }

    /// A layout change takes the first responder from the terminal; give it back.
    private func keepFocus(_ responder: NSResponder?) {
        guard let responder else { return }
        for delay in [0.0, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let window = self?.window, window.firstResponder !== responder else { return }
                window.makeFirstResponder(responder)
            }
        }
    }

    /// Cmd+B, from the terminal (the View menu item "Toggle File Viewer") or typed in the pane (the web
    /// view takes the key first, so there is one path per focus). It opens and hides, it never closes:
    /// no pane opens one with the tree and the keyboard in it; a hidden pane comes back as it was
    /// with the keyboard in it; a shown pane (with files or not) hides whole, tabs, unsaved edits and
    /// tree state kept, and the keyboard goes to the terminal. Cmd+W closes.
    func toggleFromKey(root: String?) {
        guard let model else { return openTreeOnly(root: root) }
        if hidden { return show() }
        // The page holds an edit back for 120 ms; send it before the page leaves the window.
        model.flushPendingEdit()
        hidePane()
    }

    private func focusTreeSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.model?.focusTreeInPage()
        }
    }

    private func openTreeOnly(root: String?) {
        makePane(root: root ?? NSHomeDirectory()).revealTree()
        focusTreeSoon()
    }

    /// Hides the pane keeping its model; the keyboard goes to the terminal.
    func hidePane() {
        hidden = true
        returnFocusToTerminal()
    }

    /// Brings a hidden pane back with the keyboard in it. The focus request waits for the web view to
    /// join the window, as Ghostty's `moveFocus` does after a split change (SurfaceView.swift:1075).
    private func show() {
        hidden = false
        DispatchQueue.main.async { [weak self] in self?.model?.onFocus?() }
    }

    /// Replaced in tests, which have no terminal window.
    var focusTerminal: (() -> Void)?

    private func returnFocusToTerminal() {
        if let focusTerminal { return focusTerminal() }
        if let surface = controller?.focusedSurface { Ghostty.moveFocus(to: surface) }
    }

    private func makePane(root: String) -> ViewerModel {
        let model = ViewerModel(root: root)
        let web = ViewerWebController(model: model)
        model.onClosePane = { [weak self] saved, active in self?.closePane(saved: saved, active: active, undoable: true) }
        model.onHidePane = { [weak self] in self?.hidePane() }
        model.onPaneKey = { [weak self] in self?.toggleFromKey(root: nil) }
        self.model = model
        self.web = web
        web.start()
        return model
    }

    var container: NSView? { web?.container }

    /// Closes the pane. A close by the user (`undoable`) registers an undo that reopens its tabs, or the empty tree pane, with Ghostty's timeout.
    func closePane(saved: [ViewerTab], active: Int, undoable: Bool = false) {
        guard let model else { return }
        model.shutdown()
        web?.stop()
        web = nil
        self.model = nil
        hidden = false
        returnFocusToTerminal()
        guard undoable, let controller, let undoManager = controller.undoManager else { return }
        let root = model.tree.root
        undoManager.setActionName("Close Viewer")
        undoManager.registerUndo(withTarget: self, expiresAfter: controller.undoExpiration) { host in
            host.restore(saved, active: active, root: root)
        }
    }

    /// The undo of a close: the tabs come back, in a pane that is shown (a pane opened and hidden
    /// since the close takes them too).
    func restore(_ saved: [ViewerTab], active: Int, root: String) {
        hidden = false
        let reopened = model ?? makePane(root: root)
        reopened.reopen(saved, active: active)
        DispatchQueue.main.async { reopened.onFocus?() }
    }
}

extension TerminalController {
    /// The View menu item "Toggle File Viewer" (Cmd+B), found through the responder chain from the terminal.
    @IBAction func toggleViewer(_ sender: Any?) {
        viewerHost.toggleFromKey(root: focusedSurface?.workingDirectory)
    }
}

/// Puts the viewer pane to the right of a window's terminal area.
struct ViewerLayout<Content: View>: View {
    @ObservedObject var host: ViewerHost
    @ObservedObject var ghostty: Ghostty.App
    let content: Content

    init(host: ViewerHost, ghostty: Ghostty.App, @ViewBuilder content: () -> Content) {
        self.host = host
        self.ghostty = ghostty
        self.content = content()
    }

    var body: some View {
        if let model = host.model, !host.hidden, let container = host.container {
            SplitView(.horizontal, $host.split, dividerColor: ghostty.config.splitDividerColor, left: {
                content
            }, right: {
                ViewerPane(container: container)
                    .onAppear { model.dark = isDark }
                    .onChange(of: ghostty.config.backgroundColor) { _ in model.dark = isDark }
            }, onEqualize: {
                host.split = 0.5
            })
        } else {
            content
        }
    }

    private var isDark: Bool {
        !NSColor(ghostty.config.backgroundColor).isLightColor
    }
}

private struct ViewerPane: NSViewRepresentable {
    let container: NSView

    func makeNSView(context: Context) -> NSView { container }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Where a path click or `tarn open` goes.
enum ViewerRouter {
    private static let logger = Logger(subsystem: "tarn", category: "viewer")

    /// The `open_url` action as it reaches us, for diagnosing a click that does nothing. Debug level;
    /// the URL is logged only for kind `unknown` (a path), never for links from terminal output.
    /// Watch: `log stream --level debug --predicate 'subsystem == "tarn" AND category == "viewer"'`.
    static func trace(kind: String, url: String, surfaceTarget: Bool) {
        logger.debug("open_url kind=\(kind, privacy: .public) url=\(kind == "unknown" ? url : "-", privacy: .public) surfaceTarget=\(surfaceTarget)")
    }

    /// What a clicked path becomes. The reason of a refusal is logged: a click that does nothing
    /// must be explainable from `log stream --predicate 'subsystem == "com.mitchellh.ghostty"'`.
    enum Decision: Equatable {
        case open(OpenTarget)
        /// A pane that is already open reports the missing file; otherwise the default opener runs.
        case missing(raw: String)
        case upstream(reason: String)
    }

    /// The pure part of a path click: which of the three outcomes `raw` leads to.
    static func decide(_ raw: String, cwd: String?) -> Decision {
        if ViewerPaths.isURL(raw) { return .upstream(reason: "a URL") }
        guard let target = ViewerPaths.resolve(raw, cwd: cwd) else {
            return .upstream(reason: cwd == nil ? "relative path and the terminal has no working directory" : "not a path")
        }
        switch ViewerPaths.classify(target.path) {
        case .text: return .open(target)
        case .system: return .upstream(reason: "a media, document or archive type")
        case .directory: return .upstream(reason: "a directory")
        case .special: return .upstream(reason: "not a regular file")
        case .missing: return .missing(raw: raw)
        }
    }

    /// Opens a clicked path in the viewer of the clicked surface's window. Returns false to let the
    /// default opener run: URLs, directories, a missing file without a pane, clicks without a
    /// terminal. Files of media, document and archive types open in their own app.
    @MainActor
    static func handle(_ raw: String, from surface: Ghostty.SurfaceView?) -> Bool {
        guard let surface else {
            logger.debug("click on \(raw, privacy: .public) refused: no surface")
            return false
        }
        guard let controller = surface.window?.windowController as? TerminalController else {
            logger.debug("click on \(raw, privacy: .public) refused: the surface has no terminal window")
            return false
        }
        let cwd = surface.workingDirectory
        let decision = decide(raw, cwd: cwd)
        logger.debug("click on \(raw, privacy: .public) cwd=\(cwd ?? "-", privacy: .public) -> \(String(describing: decision), privacy: .public)")
        switch decision {
        case let .open(target):
            _ = controller.viewerHost.open(target, root: cwd, focus: true)
            return true
        case let .missing(raw):
            guard let model = controller.viewerHost.model else { return false }
            model.toast("No such file: \(raw)")
            return true
        case .upstream:
            return false
        }
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
            return controller.viewerHost.open(target, root: surface.workingDirectory, focus: false) ? nil : "tarn: cannot open: \(path)"
        }
    }
}
