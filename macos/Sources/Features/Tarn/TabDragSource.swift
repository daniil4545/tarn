import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    /// Private drag payloads of the sidebar. They need no `Info.plist` entry: both ends
    /// are AppKit views of this process, like Ghostty's `SurfaceDragSourceView`.
    static let tarnTab = NSPasteboard.PasteboardType("com.daniil4545.tarn.tab")
    static let tarnWorkspace = NSPasteboard.PasteboardType("com.daniil4545.tarn.workspace")
}

/// What is being dragged in the sidebar.
enum SidebarDragKind: Equatable {
    case tab
    case workspace

    init?(_ type: NSPasteboard.PasteboardType) {
        switch type {
        case .tarnTab: self = .tab
        case .tarnWorkspace: self = .workspace
        default: return nil
        }
    }

    var pasteboardType: NSPasteboard.PasteboardType {
        self == .tab ? .tarnTab : .tarnWorkspace
    }
}

/// The gap a drop would land in.
enum SidebarDropSlot: Equatable {
    /// Before a tab row, in that row's workspace.
    case beforeTab(TabKey)
    /// After the last tab of a workspace.
    case endOfWorkspace(Workspace.ID)
    /// Before a workspace header.
    case beforeWorkspace(Workspace.ID)
    /// After the last workspace.
    case end
}

/// What the pointer is over during a drag.
enum SidebarDropTarget: Equatable {
    case tab(TabKey)
    case header(Workspace.ID)
    /// The empty sidebar below the last row.
    case tail
}

extension SidebarModel {
    /// The slot a drop at `target` lands in. `lowerHalf` says which half of the row or header
    /// the pointer is in. A tab dropped on a header goes to the end of that workspace; a
    /// workspace dropped on a row goes before or after the whole workspace, by the half of the
    /// workspace the row is in.
    nonisolated static func dropSlot(
        dragging kind: SidebarDragKind,
        over target: SidebarDropTarget,
        lowerHalf: Bool,
        in groups: [Group]
    ) -> SidebarDropSlot? {
        switch (kind, target) {
        case (.tab, .header(let id)):
            return groups.contains { $0.workspace.id == id } ? .endOfWorkspace(id) : nil

        case (.tab, .tab(let key)):
            guard let group = groups.first(where: { $0.tabs.contains { $0.key == key } }),
                  let index = group.tabs.firstIndex(where: { $0.key == key })
            else { return nil }
            if !lowerHalf { return .beforeTab(key) }
            return group.tabs[safe: index + 1].map { .beforeTab($0.key) } ?? .endOfWorkspace(group.workspace.id)

        case (.workspace, .header(let id)):
            guard let index = groups.firstIndex(where: { $0.workspace.id == id }) else { return nil }
            return lowerHalf ? slot(after: index, in: groups) : .beforeWorkspace(id)

        case (.workspace, .tab(let key)):
            guard let index = groups.firstIndex(where: { $0.tabs.contains { $0.key == key } }),
                  let row = groups[index].tabs.firstIndex(where: { $0.key == key })
            else { return nil }
            let before = (row + (lowerHalf ? 1 : 0)) * 2 <= groups[index].tabs.count
            return before ? .beforeWorkspace(groups[index].workspace.id) : slot(after: index, in: groups)

        case (.tab, .tail):
            return groups.last.map { .endOfWorkspace($0.workspace.id) }

        case (.workspace, .tail):
            return groups.isEmpty ? nil : .end
        }
    }

    private nonisolated static func slot(after index: Int, in groups: [Group]) -> SidebarDropSlot {
        groups[safe: index + 1].map { .beforeWorkspace($0.workspace.id) } ?? .end
    }

    /// The slot the gap shows while `lifted` is dragged. The lifted row takes no space, so
    /// the slot before it is the slot after it: one gap, not two that look the same.
    nonisolated static func gapSlot(_ slot: SidebarDropSlot?, lifted: TabKey, in groups: [Group]) -> SidebarDropSlot? {
        guard slot == .beforeTab(lifted) else { return slot }
        return dropSlot(dragging: .tab, over: .tab(lifted), lowerHalf: true, in: groups)
    }
}

