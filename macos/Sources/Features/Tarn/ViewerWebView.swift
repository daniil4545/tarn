// The asset scheme handler follows MarkEdit EditorViewController.swift (MIT); see THIRD_PARTY.md.

import AppKit
import Carbon.HIToolbox
import Combine
import OSLog
import WebKit

/// The script that paints the viewer page with the theme colors.
enum ViewerColors {
    /// Sets the `--p-*` properties on the page root; without a theme it removes them, and the
    /// page's own dark or light palette shows again.
    static func script(for chrome: ThemeChrome?) -> String {
        let values: [String: Any] = chrome?.viewerVariables
            ?? Dictionary(uniqueKeysWithValues: ThemeChrome.viewerVariableNames.map { ($0, NSNull()) })
        let json = (try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "(function(v){var s=document.documentElement.style;"
            + "for(var k in v){if(v[k]===null)s.removeProperty(k);else s.setProperty(k,v[k]);}})(\(json))"
    }

    /// Makes the colors part of every page load, run at document start: the first paint and a
    /// page reloaded after the web process died already have them. Replaces the earlier script.
    static func install(_ chrome: ThemeChrome?, in content: WKUserContentController) {
        content.removeAllUserScripts()
        content.addUserScript(WKUserScript(
            source: script(for: chrome), injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// The color behind the page (rubber-band scrolling, resize): the theme background, else the
    /// page's own palette: Dracula-dark or white.
    static func underPageColor(for chrome: ThemeChrome?, dark: Bool) -> NSColor {
        if let chrome {
            return NSColor(
                srgbRed: Double(chrome.background.r) / 255, green: Double(chrome.background.g) / 255,
                blue: Double(chrome.background.b) / 255, alpha: 1)
        }
        return dark ? NSColor(srgbRed: 0.157, green: 0.165, blue: 0.212, alpha: 1) : .white
    }
}

/// The web view of a viewer pane. It takes the keys the page cannot see: the menu would give
/// Cmd+S, Cmd+E and Cmd+B to other items, and Cmd+W reaches it as the menu action `close:`. The
/// split and focus items of the menu reach it first in the responder chain, before the terminal
/// controller, so Ghostty's split keys work while a viewer holds the keyboard.
final class ViewerWebView: WKWebView {
    /// The Cmd keys the web view handles itself: key, command sent to the host or page, text for Help.
    /// Help and `command` read this one list; Cmd+B also has the View menu item for a focus in the terminal.
    static let keyTable: [Key] = [
        Key("b", "tree", "Toggle File Viewer (also in the terminal: View menu)"),
        Key("e", "mode", "View or source"),
        Key("s", "save", "Save the file"),
    ]

    struct Key {
        let key: String
        let command: String
        let help: String

        init(_ key: String, _ command: String, _ help: String) {
            self.key = key
            self.command = command
            self.help = help
        }
    }

    /// The key text of a `keyTable` entry, as Help shows it.
    static func keyText(_ entry: Key) -> String { "⌘" + entry.key.uppercased() }

    var onCommand: ((String) -> Void)?
    var onLayout: ((ViewerLayoutCommand) -> Void)?

    /// The pane command of a key press. The typed letter decides, as for the menu, so Dvorak and
    /// Colemak keep their own Cmd+X and Cmd+F. Only when the layout types no ASCII letter (Russian:
    /// the S key types "ы") the physical key decides.
    static func command(characters: String?, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String? {
        let modifiers = flags.intersection([.shift, .control, .option, .command])
        let letter: String
        if let characters, characters.count == 1, characters.unicodeScalars.allSatisfy(\.isASCII) {
            letter = characters.lowercased()
        } else {
            switch Int(keyCode) {
            case kVK_ANSI_S: letter = "s"
            case kVK_ANSI_E: letter = "e"
            case kVK_ANSI_B: letter = "b"
            default: return nil
            }
        }
        // The modifiers are exact: Cmd+Alt+B and Cmd+Shift+B are not Cmd+B.
        guard modifiers == .command else { return nil }
        return keyTable.first { $0.key == letter }?.command
    }

    /// Cmd+= zooms in. Ghostty binds both Cmd+= and Cmd++ to a bigger font, but the menu item
    /// carries only the last one, Cmd++ (`Config.zig` "this order matters"); the terminal gets
    /// Cmd+= through its own keybind, the viewer has only the menu.
    static func isZoomIn(characters: String?, flags: NSEvent.ModifierFlags) -> Bool {
        characters == "=" && flags.intersection([.shift, .control, .option, .command]) == .command
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, Self.isZoomIn(characters: event.charactersIgnoringModifiers, flags: event.modifierFlags),
           let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) {
            ViewerZoom.change(by: 1)
            return true
        }
        guard event.type == .keyDown,
              let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self)
        else { return super.performKeyEquivalent(with: event) }
        if let command = Self.command(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode, flags: event.modifierFlags) {
            onCommand?(command)
            return true
        }
        if forwardToTerminal(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Runs a tab or window keybind (Cmd+1 by default) on the focused terminal of this window,
    /// as if that terminal held the keyboard (`ViewerForwardKeys`).
    private func forwardToTerminal(_ event: NSEvent) -> Bool {
        guard let config = (NSApp.delegate as? AppDelegate)?.ghostty.config,
              let action = ViewerForwardKeys.action(for: event, config: config),
              let surface = (window?.windowController as? BaseTerminalController)?.focusedSurface?.surfaceModel
        else { return false }
        return surface.perform(action: action)
    }

    /// The menu item "Close" (Cmd+W) closes the active file tab, not the terminal behind the pane.
    @objc func close(_ sender: Any?) {
        onCommand?("closeTab")
    }

    /// The font size items of the View menu (Cmd+=, Cmd+-, Cmd+0) zoom the viewer, not the terminal.
    @IBAction func increaseFontSize(_ sender: Any?) { ViewerZoom.change(by: 1) }
    @IBAction func decreaseFontSize(_ sender: Any?) { ViewerZoom.change(by: -1) }
    @IBAction func resetFontSize(_ sender: Any?) { ViewerZoom.change(by: 0) }

    @IBAction func splitRight(_ sender: Any?) { onLayout?(.split(.right)) }
    @IBAction func splitLeft(_ sender: Any?) { onLayout?(.split(.left)) }
    @IBAction func splitDown(_ sender: Any?) { onLayout?(.split(.bottom)) }
    @IBAction func splitUp(_ sender: Any?) { onLayout?(.split(.top)) }
    @IBAction func splitMoveFocusPrevious(_ sender: Any?) { onLayout?(.focus(.previous)) }
    @IBAction func splitMoveFocusNext(_ sender: Any?) { onLayout?(.focus(.next)) }
    @IBAction func splitMoveFocusAbove(_ sender: Any?) { onLayout?(.focus(.spatial(.up))) }
    @IBAction func splitMoveFocusBelow(_ sender: Any?) { onLayout?(.focus(.spatial(.down))) }
    @IBAction func splitMoveFocusLeft(_ sender: Any?) { onLayout?(.focus(.spatial(.left))) }
    @IBAction func splitMoveFocusRight(_ sender: Any?) { onLayout?(.focus(.spatial(.right))) }
    @IBAction func moveSplitDividerUp(_ sender: Any?) { onLayout?(.resize(.up, pane: bounds.size)) }
    @IBAction func moveSplitDividerDown(_ sender: Any?) { onLayout?(.resize(.down, pane: bounds.size)) }
    @IBAction func moveSplitDividerLeft(_ sender: Any?) { onLayout?(.resize(.left, pane: bounds.size)) }
    @IBAction func moveSplitDividerRight(_ sender: Any?) { onLayout?(.resize(.right, pane: bounds.size)) }
    @IBAction func equalizeSplits(_ sender: Any?) { onLayout?(.equalize) }
    /// Zoom is a terminal's (user decision 2026-10-26): from a viewer it does nothing, rather than
    /// zoom the terminal the keyboard is not in.
    @IBAction func splitZoom(_ sender: Any?) {}
}

/// Owns the web view of one viewer pane: loads the page, serves its assets, forwards messages.
@MainActor
final class ViewerWebController: NSObject {
    private static let logger = Logger(subsystem: "tarn", category: "viewer")
    private static let pageURL = URL(string: "\(ViewerRules.scheme)://app/tarn-viewer.html")!

    let container = ViewerPaneView()
    private weak var model: ViewerModel?
    private var webView: ViewerWebView?
    private var started = false
    private var wantsFocus = false
    private var themeObserver: AnyCancellable?
    private var zoomObserver: AnyCancellable?

    init(model: ViewerModel) {
        self.model = model
        super.init()
        zoomObserver = NotificationCenter.default.publisher(for: .tarnViewerZoomDidChange)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.webView?.pageZoom = ViewerZoom.current() }
            }
        // A theme change in Settings reloads the config; the page takes the new colors at once.
        themeObserver = NotificationCenter.default.publisher(for: .ghosttyConfigDidChange)
            .sink { [weak self] note in
                MainActor.assumeIsolated {
                    guard note.object == nil,
                          let config = note.userInfo?[Notification.Name.GhosttyConfigChangeKey] as? Ghostty.Config
                    else { return }
                    self?.applyColors(ThemeChrome.current(for: config))
                }
            }
        model.script = { [weak self] call in self?.webView?.evaluateJavaScript(call) { _, error in
            if let error { Self.logger.error("script failed: \(error.localizedDescription, privacy: .public)") }
        } }
        model.onFocus = { [weak self] in self?.focus() }
        model.hasFocus = { [weak self] in
            guard let web = self?.webView, let responder = web.window?.firstResponder as? NSView else { return false }
            return responder.isDescendant(of: web)
        }
    }

    /// Compiles the rule list, then loads the page. If the rule list does not compile, nothing
    /// loads: the no-network rule must hold before any page runs.
    func start() {
        guard !started else { return }
        started = true
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "tarn-viewer", encodedContentRuleList: ViewerRules.contentRuleListJSON
        ) { [weak self] list, error in
            DispatchQueue.main.async {
                guard let list else {
                    Self.logger.error("rule list failed: \(String(describing: error), privacy: .public)")
                    return
                }
                self?.makeWebView(rules: list)
            }
        }
    }

    private func makeWebView(rules: WKContentRuleList) {
        guard let model else { return }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SchemeProxy(self), forURLScheme: ViewerRules.scheme)
        config.userContentController.add(rules)
        config.userContentController.add(MessageProxy(self), name: "tarn")
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let chrome = (NSApp.delegate as? AppDelegate).flatMap { ThemeChrome.current(for: $0.ghostty.config) }
        ViewerColors.install(chrome, in: config.userContentController)

        let view = ViewerWebView(frame: container.bounds, configuration: config)
        view.navigationDelegate = self
        view.onCommand = { [weak model] in model?.command($0) }
        view.onLayout = { [weak model] in model?.onLayout?($0) }
        view.underPageBackgroundColor = ViewerColors.underPageColor(for: chrome, dark: model.dark)
        view.pageZoom = ViewerZoom.current()
        #if DEBUG
        if #available(macOS 13.3, *) { view.isInspectable = true }
        #endif
        container.install(view)
        webView = view
        view.load(URLRequest(url: Self.pageURL))
        if wantsFocus { DispatchQueue.main.async { [weak self] in self?.focus() } }
    }

    /// Gives the page the keyboard; before the web view exists the request waits for it. While the
    /// view is not in a window yet (a hidden pane that SwiftUI is putting back) it retries with a
    /// doubling delay, as `Ghostty.moveFocus` does (SurfaceView.swift:1075), and gives up at 0.5 s.
    func focus(after delay: TimeInterval? = nil) {
        guard let webView else { wantsFocus = true; return }
        wantsFocus = false
        guard let window = webView.window else {
            let next = delay.map { $0 * 2 } ?? 0.05
            guard next < 0.5 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + next) { [weak self] in self?.focus(after: next) }
            return
        }
        window.makeFirstResponder(webView)
    }

