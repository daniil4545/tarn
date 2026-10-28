import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// The grab strip over the divider of an area split: its place, what a drag means, and that it
/// takes the click above the AppKit views of the panes beside it.
@MainActor
@Suite(.serialized)
struct AreaSplitTests {
    // MARK: Math

    struct Line: Sendable {
        let ratio: Double
        let length: Double
        let expected: Double
    }

    static let lines: [Line] = [
        Line(ratio: 0.5, length: 900, expected: 449),
        Line(ratio: 0.6, length: 1000, expected: 599),
        Line(ratio: 0.25, length: 1000, expected: 249),
        Line(ratio: 0.333, length: 1000, expected: 332),
        Line(ratio: 0.5, length: 601, expected: 300),
    ]

    @Test(arguments: lines)
    func lineSitsWhereSplitViewDrawsIt(line: Line) {
        let position = AreaDivider.linePosition(ratio: CGFloat(line.ratio), length: CGFloat(line.length))
        #expect(Double(position) == line.expected, "ratio \(line.ratio) of \(line.length): \(position)")
    }

    struct Drag: Sendable {
        let location: Double
        let expected: Double
    }

    static let drags: [Drag] = [
        Drag(location: 450, expected: 0.5),
        Drag(location: 0, expected: 10.0 / 900),
        Drag(location: -40, expected: 10.0 / 900),
        Drag(location: 9000, expected: 890.0 / 900),
        Drag(location: 890, expected: 890.0 / 900),
    ]

    @Test(arguments: drags)
    func dragRatioKeepsBothPanesAtLeastTenPoints(drag: Drag) {
        let ratio = AreaDivider.ratio(at: drag.location, length: 900) ?? .nan
        #expect(abs(ratio - drag.expected) < 1e-9, "location \(drag.location): \(ratio)")
    }

    @Test func aSplitTooShortToMoveGivesNoRatio() {
        #expect(AreaDivider.ratio(at: 10, length: 20) == nil)
        #expect(AreaDivider.ratio(at: 10, length: 5) == nil)
    }

    @Test func theStripLiesMostlyOverTheSecondPane() {
        let size = CGSize(width: 900, height: 600)
        #expect(AreaDivider.strip(direction: .horizontal, ratio: 0.5, size: size) == CGRect(x: 445.5, y: 0, width: 14, height: 600))
        #expect(AreaDivider.strip(direction: .vertical, ratio: 0.5, size: size) == CGRect(x: 0, y: 295.5, width: 900, height: 14))
    }

