# Windows, groups, sidebar and layout

Canon for window, tab group, workspace, sidebar and viewer-layout behavior (R3, R10, R20, R21 of `docs/spec.md`); built. The browser demo `demo/` follows it. A rule that names a source ("Warp", "Ghostty") follows that project's behavior. Test comments name rules and scenarios of this file (`spec: ... S45`, `G5`, `D1`).

## 1. Terms and model

| Term | Meaning | Owner |
| --- | --- | --- |
| window | a macOS window of tarn | Ghostty (`TerminalController`) |
| group | an optional named set of tabs in the sidebar; a group with a project folder is a workspace | tarn |
| tab | one sidebar row: one layout of panes | Ghostty native tab |
| terminal block | all terminal splits of a tab, one Ghostty split tree | Ghostty |
| viewer | a file pane beside the terminal block | tarn |

A window has 0 or more groups and tabs; a tab is in 0 or 1 group. Membership is a table `tab -> group` that only explicit actions write. Ghostty keeps tab order; our code asks for a `move_tab` only for a user's sidebar command, and moves a whole group in one native pass (user decision 2026-10-29, T-308: `move_tab` per tab froze the app for 1-2 s). A group lives while it has a tab.

Sidebar drawing (user decision 2026-10-28): walk the native tab order; the first tab of a group draws its header and all tabs of the group, indented; a later tab of a drawn group is skipped; an ungrouped tab is a row with no header and no indent. Groups stand in the order of their first tab. Cmd+N is Ghostty's `goto_tab:N`; a row shows the shortcut of its native index. Row N and Cmd+N agree while each group is one run of the native order; the order can split a group after `window-new-tab-position = end` (accepted, Q1), a user's `move_tab` key, an undo whose neighbours moved, or a native drag with tabs at the top. Nothing heals it.

## 2. Decided by the user

- D1 (2026-10-25, changed 2026-10-28). A new window starts with one ungrouped tab, no header (G1). Older snapshots: a "~" with no folder or with the home folder loads as ungrouped tabs (G13); "No project" and "Default" stay plain groups.
- D2. A new tab opens in the current group (M1). D3. Creating a workspace asks for a folder; its name is the folder's last component; a folder another workspace of the window holds selects that workspace.
- D5. A group shows its header always, even alone; its rows are indented. D6. Groups are collapsible, several open at once, reordered by drag; collapsed shows the tab count and the most urgent agent state.
- D7. Cmd+W closes the focused pane, on the last pane the tab, on the last tab the window, as in Ghostty; Cmd+Z within 5 s (`undo-timeout`) brings it back. D12. Closing the last tab of a group closes the group; undo brings the tab back to its group (recreated when gone) or ungrouped.
- D8. Terminals form one Ghostty split tree; viewers sit beside it; Ghostty's split keys move across both. D9. Ghostty first: windows, tabs, splits, undo, restore and menus are Ghostty's; tarn adds the group layer and the viewer.
- D10. Each window has its own groups; Cmd+N opens a window with one ungrouped tab. D11. No folder rule: a tab goes where it was opened; an agent's tab goes to the group of the agent's own tab.
- D13. A group is plain: rename, delete, reorder; delete leaves its tabs ungrouped where they stand, or closes them with a checkbox; the only group can go too (G7).
- D14. Tabs at the top: a flat native tab bar, no groups and no agent state there; groups show again with the sidebar. D15. A new tab starts in the focused tab's folder (`window-inherit-working-directory`). D17. No tab pins. D16. Grab handle dots are brighter than Ghostty's (0.6 near, 1.0 on hover).
- D18. Settings writes Ghostty options to `~/.config/tarn/ghostty.conf`, loaded after the user's config; the user's file is never edited (`docs/spec/modules.md`).

## 3. Membership and groups

Source of the model: Warp "Move to group", "Remove from group", docs.warp.dev/terminal/windows/tabs; user decisions 2026-10-28 ("order is not worth rebuilding the system for: do the simple thing, no crutches", "putting a tab into a group is explicit"). Never: a tab changes group by itself (folder, agent, `cd`, native drag); a tab moves between windows by our code (T-142).