    /// Paints the page with the colors of the terminal theme, or gives it back its own palettes
    /// (`window-theme` system, light or dark). The page's CSS reads the `--p-*` properties.
    /// The loaded page gets the script now; the user script covers the next load.
    fileprivate func applyColors(_ chrome: ThemeChrome?) {
        guard let webView else { return }
        ViewerColors.install(chrome, in: webView.configuration.userContentController)
        webView.evaluateJavaScript(ViewerColors.script(for: chrome)) { _, error in
            if let error { Self.logger.error("colors failed: \(error.localizedDescription, privacy: .public)") }
        }
        webView.underPageBackgroundColor = ViewerColors.underPageColor(for: chrome, dark: model?.dark ?? true)
    }

    func stop() {
        themeObserver = nil
        zoomObserver = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "tarn")
        webView?.removeFromSuperview()
        webView = nil
    }

    /// Keeps the configuration, which the web view retains, from retaining the controller.
    private final class SchemeProxy: NSObject, WKURLSchemeHandler {
        private weak var target: ViewerWebController?

        init(_ target: ViewerWebController) {
            self.target = target
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let target else { return urlSchemeTask.didFailWithError(URLError(.cancelled)) }
            MainActor.assumeIsolated { target.serve(urlSchemeTask) }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
    }

    /// Keeps the content controller from retaining the controller.
    private final class MessageProxy: NSObject, WKScriptMessageHandler {
        private weak var target: ViewerWebController?

        init(_ target: ViewerWebController) {
            self.target = target
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            MainActor.assumeIsolated { target?.model?.handle(body) }
        }
    }
}

extension ViewerWebController: WKNavigationDelegate {
    /// The web content process died (memory pressure): load the page again; the model refills it.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Self.logger.error("web content process terminated")
        model?.pageLost()
        webView.load(URLRequest(url: Self.pageURL))
    }

    /// Only the first load of the page: links are handled by the page and the model.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.request.url == Self.pageURL, navigationAction.navigationType == .other {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
}

extension ViewerWebController {
    fileprivate func serve(_ urlSchemeTask: any WKURLSchemeTask) {
        let url = urlSchemeTask.request.url
        guard let url, let bundle = Bundle.main.resourceURL,
              let asset = ViewerRules.asset(for: url, bundle: bundle, roots: model?.assetRoots ?? []),
              let data = try? Data(contentsOf: asset.file)
        else {
            Self.logger.info("refused \(url?.absoluteString ?? "-", privacy: .public)")
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(
            url: url, mimeType: asset.mimeType, expectedContentLength: data.count,
            textEncodingName: asset.mimeType.hasPrefix("text") ? "utf-8" : nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
}
