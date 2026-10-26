import AppKit
import SwiftUI

/// The drop surface over a tab with viewers: it shows the frame of the zone under the pointer
/// and carries out the drop (`docs/specs/windows-workspaces.md` section 3a). It answers `hitTest`
/// only where the zones are ours (`AreaDrop.target` is not nil) and only during a drag, so clicks
/// and Ghostty's own drops in the terminal block (`TerminalSplitTreeView.swift`, `onDrop`) pass
/// through.
struct AreaDropOverlay: NSViewRepresentable {
    let host: ViewerHost

    func makeNSView(context: Context) -> AreaDropView {
        let view = AreaDropView()
        view.host = host
        return view
    }

    func updateNSView(_ nsView: AreaDropView, context: Context) {
        nsView.host = host
    }
}

final class AreaDropView: NSView {
    weak var host: ViewerHost?
    /// The line where the border of the new pane will be.
    private let lineLayer = CALayer()
    /// The gray plate with the reason of a refusal.
    private let plate = NSView()
    private let label = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        lineLayer.cornerRadius = AreaDrop.lineWidth / 2
        lineLayer.isHidden = true
        layer?.addSublayer(lineLayer)
        plate.wantsLayer = true
        plate.layer?.cornerRadius = 6
        plate.isHidden = true
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        plate.addSubview(label)
        addSubview(plate)
        // Text: the page of a viewer drags a file as a plain-text marker; `host.drag` tells it apart.
        registerForDraggedTypes([.tarnViewer, .ghosttySurfaceId, .string])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Events of the pointer and keyboard that are not part of a drag session. The overlay never
    /// answers them, so a drag state left over from the page cannot take clicks.
    static func isPlainEvent(_ type: NSEvent.EventType?) -> Bool {
        guard let type else { return false }
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
             .mouseMoved, .mouseEntered, .mouseExited, .scrollWheel, .keyDown, .keyUp, .cursorUpdate:
            return true
        default:
            return false
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let type = NSApp.currentEvent?.type
        if Self.isPlainEvent(type) {
            // A click while a page drag is still on record: the session is over.
            if type == .leftMouseDown { host?.cancelFileDrag() }
            return nil
        }
        guard let host, let payload = host.drag else { return nil }
        let local = convert(point, from: superview)
        return host.dropTarget(at: local, in: bounds.size, payload: payload) == nil ? nil : self
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        update(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        update(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hideFrame()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        hideFrame()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { hideFrame() }
        guard let payload = payload(of: sender), let plan = target(of: sender, payload)?.plan else { return false }
        host?.drop(payload, plan)
        return true
    }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let payload = payload(of: sender), let target = target(of: sender, payload) else {
            hideFrame()
            return []
        }
        showFrame(target)
        return target.plan == nil ? [] : .move
    }

    private func target(of sender: NSDraggingInfo, _ payload: AreaPayload) -> AreaDropTarget? {
        host?.dropTarget(at: convert(sender.draggingLocation, from: nil), in: bounds.size, payload: payload)
    }

    private func payload(of sender: NSDraggingInfo) -> AreaPayload? {
        if case .file = host?.drag { return host?.drag }
        let board = sender.draggingPasteboard
        if let text = board.string(forType: .tarnViewer), let id = UUID(uuidString: text) { return .viewer(id) }
        if let data = board.data(forType: .ghosttySurfaceId), data.count == 16 {
            return .terminal(data.withUnsafeBytes { $0.loadUnaligned(as: UUID.self) })
        }
        return nil
    }

    // MARK: The line

    /// A drop shows a line in the system accent where the border of the new pane will be, as a
    /// split in macOS apps does; no fill and no frame of our own (T-151 bug 4). A refusal shows a
    /// gray plate with the reason and no line. Line and plate move in one animation.
    private func showFrame(_ target: AreaDropTarget) {
        let refused = target.refusal != nil || target.plan == nil
        let line = target.plan.flatMap { refused ? nil : AreaDrop.line(for: $0, frame: target.frame) }
        let animated = !lineLayer.isHidden || !plate.isHidden
        effectiveAppearance.performAsCurrentDrawingAppearance {
            lineLayer.backgroundColor = NSColor.controlAccentColor.cgColor
            plate.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.92).cgColor
        }
        if let hint = target.refusal {
            label.stringValue = hint
            label.sizeToFit()
            plate.setFrameSize(NSSize(width: label.frame.width + 16, height: label.frame.height + 6))
            label.setFrameOrigin(NSPoint(x: 8, y: 3))
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? Motion.base : 0
            context.allowsImplicitAnimation = true
            if let line {
                lineLayer.frame = line
            }
            lineLayer.isHidden = line == nil
            plate.isHidden = !refused
            if refused {
                let size = plate.frame.size
                let origin = NSPoint(x: target.frame.midX - size.width / 2, y: target.frame.midY - size.height / 2)
                plate.animator().frame = NSRect(origin: origin, size: size)
            }
        }
    }

    private func hideFrame() {
        lineLayer.isHidden = true
        plate.isHidden = true
    }
}
