import Foundation

/// What a closed tab leaves behind so an undo can put it back where it was: its
/// workspace and place, the surfaces it held and its viewers.
struct WorkspaceTombstone {
    let closed: WorkspaceBook.ClosedTab
    /// Ids of the surfaces of the tab. Ghostty's undo reuses the `SurfaceView`s, so the
    /// reopened window holds the same ids (`TerminalController.swift:1028-1036`).
    let surfaces: Set<UUID>
    let viewers: ViewerSnapshot?
}

/// The undo closure holds the token, so a tombstone lives exactly as long as Ghostty keeps the
/// undo (`undoExpiration`, then it is dropped with the closure). No timer of our own.
final class TombstoneToken {
    let tombstone: WorkspaceTombstone

    init(_ tombstone: WorkspaceTombstone) {
        self.tombstone = tombstone
    }
}

/// Tombstones waiting for their undo. An undo arms its tombstone; the window that Ghostty's
/// undo creates next claims it by its surface ids.
@MainActor
final class TombstoneShelf {
    private var armed: [TombstoneToken] = []

    var armedCount: Int { armed.count }

    /// The undo of this tombstone ran: its window is about to appear.
    func arm(_ token: TombstoneToken) {
        armed.append(token)
    }

    /// The armed tombstone that shares the most surfaces with `surfaces`, removed from the
    /// shelf. Nil when none shares one.
    func claim(surfaces: Set<UUID>) -> WorkspaceTombstone? {
        let best = armed.enumerated()
            .map { ($0.offset, $0.element.tombstone.surfaces.intersection(surfaces).count) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }
        return best.map { armed.remove(at: $0.0).tombstone }
    }

    /// Drops what no window claimed once the undo has finished; returns how many.
    @discardableResult
    func settle() -> Int {
        defer { armed = [] }
        return armed.count
    }
}
