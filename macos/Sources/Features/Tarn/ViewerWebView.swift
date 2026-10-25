// The asset scheme handler follows MarkEdit EditorViewController.swift (MIT); see THIRD_PARTY.md.

import AppKit
import OSLog
import WebKit

/// The web view of a viewer pane. It takes the keys the page cannot see: the menu would give
/// Cmd+S, Cmd+E and Cmd+B to other items, and Cmd+W reaches it as the menu action `close:`.
final class ViewerWebView: WKWebView {
    var onCommand: ((String) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self),
              let command = ["s": "save", "e": "mode", "b": "tree"][event.charactersIgnoringModifiers ?? ""]
        else { return super.performKeyEquivalent(with: event) }
        onCommand?(command)
        return true
    }

    /// The menu item "Close" (Cmd+W) closes the active file tab, not the terminal behind the pane.
    @objc func close(_ sender: Any?) {
        onCommand?("closeTab")
    }
}

/// Owns the web view of one viewer pane: loads the page, serves its assets, forwards messages.
@MainActor
final class ViewerWebController: NSObject {
    private static let logger = Logger(subsystem: "tarn", category: "viewer")
    private static let pageURL = URL(string: "\(ViewerRules.scheme)://app/tarn-viewer.html")!

    let container = NSView()
    private weak var model: ViewerModel?
    private var webView: ViewerWebView?
    private var started = false
    private var wantsFocus = false

    init(model: ViewerModel) {
        self.model = model
        super.init()
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

        let view = ViewerWebView(frame: container.bounds, configuration: config)
        view.autoresizingMask = [.width, .height]
        view.navigationDelegate = self
        view.onCommand = { [weak model] in model?.command($0) }
        view.underPageBackgroundColor = model.dark ? NSColor(srgbRed: 0.157, green: 0.165, blue: 0.212, alpha: 1) : .white
        #if DEBUG
        if #available(macOS 13.3, *) { view.isInspectable = true }
        #endif
        container.addSubview(view)
        webView = view
        view.load(URLRequest(url: Self.pageURL))
        if wantsFocus { DispatchQueue.main.async { [weak self] in self?.focus() } }
    }

    /// Gives the page the keyboard; before the web view exists the request waits for it.
    func focus() {
        guard let webView else { wantsFocus = true; return }
        wantsFocus = false
        webView.window?.makeFirstResponder(webView)
    }

    func stop() {
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
