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
    /// After the last tab of a workspace, or of a block of ungrouped tabs (named by its id).
    case endOfWorkspace(UUID)
    /// Below all rows, ungrouped, when the last block is a workspace.
    case tail
    /// Before a block: a workspace header, or the first row of a run of ungrouped tabs (its id).
    case beforeWorkspace(UUID)
    /// After the last workspace.
    case end
}

/// What the pointer is over during a drag.
enum SidebarDropTarget: Equatable {
    case tab(TabKey)
    case header(Workspace.ID)
    case margin(UUID)
    /// The empty sidebar below the last row.
    case tail
}

extension SidebarModel {
    /// `lowerHalf` measures the row for tab drags, the whole block for group drags.
    nonisolated static func dropSlot(
        dragging kind: SidebarDragKind,
        over target: SidebarDropTarget,
        lowerHalf: Bool,
        in groups: [Group]
    ) -> SidebarDropSlot? {
        switch (kind, target) {
        case (_, .margin(let id)):
            return groups.contains { $0.id == id } ? .beforeWorkspace(id) : nil

        case (.tab, .header(let id)):
            return groups.contains { $0.workspace?.id == id } ? .endOfWorkspace(id) : nil

        case (.tab, .tab(let key)):
            guard let group = groups.first(where: { $0.tabs.contains { $0.key == key } }),
                  let index = group.tabs.firstIndex(where: { $0.key == key })
            else { return nil }
            if !lowerHalf { return .beforeTab(key) }
            return group.tabs[safe: index + 1].map { .beforeTab($0.key) } ?? .endOfWorkspace(group.id)

        case (.workspace, .header(let id)):
            guard let index = groups.firstIndex(where: { $0.workspace?.id == id }) else { return nil }
            return lowerHalf ? slot(after: index, in: groups) : .beforeWorkspace(id)

        case (.workspace, .tab(let key)):
            guard let index = groups.firstIndex(where: { $0.tabs.contains { $0.key == key } })
            else { return nil }
            return lowerHalf ? slot(after: index, in: groups) : .beforeWorkspace(groups[index].id)

        case (.tab, .tail):
            guard let last = groups.last else { return nil }
            return last.workspace == nil ? .endOfWorkspace(last.id) : .tail

        case (.workspace, .tail):
            return groups.isEmpty ? nil : .end
        }
    }

    /// Before the next block below `index`, or the end.
    private nonisolated static func slot(after index: Int, in groups: [Group]) -> SidebarDropSlot {
        groups[safe: index + 1].map { .beforeWorkspace($0.id) } ?? .end
    }

    /// The slot while `lifted` is dragged. The slot before the lifted row and the slot after it
    /// both leave the tab where it is: they are one slot, the row's own, which opens no gap.
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
    var dragMoved: (NSPoint) -> Void = { _ in }
    /// Strips at the sides that stay clickable for SwiftUI buttons below.
    var excludedLeading: CGFloat = 0
    var excludedTrailing: CGFloat = 0
    /// The padding around the drawn card, left out of the drag image.
    var cardInset = NSEdgeInsetsZero
    var blockView: (() -> NSView?)?
    var toolTip: String?

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
        view.dragMoved = dragMoved
        view.excludedLeading = excludedLeading
        view.excludedTrailing = excludedTrailing
        view.cardInset = cardInset
        view.blockView = blockView
        view.toolTip = toolTip
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
        var dragMoved: (NSPoint) -> Void = { _ in }
        var excludedLeading: CGFloat = 0
        var excludedTrailing: CGFloat = 0
        var cardInset = NSEdgeInsetsZero
        var blockView: (() -> NSView?)?

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
            let block = payload.kind == .workspace ? blockView?() : nil
            let card = block.map { convert($0.bounds, from: $0) } ?? NSRect(
                x: bounds.minX + cardInset.left, y: bounds.minY + cardInset.bottom,
                width: bounds.width - cardInset.left - cardInset.right,
                height: bounds.height - cardInset.top - cardInset.bottom
            )
            dragging.setDraggingFrame(card, contents: snapshot(of: card, radius: block == nil ? Sidebar.cardRadius : 10))
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

        /// The row as drawn, for the drag image. SwiftUI draws the row in its hosting view: the
        /// representable's own host draws nothing, and its snapshot is blank.
        private func snapshot(of card: NSRect, radius: CGFloat) -> NSImage {
            let host = window?.contentView ?? self
            let rect = host.convert(card, from: self)
            guard let rep = host.bitmapImageRepForCachingDisplay(in: rect) else {
                return NSImage(size: card.size)
            }
            host.cacheDisplay(in: rect, to: rep)
            // Clipped to the card's corners, so no sidebar shows at its edges.
            return NSImage(size: rect.size, flipped: false) { frame in
                NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
                rep.draw(in: frame)
                return true
            }
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .move
        }

        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            dragBegan(payload?()?.kind == .workspace ? blockView?()?.bounds.height ?? bounds.height : bounds.height)
        }

        func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
            dragMoved(screenPoint)
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            dragEnded(screenPoint, operation != [])
        }

        // MARK: Drop

        private func kind(of info: NSDraggingInfo) -> SidebarDragKind? {
            info.draggingPasteboard.types?.lazy.compactMap(SidebarDragKind.init).first
        }

        private func lowerHalf(_ info: NSDraggingInfo) -> Bool {
            if kind(of: info) == .workspace, let block = blockView?() {
                let point = block.convert(info.draggingLocation, from: nil)
                return block.isFlipped ? point.y > block.bounds.midY : point.y < block.bounds.midY
            }
            return convert(info.draggingLocation, from: nil).y < bounds.midY
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
