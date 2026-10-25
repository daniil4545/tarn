import Foundation

struct ViewerTab: Equatable {
    var path: String
    /// A preview tab shows in italics and is replaced by the next file opened.
    var preview: Bool
    var line: Int?
    /// Grows with every open that carries a line, so the page scrolls again to the same line.
    var jump: Int
}

/// The tab list of one viewer pane. `docs/spec.md` 2.5: a file opens as a preview tab; a double
/// click, an edit or a drag pins it; the next open replaces the preview tab.
struct ViewerTabs: Equatable {
    private(set) var tabs: [ViewerTab] = []
    private(set) var active = -1
    private var jumps = 0

    var activePath: String? {
        tabs.indices.contains(active) ? tabs[active].path : nil
    }

    /// Opens `path`; an open path is activated, not added twice. A background open (an agent's
    /// `tarn open` while the user types in the pane) adds a pinned tab and keeps the active one.
    mutating func open(_ path: String, line: Int? = nil, pin: Bool = false, background: Bool = false) {
        if background, !tabs.isEmpty {
            guard !tabs.contains(where: { $0.path == path }) else { return }
            tabs.append(ViewerTab(path: path, preview: false, line: line, jump: 0))
            if let line { jumpTo(line, at: tabs.count - 1) }
            return
        }
        if let index = tabs.firstIndex(where: { $0.path == path }) {
            active = index
            if pin { tabs[index].preview = false }
            if let line { jumpTo(line, at: index) }
            return
        }
        let tab = ViewerTab(path: path, preview: !pin, line: nil, jump: 0)
        let index: Int
        if !pin, let preview = tabs.firstIndex(where: \.preview) {
            tabs[preview] = tab
            index = preview
        } else {
            index = active + 1
            tabs.insert(tab, at: index)
        }
        active = index
        if let line { jumpTo(line, at: index) }
    }

    private mutating func jumpTo(_ line: Int, at index: Int) {
        jumps += 1
        tabs[index].line = line
        tabs[index].jump = jumps
    }

    mutating func activate(_ index: Int) {
        if tabs.indices.contains(index) { active = index }
    }

    mutating func pin(at index: Int) {
        if tabs.indices.contains(index) { tabs[index].preview = false }
    }

    /// An edit keeps the file: its tab stops being a preview.
    mutating func pin(path: String) {
        if let index = tabs.firstIndex(where: { $0.path == path }) { tabs[index].preview = false }
    }

    /// Closes a tab and returns its path. The caller closes the pane when `tabs` is empty.
    @discardableResult
    mutating func close(at index: Int) -> String? {
        guard tabs.indices.contains(index) else { return nil }
        let path = tabs.remove(at: index).path
        if index < active {
            active -= 1
        } else if index == active {
            active = min(index, tabs.count - 1)
        }
        return path
    }
}
