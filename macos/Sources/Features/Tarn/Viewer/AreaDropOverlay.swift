import AppKit
import SwiftUI

/// The drop surface over a tab with viewers: it shows the frame of the zone under the pointer
/// and carries out the drop (`docs/plans/windows-workspaces.md` section 3a). It answers `hitTest`
/// only where the zones are ours (`AreaDrop.target` is not nil) and only during a drag, so clicks
/// and Ghostty's own drops in the terminal block (`TerminalSplitTreeView.swift`, `onDrop`) pass
/// through (C10).
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
    private let frameLayer = CALayer()
    private let label = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        frameLayer.cornerRadius = 8
        frameLayer.borderWidth = 2
        frameLayer.isHidden = true
        layer?.addSublayer(frameLayer)
        label.font = .systemFont(ofSize: 12)
        label.wantsLayer = true
        label.isHidden = true
        addSubview(label)
        // Text: the page of a viewer drags a file as plain text (its path); `host.drag` tells it apart.
        registerForDraggedTypes([.tarnViewer, .ghosttySurfaceId, .string])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
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
            return .terminal(data.withUnsafeBytes { $0.load(as: UUID.self) })
        }
        return nil
    }

    // MARK: The frame

    /// The frame only shows the place, like Rectangle's footprint: neutral, in the text color, and red
    /// only for a refusal. It slides between zones.
    private func showFrame(_ target: AreaDropTarget) {
        let refused = target.refusal != nil || target.plan == nil
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = refused ? NSColor.systemRed : NSColor.labelColor
            frameLayer.backgroundColor = color.withAlphaComponent(refused ? 0.18 : 0.12).cgColor
            frameLayer.borderColor = color.withAlphaComponent(refused ? 1 : 0.45).cgColor
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(frameLayer.isHidden ? 0 : 0.14)
        frameLayer.frame = target.frame.insetBy(dx: 4, dy: 4)
        frameLayer.isHidden = false
        CATransaction.commit()
        label.isHidden = target.refusal == nil
        if let hint = target.refusal {
            label.stringValue = hint
            label.sizeToFit()
            label.setFrameOrigin(NSPoint(x: target.frame.midX - label.frame.width / 2, y: target.frame.midY - label.frame.height / 2))
        }
    }

    private func hideFrame() {
        frameLayer.isHidden = true
        label.isHidden = true
    }
}