- M1. A new tab takes the group of the tab it was opened from: Cmd+T, New Tab menu, native "+", the sidebar New Tab button, the "+" of a header. It acts only when the new window is in the native tab group of its source. Every other new tab is ungrouped: first tab of a window, a tab dragged out of a window of two or more tabs, AppleScript, Services, App Intents, dock drops, New Tab while Settings is key, redo of a closed tab.
- M2. Membership changes only by a sidebar command: drag a row onto a group or below all rows, "Move to <group>", "Remove from group", "Delete group...". Group commands (delete, rename, move) have no undo.
- M3. A native reorder (tabs at the top, `move_tab` keys) changes order only.
- M4. Merge All Windows keeps the group of every tab: the other set's groups join whole, its ungrouped tabs stay ungrouped; the last tab of a window dropped into another window is the same merge. Two workspaces on one folder after a merge are accepted.
- G1. A group is optional (Warp). G2. Shift+Cmd+T, the header button and "+ New group" ask for a Group (name) or a Workspace (folder, macOS folder panel). Source: Warp, Claude Code desktop.
- G3. The "+" of a header opens a tab from the group's last tab (`newTab(from:)`), so it stands at the group's end with `window-new-tab-position = current`; a workspace passes its folder as working directory, a plain group inherits from that tab. G4. Cmd+T and Cmd+D are Ghostty's, with Ghostty's folder inheritance.
- G5. Sidebar commands, one `move_tab` each at most: drag a row to a slot (a gap between rows of one block, a block end, or the tail below all rows = ungrouped); "Move to" (after the group's last tab); "Remove from group" (after the group's last tab, none when last); drag a header (one per tab). The move keeps the row where it is drawn. Prior art: searched Warp docs, tmux, WezTerm for membership over a native order without a move; none has it, this is ours.
- G6. The last tab leaving a group removes the group. G7. "Delete group..." has "Also close its N tabs", unchecked: tabs become ungrouped in place with no move; checked: one confirmation and the undo that closing gives (Warp "Ungroup tabs").
- G8. A new group's first tab opens from the last tab of the window, so the group stands at the bottom and splits no group; a workspace tab starts in its folder, a plain group's tab inherits from the selected tab.
- G9. The agent scope (`tarn ls`, `new`, `run`, `wait`, `read`, `close`) is the caller's group, for an ungrouped caller its own tab; outside it exit 4 (Tellurion, cmux, behavior only; `docs/spec/agent-cli.md`).
- G10. A workspace folder is fixed at creation; a plain group never gets one. G12. With tabs at the top a grouped tab carries its group name after the title (only when the window has two or more groups); the window subtitle names the selected tab's group. G13. Restore: an ungrouped tab is in no `tabKeys`; an older build reading a new snapshot puts ungrouped tabs into its target.
- Groups are always on (no switch, T-300). Fallback: an unforeseen state is logged `workspace: <reason>` and the tab is ungrouped.

Scenario labels S1-S65 stay as test tags (`spec: ... S45`); the rules above are the behavior. Facts only the labels carry: S43, S61, S62 each make one `move_tab` and rows match Cmd+1..9; S44-S46 Cmd+Z of a close restores a removed group; S55 with `window-new-tab-position = end` Cmd+T lands at the group end with its shortcut out of sequence (accepted).

Limits: never moves a tab between windows; never a `move_tab` the user's action did not cause; never changes a group because of a folder, agent, `cd` or native reorder; never changes the start folder of Cmd+T or Cmd+D; never writes the user's Ghostty config; never lets an agent command leave its scope.

## 4. Sidebar

