import Foundation

extension Notification.Name {
    /// The viewer zoom changed; every viewer pane takes the new value.
    static let tarnViewerZoomDidChange = Notification.Name("TarnViewerZoomDidChange")
}

/// The zoom of the viewer panes. The terminal's font size keys (Cmd+=, Cmd+-, Cmd+0 by default)
/// step it while a viewer holds the keyboard. One value for every pane, kept across launches.
enum ViewerZoom {
    /// The stops of a step, as Safari has them.
    static let steps: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    static let key = "TarnViewerZoom"

    static func current(in defaults: UserDefaults = .standard) -> Double {
        let value = defaults.double(forKey: key)
        return value > 0 ? value : 1
    }

    /// The next stop up (`by` 1) or down (`by` -1) from `zoom`; the last stop stays.
    static func step(_ zoom: Double, by direction: Int) -> Double {
        if direction > 0 { return steps.first { $0 > zoom + 0.001 } ?? steps[steps.count - 1] }
        return steps.last { $0 < zoom - 0.001 } ?? steps[0]
    }

    /// Steps the zoom (`by` 0 resets it), saves it and tells the panes.
    static func change(by direction: Int, in defaults: UserDefaults = .standard) {
        let zoom = direction == 0 ? 1 : step(current(in: defaults), by: direction)
        defaults.set(zoom, forKey: key)
        NotificationCenter.default.post(name: .tarnViewerZoomDidChange, object: nil)
    }
}
