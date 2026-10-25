import AppKit

/// Windows the registry raises itself to make a native move (`move_tab` acts on the selected tab).
/// The key notifications they cause are not the user's choice: they must neither unfold a
/// folded workspace nor change where the next new tab goes.
struct KeyHops {
    private var windows = Set<ObjectIdentifier>()

    mutating func mark(_ window: NSWindow) {
        windows.insert(ObjectIdentifier(window))
    }

    func contains(_ window: NSWindow) -> Bool {
        windows.contains(ObjectIdentifier(window))
    }

    mutating func clear() {
        windows = []
    }
}