    @Test func theStripTakesTheLeftButtonAndThePointerOnly() {
        typealias Strip = AreaDividerStrip.StripView
        let taken: [NSEvent.EventType] = [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved, .cursorUpdate, .mouseEntered, .mouseExited,
        ]
        let passed: [NSEvent.EventType] = [.scrollWheel, .rightMouseDown, .otherMouseDown, .keyDown, .magnify, .swipe]
        for type in taken { #expect(Strip.claims(type), "\(type.rawValue)") }
        for type in passed { #expect(!Strip.claims(type), "\(type.rawValue)") }
        #expect(!Strip.claims(nil))
    }

    // MARK: Hit test

    /// A pane: an AppKit view with a scroll bar probe along its right edge, standing for the web
    /// view or the terminal view.
    private final class ProbePane: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            let scroller = ProbeScroller(frame: NSRect(x: frame.width - 15, y: 0, width: 15, height: frame.height))
            scroller.autoresizingMask = [.minXMargin, .height]
            addSubview(scroller)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }

    private final class ProbeScroller: NSView {}

    private struct Probe: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { ProbePane(frame: NSRect(x: 0, y: 0, width: 100, height: 100)) }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private func event(_ type: NSEvent.EventType, window: NSWindow) -> NSEvent {
        switch type {
        case .scrollWheel:
            let cgEvent = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 5, wheel2: 0, wheel3: 0)!
            return NSEvent(cgEvent: cgEvent)!
        default:
            return NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 100, y: 300), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
        }
    }

    /// The AppKit view that gets an event of `type` at each point. Hit testing reads the event being
    /// sent, so the test asks from inside a posted event.
    private func hits(at points: [NSPoint], type: NSEvent.EventType, direction: SplitViewDirection) async -> [NSPoint: String] {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: AreaSplit(
            direction: direction, ratio: 0.5, dividerColor: .gray, onResize: { _ in }, onEqualize: {},
            left: { Probe() }, right: { Probe() }))
        window.contentView = host
        window.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(200))

        var result: [NSPoint: String] = [:]
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .any) { posted in
            guard posted.type == type, result.isEmpty else { return posted }
            for point in points {
                result[point] = host.hitTest(point).map { String(describing: Swift.type(of: $0)) } ?? "nil"
            }
            return nil
        }
        NSApp.postEvent(event(type, window: window), atStart: false)
        for _ in 0 ..< 20 where result.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        if let monitor { NSEvent.removeMonitor(monitor) }
        window.close()
        return result
    }

    /// The line is at x 449. The strip runs from 445.5 to 459.5: a click on it is ours, a click on the
    /// scroll bar of the first pane 8 pt before the line goes to the scroll bar, and 12 pt after the
    /// line goes to the second pane.
    @Test func stripBeatsThePaneViewsButLeavesTheScrollBarAlone() async {
        let points = [441, 447, 457, 461].map { NSPoint(x: $0, y: 300) }
        let result = await hits(at: points, type: .leftMouseDown, direction: .horizontal)
        #expect(result[points[0]] == "ProbeScroller", "scroll bar of the first pane: \(String(describing: result[points[0]]))")
        #expect(result[points[1]] == "StripView", "edge of the first pane: \(String(describing: result[points[1]]))")
        #expect(result[points[2]] == "StripView", "on the strip: \(String(describing: result[points[2]]))")
        #expect(result[points[3]] == "ProbePane", "second pane: \(String(describing: result[points[3]]))")
    }

    /// A wheel over the strip, outside Ghostty's own 7 pt divider (which is SwiftUI and takes it as
    /// before), reaches the same view as a wheel over a pane far from the line, never the strip.
    @Test func theWheelGoesThroughTheStripAndThePointerStopsAtIt() async {
        let points = [NSPoint(x: 457, y: 300), NSPoint(x: 455, y: 300), NSPoint(x: 200, y: 300)]
        let wheel = await hits(at: points, type: .scrollWheel, direction: .horizontal)
        #expect(wheel[points[2]] != nil && wheel[points[2]] != "StripView")
        for point in points { #expect(wheel[point] == wheel[points[2]], "wheel at \(point.x): \(String(describing: wheel[point]))") }
        let moved = await hits(at: Array(points.prefix(2)), type: .mouseMoved, direction: .horizontal)
        for point in points.prefix(2) { #expect(moved[point] == "StripView", "pointer at \(point.x): \(String(describing: moved[point]))") }
    }

    /// The window is 600 pt high and hit test points count from the bottom; the strip runs from 295.5
    /// to 309.5 from the top.
    @Test func stripOfAStackedSplitLiesAcrossTheWidth() async {
        let fromTop: [CGFloat] = [291, 297, 307, 312]
        let points = fromTop.map { NSPoint(x: 450, y: 600 - $0) }
        let result = await hits(at: points, type: .leftMouseDown, direction: .vertical)
        #expect(result[points[0]] == "ProbePane", "above the strip: \(String(describing: result[points[0]]))")
        #expect(result[points[1]] == "StripView", "on the strip: \(String(describing: result[points[1]]))")
        #expect(result[points[2]] == "StripView", "on the strip: \(String(describing: result[points[2]]))")
        #expect(result[points[3]] == "ProbePane", "below the strip: \(String(describing: result[points[3]]))")
    }
}
