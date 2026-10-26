import AppKit

/// Where a window goes when it is dropped at a point on screen (a viewer or a tab dragged outside
/// every window). Pure math over the screens, so the case of two screens is tested without a second
/// display. Points and frames are in AppKit's global coordinates: origin at the bottom left of the
/// main screen, y up, other screens at any offset (negative to the left of or below the main one).
enum WindowPlacement {
    struct Screen: Equatable {
        /// The whole screen.
        let frame: CGRect
        /// The screen without the menu bar and the Dock.
        let visibleFrame: CGRect
    }

    /// The frame for a window of `size` whose top left corner is `point`. The screen under `point`
    /// decides (the nearest one when the point lies in a gap between screens); the window is moved
    /// and shrunk to fit that screen's visible area, so it never lands on another screen.
    static func frame(topLeft point: CGPoint, size: CGSize, screens: [Screen]) -> CGRect {
        guard let screen = screen(at: point, in: screens) else {
            return CGRect(x: point.x, y: point.y - size.height, width: size.width, height: size.height)
        }
        let area = screen.visibleFrame
        let width = min(size.width, area.width)
        let height = min(size.height, area.height)
        let x = min(max(point.x, area.minX), area.maxX - width)
        let top = min(max(point.y, area.minY + height), area.maxY)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    /// The screen that holds `point`, else the one whose frame is closest to it.
    static func screen(at point: CGPoint, in screens: [Screen]) -> Screen? {
        screens.first { $0.frame.contains(point) }
            ?? screens.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// Puts `window` with its top left corner at `point` on screen, on the screen that holds the
    /// point. `TerminalController.newWindow` (`Features/Terminal/TerminalController.swift`) shows the
    /// window on the next turn of the main queue and cascades it one turn later
    /// (`applyCascade`, `cascadeTopLeft`), which moves a frame set at once back beside the other
    /// windows; so the frame is set after both turns.
    @MainActor
    static func place(_ window: NSWindow, topLeft point: NSPoint) {
        DispatchQueue.main.async {
            DispatchQueue.main.async { [weak window] in
                guard let window, !window.styleMask.contains(.fullScreen) else { return }
                let screens = NSScreen.screens.map { Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
                window.setFrame(frame(topLeft: point, size: window.frame.size, screens: screens), display: true)
            }
        }
    }
}