The sidebar replaces the native tab bar (origin: PR #14562 of ghostty-org/ghostty, `THIRD_PARTY.md`). Frozen look and drag (user decisions 2026-10-29 and 2026-11-02, `.claude/CLAUDE.md`).

- A row shows the agent state; in a split tab the most urgent pane's state, with that pane's title, folder and agent name. A header shows the worst state of its tabs (permission, then working, then unseen done); folded: tab count and worst state dot. Rows: close on hover, tab color dot, agent logo, title, state dot, shortcut. Groups are blocks with their own background, tabs are cards (R20); the collapsed rail shows icons only.
- Width 120 to 400 (default 200), collapsed 40, stored once a drag ends. The drag does not resize the terminal: the sidebar lies over it and the terminal resizes once, at mouse release (no SIGWINCH per frame). The drag clamps at both ends and never folds; only the button folds. The grab zone is a 14 pt divider, 10 pt over the sidebar and 3 pt over the terminal, so the terminal's first column still takes a click.
- Drag and drop (R20): over a tab the rows part (halves, as iTerm2); over a header nothing changes; the strip between blocks ungroups; leaving the sidebar closes the gap. A tab dropped on the upper half lands before the row, on the lower before the next row or at the group end. The dragged row or block lifts and opens a gap at its slot; no line. A group drops between groups or ungrouped tabs, never inside another. A payload from another window is refused. A tab drag that nobody accepts and ends outside every window opens a new window.
- Card: hover on an agent row for 0.5 s or a force click opens one popover (title, group, folder, state, elapsed time; for a request its text and buttons while the hook waits). After an answer it stays closed until the pointer leaves the row.
- Titles: a shell path title becomes the full working directory with `~`, except while `ssh` leads the foreground group (Ghostty drops the remote OSC 7): the remote title stays and no folder shows. Under an agent, a shell title becomes the agent's name; an own title loses its leading spinner mark.
- Colors (T-151): sidebar, viewer and divider take colors from the terminal theme (surface = background plus 6% of text; muted text 38% toward background; accent = first of blue, bright blue, cyan, magenta with contrast 3:1, else text). The four state colors stay in every theme; with `window-theme` system, light or dark the views use system colors.
- Tabs at the top (Sidebar module off): the native bar shows the agent mark in each tab; with two or more groups the order is title, group name, state dot (user decision 2026-10-27; no insertion point).
- Detection latency: up to 2 s on a visible window; hidden windows refresh on notifications only.

## 5. Drop zones and viewer layout

A tab holds any number of viewers around the terminal block (one leaf of the layout). While a file tab, a viewer or a terminal is dragged, a 3 pt accent line shows the new pane's border (user decision 2026-10-25, Rectangle-style); a refusal shows a gray plate with the reason. Zones, first to last:

| Pointer | Result |
| --- | --- |
| corner of the tab area, 48 pt | split across that corner: the quarter if the area is already split on that axis, else the nearest half |
| 24 pt strip at an edge of the tab area | that half of the whole area |
| viewer tab bar (32 pt) or middle box (15%) | the file or viewer goes into that viewer |
| elsewhere in a pane | half of that pane on the nearest edge (Ghostty `TerminalSplitDropZone`) |
| over the dragged pane | red, refused ("Drop on another pane") |

Panes only split in two; no thirds. A lone terminal dropped at a viewer edge moves the whole block; split terminals have no area zones (the overlay is out of the layout while one drags, T-178, T-328): they move among themselves by Ghostty's zones and a drop over a viewer does nothing. A file tab moves with its edits (refused if both viewers hold different edited copies); a tree row only opens the file; an emptied source viewer closes; a viewer dropped outside every window opens in a new window at the drop point.

- The first open puts a viewer right of the block (60% block); later opens use the viewer with the keyboard, else the last used. Split from a viewer opens the active file in a new viewer on the chosen side with half the room; a failed open discards the new viewer. Closing the last file tab closes the viewer; a close with files registers an undo (viewer back beside its old neighbour, tabs reopened); a moved viewer has no undo. Viewers are not restored after a relaunch.
- Each viewer has a three-dot grip on top that drags the whole viewer; it follows `drag-handle` (auto: top fifth). Divider grab zone 14 pt (3.5 before the line, 10.5 after) over both panes, left button and pointer movement only; double click equalizes. Terminal splits keep Ghostty's 7 pt.
- Move Divider and Equalize Splits work from a viewer (10 pt steps); split zoom does nothing there (2026-10-26).
- Rejected: viewers inside the terminal tree (its leaves must be `SurfaceView`). A drop that would lose focus is refused. Prior art: cmux `SessionPersistence.swift` (GPL, structure only) shaped the versioned snapshot; no project groups native tabs into named workspaces.
