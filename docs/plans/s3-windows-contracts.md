# S3 contracts: workspace state, rules, failures

Companion of `docs/plans/s3-windows.md`. Workers A and C implement these rules; tests name them. Paths are under `macos/Sources/Features/Tarn/` unless noted.

## 1. What we write, what Ghostty writes (M1)

| Fact | Single writer | Notes |
| --- | --- | --- |
| order of tabs | Ghostty: `newTab`, `move_tab`, native drag, undo (`TerminalController.swift:424,1565,1050`) | we never call `removeWindow` or `addTabbedWindowSafely` for ordering |
| tab belongs to workspace | `WorkspaceRegistry` | the only thing we write |
| workspace names, fold, id | `WorkspaceRegistry` | |
| workspace order | derived from tab order | not stored |

A workspace is a contiguous run of the native tab order. The sidebar draws runs, top to bottom, so row N is native tab N and cmd+N (`onGotoTab`, `TerminalController.swift:1631`) lands on row N, folded or not. This holds by construction, not by repair.

## 2. Types and keys (M2, S3)

| Type | Fields | Key |
| --- | --- | --- |
| `Workspace` | `id: UUID`, `name`, `collapsed` | `id` |
| `WorkspaceSet` | `id: UUID` (one Ghostty window), `workspaces: [Workspace]` (unordered), `members: [TabKey: workspaceID]`, `revision: Int` | `id` |
| `TabKey` | `UUID` made by us per tab window, held in a weak window map | persisted in the snapshot |

No `ObjectIdentifier` keys. The registry holds `[WeakWindow: TabKey]`. The set lives in `WorkspaceRegistry` (singleton), not in a per-group object; it outlives restore, undo and merges.

## 3. Normalizing a foreign order change (M1)

`reconcile(group)` runs on `.terminalTabsDidChange` and on key change. It compares the native sequence with the last seen one.

1. A window with no `TabKey` is new: it is placed by section 4.
2. Gone windows leave `members`. A workspace left with no tab is removed (D12).
3. Find the mover: the one tab whose removal leaves the other tabs in their previous relative order. Ghostty moves one tab at a time (`move_tab`, drag, undo insert, new tab). The mover joins the workspace of its upper neighbour, or of its lower neighbour if first. Only `members` changes.
4. Still not contiguous (several changes at once, a merge): every tab outside the first run of its workspace joins the workspace of its upper neighbour.
5. Bump `revision`, post `.terminalTabsDidChange`, invalidate restorable state.

Tests: `ReconcileTests` (move down into another workspace, move to top, undo insert, native drag, two changes, cmd+N equals row N on each result).

## 4. Where a new tab goes (M3)

`target` is chosen in this order:

1. `pendingTarget`, set by the sidebar before it calls `newTab`: S3 the clicked header's workspace; S4 the workspace just created with a name (empty until its tab joins, the only moment a workspace has no tab).
2. `lastSelected`: workspace of the selected tab, updated on every key change of a window that has a `TabKey`. A new window has none, so Ghostty selecting it (`TerminalController.swift:493`) does not change `lastSelected`.

The new window joins `target`; the sidebar then moves it to the end of that run by `move_tab` (D2, answer Q1). A window created by cmd+N has no peers: it makes a new set with `Default` (D1, D10).

## 5. Reordering from the sidebar (M1)

Membership first, then one Ghostty action: `performAction("move_tab:<delta>", on: surface)` (`BaseTerminalController.swift:1046`, handled by `onMoveTab`). The handler needs the tab to be focused (`TerminalController.swift:1567`), so the move selects the tab, moves it and restores the selection. A workspace move is one `move_tab` per tab. No `reconcile` step writes order. If the selection hop flickers, fall back to the two calls `onMoveTab` makes (`:1619-1620`).

## 6. Sets across restore, undo, merge (M2)

| Event | Rule |
| --- | --- |
| restore | each window's coder holds `{setID, revision, table, tabKey}` (points 12-13). Same `setID` joins one set; the higher `revision` table wins; a missing `tabKey` makes a new one |
| undo of a tab | tombstone (section 7) puts it back in its workspace; a deleted workspace is recreated at its old place |
| undo of a window (S18) | the new group has no set yet: the tombstone of the closed window supplies set, names and fold; no empty `Default` is created |
| Merge All Windows | two sets in one group: the set of the first window wins; the loser's workspaces and members are appended whole (names kept) when the loser has no window left outside the group |
| one tab dragged to another window (S21) | the loser set still has windows: the tab joins the destination's `target` (section 4). Dropped outside every window: new window, new set `Default` (D10) |

## 7. Tombstone (M4)

Written on `NSWindow.willCloseNotification`, before `closeTabImmediately` removes the controller (`TerminalController.swift:730-761`): at that point surface UUIDs and `ViewerHost` are alive. Content: surface UUIDs, set snapshot, workspace id and index, run position, `AreaTree` snapshot with the open files of every viewer. Matching: a new window whose `surfaceTree` holds those UUIDs (`undoState` reuses the `SurfaceView`s, `:1028-1036`). Lifetime: `undoExpiration` (`BaseTerminalController.swift:112`), cleared on match. Why not a second action in `ExpiringUndoManager`: it would register after Ghostty's, sit on top of the stack and need a second cmd+Z; the user decides (plan Q11).

## 8. Failure rule (M8)

Any case the rules do not cover (snapshot not decodable, unknown `setID`, tab without membership, `move_tab` refused, tombstone not matched) ends the same way: log one line `workspace: <reason> window=<tabKey> set=<id>` (OSLog `tarn`, category `workspace`); the tab goes to `target`; a broken snapshot gives one set `Default` holding all the window's tabs. Never crash, never drop a tab, never leave a tab outside a workspace.

## 9. Persistence format

Second key `tarn.workspaces` in the window's `NSCoder`, JSON `{version: 1, setID, revision, tabKey, workspaces: [{id, name, collapsed, tabKeys ordered}]}`. Version unknown or decode error: section 8. The Ghostty `TerminalRestorableState` (version 7, `TerminalRestorable.swift:61`) is untouched.

## 10. Drag payloads

Private pasteboard types, no `Ghostty-Info.plist` entry: `com.daniil4545.tarn.tab`, `.workspace`, `.viewer` as `NSPasteboard.PasteboardType` on AppKit drag sources (the way `SurfaceDragSourceView` does, `Ghostty/Surface View/SurfaceDragSource.swift:82`) and `NSDraggingDestination` views. Terminal drags keep `.ghosttySurfaceId`. The area overlay answers `hitTest` only inside the corner and strip rects during a drag; elsewhere the drop falls to Ghostty's `onDrop` (`TerminalSplitTreeView.swift:108`), so the pane zones reuse `TerminalSplitDropZone.calculate` (`:205`).
