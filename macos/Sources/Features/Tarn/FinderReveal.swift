import AppKit

/// Finder reveals the existing file independently of the viewer's file-type rules.
@MainActor
enum FinderReveal {
    static func file(_ text: String, cwd: String?) -> URL? {
        guard !ViewerPaths.isURL(text),
              let target = ViewerPaths.resolve(text, cwd: cwd),
              FileManager.default.fileExists(atPath: target.path) else { return nil }
        return URL(fileURLWithPath: target.path)
    }

    /// The target lives for the menu's lifetime and keeps the resolved path of this click.
    private final class Target: NSObject {
        let url: URL
        init(_ url: URL) { self.url = url }
        @objc func reveal(_ sender: Any?) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    static func add(to menu: NSMenu, file: URL?) {
        guard let file else { return }
        let target = Target(file)
        let item = NSMenuItem(title: "Show in Finder", action: #selector(Target.reveal(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        menu.addItem(.separator())
        menu.addItem(item)
    }

    static func add(to menu: NSMenu, surface: Ghostty.SurfaceView) {
        guard let text = surface.accessibilitySelectedText() else { return }
        add(to: menu, file: file(text, cwd: surface.workingDirectory))
    }
}
