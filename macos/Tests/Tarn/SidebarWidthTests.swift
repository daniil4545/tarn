import AppKit
import SwiftUI
import Testing
@testable import Ghostty

@MainActor
@Suite
struct SidebarWidthTests {
    @Test(arguments: [
        (0.0, 120.0), (119.4, 120.0), (120.0, 120.0), (200.4, 200.0), (400.0, 400.0),
        (400.6, 400.0), (5000.0, 400.0), (-30.0, 120.0), (.nan, 200.0), (.infinity, 200.0), (-.infinity, 200.0),
    ])
    func widthStaysInRangeAndNeverCollapses(input: Double, expected: Double) {
        #expect(Sidebar.clampedWidth(input) == expected)
    }

    /// A plain AppKit view beside the sidebar, standing for the terminal view that takes clicks.
    private struct Probe: NSViewRepresentable {
        var onMake: (NSView) -> Void = { _ in }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            onMake(view)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    /// The widths a resize drag moves.
    @Test func dragMovesTheDrawnWidthAndNotTheLayoutWidth() {
        let idle = Sidebar.widths(isCollapsed: false, stored: 200, drag: nil)
        #expect(idle.layout == 200 && idle.shown == 200)

        let wider = Sidebar.widths(isCollapsed: false, stored: 200, drag: 320)
        #expect(wider.layout == 200 && wider.shown == 320)

        let outOfRange = Sidebar.widths(isCollapsed: false, stored: 200, drag: 9000)
        #expect(outOfRange.layout == 200 && outOfRange.shown == 400)

        let rail = Sidebar.widths(isCollapsed: true, stored: 200, drag: 320)
        #expect(rail.layout == Sidebar.collapsedWidth && rail.shown == Sidebar.collapsedWidth)
    }

    /// The T-151 live resize: while the sidebar is dragged to another width, the view beside
    /// it keeps its place and size (a moved terminal is a pty resize per frame), and a wider
    /// sidebar lies over it instead.
    @Test func terminalKeepsItsFrameWhileTheSidebarIsDragged() async throws {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Sidebar.collapsedKey)
        defaults.removeObject(forKey: Sidebar.widthKey)
        let ghostty = Ghostty.App()

        var frames: [CGRect] = []
        var wideHit = "none"
        let drags: [Double?] = [nil, 320, 130]
        for drag in drags {
            var probe: NSView?
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: SidebarLayout(model: SidebarModel(), ghostty: ghostty, dragWidth: drag) {
                Probe { probe = $0 }
            })
            window.contentView = host
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(200))
            let view = try #require(probe)
            frames.append(view.convert(view.bounds, to: host))

            if drag == 320 {
                wideHit = await hits(at: [250], host: host, window: window)[250] ?? "none"
            }
            window.close()
        }

        #expect(abs(frames[0].minX - (Sidebar.defaultWidth + Sidebar.dividerWidth)) < 0.5)
        #expect(frames[1] == frames[0], "wider drag moved the terminal: \(frames[1])")
        #expect(frames[2] == frames[0], "narrower drag moved the terminal: \(frames[2])")
        #expect(wideHit != "NSView", "the wider sidebar must lie over the terminal, hit: \(wideHit)")
    }

    /// Where a left click at `x` lands: the AppKit view that gets it. Hit testing of the
    /// rows reads the event being sent, so the test asks from inside a posted mouse event.
    private func hits(at xs: [CGFloat], host: NSHostingView<some View>, window: NSWindow) async -> [CGFloat: String] {
        var result: [CGFloat: String] = [:]
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            for x in xs {
                let hit = host.hitTest(NSPoint(x: x, y: 300))
                result[x] = hit.map { String(describing: type(of: $0)) } ?? "nil"
            }
            return nil
        }
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 100, y: 300), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
        NSApp.postEvent(event, atStart: false)
        for _ in 0..<20 where result.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        if let monitor { NSEvent.removeMonitor(monitor) }
        return result
    }

    /// The grab zone straddles the edge and lies above both the rows under it and the
    /// terminal view beside it.
    @Test func edgeGrabZoneBeatsTheRowsAndTheTerminalNextToIt() async throws {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Sidebar.collapsedKey)
        defaults.removeObject(forKey: Sidebar.widthKey)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: SidebarLayout(model: SidebarModel(), ghostty: Ghostty.App()) { Probe() })
        window.contentView = host
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(200))

        let edge = Sidebar.defaultWidth + Sidebar.dividerWidth / 2
        let half = Double(Sidebar.edgeGrabWidth) / 2
        let inside = edge - half + 2
        let outside = edge + half - 2
        let result = await hits(at: [edge - half - 6, inside, outside, edge + half + 6], host: host, window: window)
        window.close()

        #expect(result[edge - half - 6] == "InteractionView", "left of the zone the rows take the click")
        #expect(result[inside].map { !$0.contains("InteractionView") } == true, "over the sidebar: \(String(describing: result[inside]))")
        #expect(result[outside].map { $0.contains("NSHostingView") } == true, "over the terminal: \(String(describing: result[outside]))")
        #expect(result[edge + half + 6] == "NSView", "right of the zone the terminal takes the click")
    }
}
