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

    // MARK: Hit test

    /// A plain AppKit view in a pane, standing for the web view or the terminal view.
    private struct Probe: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { NSView() }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    /// The AppKit view that gets a left click at each point. Hit testing of SwiftUI reads the event
    /// being sent, so the test asks from inside a posted mouse event.
    private func hits(at points: [NSPoint], direction: SplitViewDirection) async -> [NSPoint: String] {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.borderless], backing: .buffered,
            defer: false)
        let host = NSHostingView(rootView: AreaSplit(
            direction: direction, ratio: 0.5, dividerColor: .gray, onResize: { _ in }, onEqualize: {},
            left: { Probe() }, right: { Probe() }))
        window.contentView = host
        window.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(200))

        var result: [NSPoint: String] = [:]
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            for point in points {
                result[point] = host.hitTest(point).map { String(describing: type(of: $0)) } ?? "nil"
            }
            return nil
        }
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 100, y: 300), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1)!
        NSApp.postEvent(event, atStart: false)
        for _ in 0 ..< 20 where result.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        if let monitor { NSEvent.removeMonitor(monitor) }
        window.close()
        return result
    }

    /// The strip is 14 pt wide: a click 5 pt from the line (beyond Ghostty's own 3.5 pt) is ours, a
    /// click 12 pt from it goes to the pane.
    @Test func stripBeatsThePaneViewsBesideTheLine() async {
        let line: CGFloat = 449
        let points = [line - 12, line - 5, line + 5, line + 12].map { NSPoint(x: $0, y: 300) }
        let result = await hits(at: points, direction: .horizontal)
        #expect(result[points[0]] == "NSView", "left of the strip: \(String(describing: result[points[0]]))")
        #expect(result[points[1]].map { $0 != "NSView" } == true, "on the strip: \(String(describing: result[points[1]]))")
        #expect(result[points[2]].map { $0 != "NSView" } == true, "on the strip: \(String(describing: result[points[2]]))")
        #expect(result[points[3]] == "NSView", "right of the strip: \(String(describing: result[points[3]]))")
    }

    @Test func stripOfAStackedSplitLiesAcrossTheWidth() async {
        // The line is at the middle of the height; 2 pt of slack for the flipped origin.
        let points = [300 - 12, 300 - 5, 300 + 5, 300 + 12].map { NSPoint(x: 450, y: $0) }
        let result = await hits(at: points, direction: .vertical)
        #expect(result[points[0]] == "NSView", "above the strip: \(String(describing: result[points[0]]))")
        #expect(result[points[1]].map { $0 != "NSView" } == true, "on the strip: \(String(describing: result[points[1]]))")
        #expect(result[points[2]].map { $0 != "NSView" } == true, "on the strip: \(String(describing: result[points[2]]))")
        #expect(result[points[3]] == "NSView", "below the strip: \(String(describing: result[points[3]]))")
    }
}
