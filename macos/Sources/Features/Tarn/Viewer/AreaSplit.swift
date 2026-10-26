import SwiftUI

/// The numbers of an area divider: where Ghostty's `SplitView` draws its line, and what a drag at a
/// point means. Pure, so a test checks them.
enum AreaDivider {
    /// Width of the grab strip over a divider. Ghostty's own strip is 7 pt, 3.5 pt on each side of
    /// the line; the pane views beside the line take the clicks there, so it is hard to catch.
    static let hitWidth: CGFloat = 14
    /// How much of the strip lies before the line, over the first (left or top) pane. That pane has
    /// the scroll bar at this edge, so the strip covers no more of it than Ghostty's own does; the
    /// rest lies over the second pane, whose edge holds no scroll bar.
    static let hitBefore: CGFloat = 3.5
    /// The least size of a pane in a drag, as in `SplitView` (`minSize`).
    static let minSize: CGFloat = 10

    /// Where the line is along the split axis in a split of `length`: `SplitView.leftRect` and
    /// `splitterPoint` (`Features/Splits/SplitView.swift`) with whole-point increments.
    static func linePosition(ratio: CGFloat, length: CGFloat) -> CGFloat {
        let raw = length * ratio - 0.5
        return raw - raw.truncatingRemainder(dividingBy: 1)
    }

    /// The grab strip in a split of `size`, in points from the top left.
    static func strip(direction: SplitViewDirection, ratio: CGFloat, size: CGSize) -> CGRect {
        let length = direction == .horizontal ? size.width : size.height
        let start = linePosition(ratio: ratio, length: length) - hitBefore
        return direction == .horizontal
            ? CGRect(x: start, y: 0, width: hitWidth, height: size.height)
            : CGRect(x: 0, y: start, width: size.width, height: hitWidth)
    }

    /// The ratio a drag to `location` along the axis gives, as in `SplitView.dragGesture`. Nil when
    /// the split is too short to move.
    static func ratio(at location: CGFloat, length: CGFloat) -> CGFloat? {
        guard length > 2 * minSize else { return nil }
        return min(max(minSize, location), length - minSize) / length
    }
}

/// One split of the area: Ghostty's `SplitView` unchanged, with a wider transparent grab strip over
/// its divider (`AreaDividerStrip`). The strip changes the same ratio and equalizes on a double
/// click, as the divider does.
struct AreaSplit<L: View, R: View>: View {
    let direction: SplitViewDirection
    let ratio: CGFloat
    let dividerColor: Color
    let onResize: (CGFloat) -> Void
    let onEqualize: () -> Void
    let left: L
    let right: R

    init(
        direction: SplitViewDirection,
        ratio: CGFloat,
        dividerColor: Color,
        onResize: @escaping (CGFloat) -> Void,
        onEqualize: @escaping () -> Void,
        @ViewBuilder left: () -> L,
        @ViewBuilder right: () -> R
    ) {
        self.direction = direction
        self.ratio = ratio
        self.dividerColor = dividerColor
        self.onResize = onResize
        self.onEqualize = onEqualize
        self.left = left()
        self.right = right()
    }

    var body: some View {
        SplitView(
            direction,
            .init(get: { ratio }, set: onResize),
            dividerColor: dividerColor,
            left: { left },
            right: { right },
            onEqualize: onEqualize)
            .overlay {
                AreaDividerStrip(direction: direction, ratio: ratio, onResize: onResize, onEqualize: onEqualize)
            }
    }
}

/// The grab strip as an AppKit view over the whole split. It answers hit tests only inside the strip
/// and only for the left mouse button and pointer movement, so that a scroll wheel, a right click and
/// the rest reach the pane under it (a SwiftUI view would take them all and drop the wheel). Being
/// an AppKit view above the panes' own views, it takes the left clicks in the strip.
struct AreaDividerStrip: NSViewRepresentable {
    let direction: SplitViewDirection
    let ratio: CGFloat
    let onResize: (CGFloat) -> Void
    let onEqualize: () -> Void

    func makeNSView(context: Context) -> StripView {
        let view = StripView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: StripView, context: Context) {
        update(nsView)
    }

    private func update(_ view: StripView) {
        view.onResize = onResize
        view.onEqualize = onEqualize
        if view.direction != direction || view.ratio != ratio {
            view.direction = direction
            view.ratio = ratio
            view.window?.invalidateCursorRects(for: view)
        }
    }

    final class StripView: NSView {
        var direction: SplitViewDirection = .horizontal
        var ratio: CGFloat = 0.5
        var onResize: (CGFloat) -> Void = { _ in }
        var onEqualize: () -> Void = {}

        override var isFlipped: Bool { true }

        private var strip: CGRect {
            AreaDivider.strip(direction: direction, ratio: ratio, size: bounds.size)
        }

        /// The events the strip takes: the left button, and the pointer moving for the cursor.
        static func claims(_ type: NSEvent.EventType?) -> Bool {
            switch type {
            case .leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved, .cursorUpdate, .mouseEntered, .mouseExited:
                return true
            default:
                return false
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard Self.claims(NSApp.currentEvent?.type), strip.contains(convert(point, from: superview)) else { return nil }
            return self
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(strip, cursor: direction == .horizontal ? .resizeLeftRight : .resizeUpDown)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { onEqualize() }
        }

        override func mouseDragged(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            let horizontal = direction == .horizontal
            let length = horizontal ? bounds.width : bounds.height
            if let new = AreaDivider.ratio(at: horizontal ? location.x : location.y, length: length) { onResize(new) }
        }
    }
}
