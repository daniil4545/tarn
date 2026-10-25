import Foundation

/// The viewers of a tab as they were when it closed: the layout (ids and ratios) and the open
/// files of every viewer. A tombstone keeps it so an undo of the tab brings the viewers back
/// (`docs/plans/s3-windows-contracts.md` section 7). Unsaved edits are not part of it: a close
/// settles them first (`ViewerClose`).
struct ViewerSnapshot {
    struct Viewer {
        let id: UUID
        let root: String
        let tabs: [ViewerTab]
        let active: Int
    }

    /// `AreaTree` as JSON.
    let layout: Data
    let viewers: [Viewer]
}
