import SwiftUI

/// The numbers of an area divider: where Ghostty's `SplitView` draws its line, and what a drag at a
/// point means. Pure, so a test checks them.
enum AreaDivider {
    /// Width of the grab strip over a divider. Ghostty's own strip is 7 pt, 3.5 pt on each side of
    /// the line; the pane views beside the line take the clicks there, so it is hard to catch.
    static let hitWidth: CGFloat = 14
    /// The least size of a pane in a drag, as in `SplitView` (`minSize`).
    static let minSize: CGFloat = 10

    /// Where the line is along the split axis in a split of `length`: `SplitView.leftRect` and
    /// `splitterPoint` (`Features/Splits/SplitView.swift`) with whole-point increments.
    static func linePosition(ratio: CGFloat, length: CGFloat) -> CGFloat {
        let raw = length * ratio - 0.5
        return raw - raw.truncatingRemainder(dividingBy: 1)
    }

    /// The ratio a drag to `location` along the axis gives, as in `SplitView.dragGesture`. Nil when
    /// the split is too short to move.
    static func ratio(at location: CGFloat, length: CGFloat) -> CGFloat? {
        guard length > 2 * minSize else { return nil }
        return min(max(minSize, location), length - minSize) / length
    }
}

/// One split of the area: Ghostty's `SplitView` unchanged, with a wider transparent grab strip over
/// its divider. The strip lies above both panes (their AppKit views would take the clicks), shows the
/// resize cursor, changes the same ratio and equalizes on a double click, as the divider does.
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
                GeometryReader { geometry in
                    strip(in: geometry.size)
                }
            }
    }

    private func strip(in size: CGSize) -> some View {
        let horizontal = direction == .horizontal
        let length = horizontal ? size.width : size.height
        let line = AreaDivider.linePosition(ratio: ratio, length: length)
        return Color.clear
            .frame(width: horizontal ? AreaDivider.hitWidth : size.width,
                   height: horizontal ? size.height : AreaDivider.hitWidth)
            .contentShape(Rectangle())
            .position(x: horizontal ? line : size.width / 2, y: horizontal ? size.height / 2 : line)
            .gesture(DragGesture().onChanged { drag in
                let location = horizontal ? drag.location.x : drag.location.y
                if let new = AreaDivider.ratio(at: location, length: length) { onResize(new) }
            })
            .onTapGesture(count: 2) { onEqualize() }
            .backport.pointerStyle(horizontal ? .resizeLeftRight : .resizeUpDown)
            .onHover { isHovered in
                // macOS 15 and later use the pointer style above.
                if #available(macOS 15, *) { return }
                if isHovered {
                    (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .accessibilityHidden(true)
    }
}
