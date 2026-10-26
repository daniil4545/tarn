import AppKit
import Testing
@testable import Ghostty

/// The viewer zoom: steps, ends of the range, reset and the saved value (`docs/specs/viewer-pane.md`).
@Suite
struct ViewerZoomTests {
    @Test(arguments: [
        (1.0, 1, 1.1), (1.0, -1, 0.9), (3.0, 1, 3.0), (0.5, -1, 0.5),
        // A value between the stops, as an older build or a hand edit leaves it, goes to a stop.
        (1.05, 1, 1.1), (1.05, -1, 1.0),
    ])
    func stepsGoToTheNextStop(zoom: Double, direction: Int, expected: Double) {
        #expect(ViewerZoom.step(zoom, by: direction) == expected)
    }

    private static let cmd = NSEvent.ModifierFlags.command.rawValue
    private static let shift = NSEvent.ModifierFlags.shift.rawValue
    private static let option = NSEvent.ModifierFlags.option.rawValue

    @Test(arguments: [
        ("=", cmd, true), ("=", cmd | shift, false), ("=", cmd | option, false), ("-", cmd, false), ("=", 0, false),
    ])
    func cmdEqualsZoomsIn(characters: String, flags: UInt, expected: Bool) {
        #expect(ViewerWebView.isZoomIn(characters: characters, flags: NSEvent.ModifierFlags(rawValue: flags)) == expected)
    }

    /// On the main actor: `change` posts the notification that open panes take there.
    @Test @MainActor func changeSavesAndResetGoesBackToOne() throws {
        let suite = "tarn.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ViewerZoom.current(in: defaults) == 1)
        ViewerZoom.change(by: 1, in: defaults)
        ViewerZoom.change(by: 1, in: defaults)
        #expect(ViewerZoom.current(in: defaults) == 1.25)
        ViewerZoom.change(by: 0, in: defaults)
        #expect(ViewerZoom.current(in: defaults) == 1)
    }
}
