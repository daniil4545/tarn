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
        let model = model ?? makePane(root: root ?? NSHomeDirectory())
        guard model.open(target, background: typingInPane) else {
            if model.snapshot.isEmpty { closePane(saved: [], active: -1) }
            return false
        }
        if focus {
            DispatchQueue.main.async { model.onFocus?() }
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

    private func makePane(root: String) -> ViewerModel {
        let model = ViewerModel(root: root)
        let web = ViewerWebController(model: model)
        model.onClosePane = { [weak self] saved, active in self?.closePane(saved: saved, active: active) }
        self.model = model
        self.web = web
        web.start()
        return model
    }

    var container: NSView? { web?.container }

    /// Closes the pane. A close with tabs registers an undo that reopens them, with Ghostty's timeout.
    func closePane(saved: [ViewerTab], active: Int) {
        guard let model else { return }
        model.shutdown()
        web?.stop()
        web = nil
        self.model = nil
        if let surface = controller?.focusedSurface { Ghostty.moveFocus(to: surface) }
        guard !saved.isEmpty, let controller, let undoManager = controller.undoManager else { return }
        let root = model.tree.root
        undoManager.setActionName("Close Viewer")
        undoManager.registerUndo(withTarget: self, expiresAfter: controller.undoExpiration) { host in
            let reopened = host.model ?? host.makePane(root: root)
            reopened.reopen(saved, active: active)
            DispatchQueue.main.async { reopened.onFocus?() }
        }
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
        if let model = host.model, let container = host.container {
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
            guard let model = controller.viewerHost.model else { return false }
            model.toast("No such file: \(raw)")
        }
        return true
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
