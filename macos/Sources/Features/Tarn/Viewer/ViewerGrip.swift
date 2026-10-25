import AppKit

extension NSPasteboard.PasteboardType {
    /// Private drag payload of a whole viewer: its id (`docs/plans/s3-windows-contracts.md` section 10).
    static let tarnViewer = NSPasteboard.PasteboardType("com.daniil4545.tarn.viewer")
}

/// What a viewer pane is made of: the web view and, above it, the grab handle that drags the whole
/// viewer with its files. The handle follows Ghostty's `SurfaceGrabHandle`: it shows while the pointer
/// is in the top fifth of the pane (`drag-handle auto`), always, or never.
final class ViewerPaneView: NSView {
    let grip = ViewerGripView()
    private static let nearHeight: CGFloat = 0.2

    var dragHandle: Ghostty.Config.DragHandle = .auto {
        didSet {
            grip.isHidden = dragHandle == .never
            grip.alwaysShown = dragHandle == .always
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(grip)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Puts the page under the handle.
    func install(_ web: NSView) {
        web.frame = bounds
        web.autoresizingMask = [.width, .height]
        addSubview(web, positioned: .below, relativeTo: grip)
    }

    override func layout() {
        super.layout()
        let size = ViewerGripView.size
        grip.frame = NSRect(x: (bounds.width - size.width) / 2, y: bounds.height - size.height, width: size.width, height: size.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        grip.near = convert(event.locationInWindow, from: nil).y > bounds.height * (1 - Self.nearHeight)
    }

    override func mouseExited(with event: NSEvent) {
        grip.near = false
    }
}

/// The three dots of the viewer, as in the mockup: 0.6 opaque when near, 1.0 on hover (D16). The drag
/// session follows `Ghostty.SurfaceDragSourceView` (`Ghostty/Surface View/SurfaceDragSource.swift:82`).
final class ViewerGripView: NSView, NSDraggingSource {
    static let size = NSSize(width: 80, height: 12)

    var viewerID: UUID?
    var dark = true { didSet { needsDisplay = true } }
    /// Name shown on the drag image.
    var title: () -> String = { "Viewer" }
    var onDragState: ((Bool) -> Void)?
    /// The drag ended outside every window; the point is on screen.
    var onEndedOutside: ((NSPoint) -> Void)?

    var near = false { didSet { needsDisplay = true } }
    var alwaysShown = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var cancelledByEscape = false
    private var escapeMonitor: Any?

    deinit {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

    /// Opacity of the dots: Ghostty's handle uses 0.3 and 0.8; here 0.6 and 1.0 (D16).
    static func opacity(near: Bool, hovering: Bool) -> CGFloat {
        hovering ? 1.0 : (near ? 0.6 : 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        let alpha = Self.opacity(near: near || alwaysShown, hovering: hovering)
        guard alpha > 0 else { return }
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(alpha).setFill()
        for index in 0 ..< 3 {
            let center = NSPoint(x: bounds.midX + CGFloat(index - 1) * 8, y: bounds.midY)
            NSBezierPath(ovalIn: NSRect(x: center.x - 2.2, y: center.y - 2.2, width: 4.4, height: 4.4)).fill()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Consumed, so the window does not drag; the drag starts in `mouseDragged`.
    override func mouseDown(with event: NSEvent) {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }

    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDragged(with event: NSEvent) {
        guard let viewerID else { return }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(viewerID.uuidString, forType: .tarnViewer)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = preview()
        let mouse = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(x: mouse.x - image.size.width / 2, y: mouse.y - image.size.height / 2, width: image.size.width, height: image.size.height),
            contents: image)
        onDragState?(true)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    private func preview() -> NSImage {
        let name = title()
        return NSImage(size: NSSize(width: 160, height: 96), flipped: false) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
            ]
            let text = NSAttributedString(string: name, attributes: attributes)
            let size = text.size()
            text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            return true
        }
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        cancelledByEscape = false
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancelledByEscape = true }
            return event
        }
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        NSCursor.closedHand.set()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        onDragState?(false)
        guard operation == [], !cancelledByEscape else { return }
        let insideWindow = NSApplication.shared.windows.contains { $0.isVisible && $0.frame.contains(screenPoint) }
        if !insideWindow { onEndedOutside?(screenPoint) }
    }
}