/// The AppKit layer over a sidebar row or header: it owns left clicks, drags out of the row,
/// drops onto it and the context menu, and lets everything else (hover, scroll, buttons
/// beside it) through to the SwiftUI views below.
struct SidebarInteraction: NSViewRepresentable {
    var payload: (() -> (kind: SidebarDragKind, value: String)?)?
    var onClick: () -> Void
    var menu: (() -> NSMenu)?
    /// The pointer is over this view with `kind` dragged; true accepts it.
    var dragOver: (SidebarDragKind, _ value: String, _ lowerHalf: Bool) -> Bool
    var dragExit: () -> Void
    var drop: (SidebarDragKind, _ value: String, _ lowerHalf: Bool) -> Bool
    /// A drag out of this view began; the height is the view's own.
    var dragBegan: (_ height: CGFloat) -> Void = { _ in }
    /// The drag ended at a screen point; true when somebody took it.
    var dragEnded: (_ screenPoint: NSPoint, _ accepted: Bool) -> Void = { _, _ in }
    /// Strips at the sides that stay clickable for SwiftUI buttons below.
    var excludedLeading: CGFloat = 0
    var excludedTrailing: CGFloat = 0

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        update(nsView)
    }

    private func update(_ view: InteractionView) {
        view.payload = payload
        view.onClick = onClick
        view.menuProvider = menu
        view.dragOver = dragOver
        view.dragExit = dragExit
        view.drop = drop
        view.dragBegan = dragBegan
        view.dragEnded = dragEnded
        view.excludedLeading = excludedLeading
        view.excludedTrailing = excludedTrailing
    }

    final class InteractionView: NSView, NSDraggingSource {
        var payload: (() -> (kind: SidebarDragKind, value: String)?)?
        var onClick: () -> Void = {}
        var menuProvider: (() -> NSMenu)?
        var dragOver: (SidebarDragKind, String, Bool) -> Bool = { _, _, _ in false }
        var dragExit: () -> Void = {}
        var drop: (SidebarDragKind, String, Bool) -> Bool = { _, _, _ in false }
        var dragBegan: (CGFloat) -> Void = { _ in }
        var dragEnded: (NSPoint, Bool) -> Void = { _, _ in }
        var excludedLeading: CGFloat = 0
        var excludedTrailing: CGFloat = 0

        private var mouseDownEvent: NSEvent?
        private var didDrag = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.tarnTab, .tarnWorkspace])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        // MARK: Hit testing

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Hover, scroll and the like belong to the views below.
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .leftMouseDown, .leftMouseUp:
                let local = convert(point, from: superview)
                if local.x < excludedLeading || local.x > bounds.width - excludedTrailing { return nil }
                return super.hitTest(point)
            case .leftMouseDragged, .rightMouseDown, .rightMouseUp:
                return super.hitTest(point)
            default:
                return nil
            }
        }

        // MARK: Click and drag out

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control), let menu = menuProvider?() {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return
            }
            mouseDownEvent = event
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !didDrag, let start = mouseDownEvent, let payload = payload?() else { return }
            let from = start.locationInWindow
            let to = event.locationInWindow
            guard hypot(to.x - from.x, to.y - from.y) > 4 else { return }
            didDrag = true

            let item = NSPasteboardItem()
            item.setString(payload.value, forType: payload.kind.pasteboardType)
            let dragging = NSDraggingItem(pasteboardWriter: item)
            dragging.setDraggingFrame(bounds, contents: snapshot())
            beginDraggingSession(with: [dragging], event: start, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            defer { mouseDownEvent = nil }
            guard !didDrag, mouseDownEvent != nil else { return }
            onClick()
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            menuProvider?()
        }

        /// The row as drawn, for the drag image.
        private func snapshot() -> NSImage {
            let host = superview ?? self
            let rect = host.convert(bounds, from: self)
            guard let rep = host.bitmapImageRepForCachingDisplay(in: rect) else {
                return NSImage(size: bounds.size)
            }
            host.cacheDisplay(in: rect, to: rep)
            let image = NSImage(size: rect.size)
            image.addRepresentation(rep)
            return image
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .move
        }

        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            dragBegan(bounds.height)
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            dragEnded(screenPoint, operation != [])
        }

        // MARK: Drop

        private func kind(of info: NSDraggingInfo) -> SidebarDragKind? {
            info.draggingPasteboard.types?.lazy.compactMap(SidebarDragKind.init).first
        }

        private func lowerHalf(_ info: NSDraggingInfo) -> Bool {
            convert(info.draggingLocation, from: nil).y < bounds.midY
        }

        private func respond(_ info: NSDraggingInfo) -> NSDragOperation {
            guard let kind = kind(of: info),
                  let value = info.draggingPasteboard.string(forType: kind.pasteboardType),
                  dragOver(kind, value, lowerHalf(info))
            else { return [] }
            return .move
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { respond(sender) }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { respond(sender) }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            dragExit()
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { dragExit() }
            guard let kind = kind(of: sender),
                  let value = sender.draggingPasteboard.string(forType: kind.pasteboardType)
            else { return false }
            return drop(kind, value, lowerHalf(sender))
        }
    }
}
