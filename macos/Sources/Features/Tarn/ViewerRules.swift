import Foundation

/// What the viewer's web page may load. `docs/spec.md` 2.5: nothing leaves the machine; the page
/// reads its own assets and local images only through the `tarn-md://` scheme.
enum ViewerRules {
    static let scheme = "tarn-md"

    /// Block every load, then let the own scheme through (tested: three requests to none).
    static let contentRuleListJSON = """
    [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},\
    {"trigger":{"url-filter":"^tarn-md:"},"action":{"type":"ignore-previous-rules"}}]
    """

    static let bundleAssets: Set<String> = ["tarn-viewer.html", "tarn-viewer.css", "tarn-viewer.js", "tarn-mermaid.js"]

    static let imageTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
        "webp": "image/webp", "svg": "image/svg+xml",
    ]

    private static let assetTypes: [String: String] = [
        "html": "text/html", "css": "text/css", "js": "text/javascript",
    ]

    struct Asset: Equatable {
        var file: URL
        var mimeType: String
    }

    /// Maps a request to a file, or nil to refuse it. `tarn-md://app/<name>` is a bundle asset;
    /// `tarn-md://file/<absolute path>` is an image under one of `roots`.
    static func asset(for url: URL, bundle: URL, roots: [String]) -> Asset? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case "app":
            let name = url.lastPathComponent
            guard bundleAssets.contains(name),
                  let type = assetTypes[(name as NSString).pathExtension]
            else { return nil }
            return Asset(file: bundle.appendingPathComponent(name), mimeType: type)
        case "file":
            let ext = url.pathExtension.lowercased()
            guard let type = imageTypes[ext] else { return nil }
            let path = URL(fileURLWithPath: url.path).resolvingSymlinksInPath().standardizedFileURL.path
            let inside = roots.contains { root in
                let resolved = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
                return path.hasPrefix(resolved.hasSuffix("/") ? resolved : resolved + "/")
            }
            return inside ? Asset(file: URL(fileURLWithPath: path), mimeType: type) : nil
        default:
            return nil
        }
    }
}
