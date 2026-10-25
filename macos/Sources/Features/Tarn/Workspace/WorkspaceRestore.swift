import AppKit
import OSLog

/// Saves and reads a window's workspace table beside Ghostty's `TerminalRestorableState`,
/// under its own coder key, so Ghostty's state version stays as it is (C9).
enum WorkspaceRestore {
    static let key = "tarn.workspaces"

    private static let logger = Logger(subsystem: "tarn", category: "workspace")

    @MainActor
    static func encode(_ window: NSWindow, into coder: NSCoder) {
        guard let snapshot = WorkspaceRegistry.shared.snapshot(for: window) else { return }
        do {
            coder.encode(try snapshot.encoded() as NSData, forKey: key)
        } catch {
            logger.error("workspace: encode failed window=\(snapshot.tabKey, privacy: .public) set=\(snapshot.setID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    static func decode(_ coder: NSCoder, for window: NSWindow) {
        guard let snapshot = snapshot(from: coder.decodeObject(of: NSData.self, forKey: key) as Data?) else { return }
        WorkspaceRegistry.shared.restore(snapshot, for: window)
    }

    /// The snapshot in `data`, or nil with one logged line for data we cannot read. The window
    /// then restores as a new tab and lands in the `Default` of its group (section 8).
    static func snapshot(from data: Data?) -> WorkspaceSnapshot? {
        guard let data else { return nil }
        do {
            return try WorkspaceSnapshot.decode(data)
        } catch {
            logger.error("workspace: snapshot not decodable error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
