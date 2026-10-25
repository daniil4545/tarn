// Stands in for WKWebView's message handler inside the viewer iframe: the app's bundle posts
// to window.webkit.messageHandlers.tarn; here the host (viewer.js) sets `__host` on the frame.
window.webkit = { messageHandlers: { tarn: { postMessage: (body) => window.frameElement.__host(body) } } };
