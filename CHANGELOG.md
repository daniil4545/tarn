# Changelog

Changes of tarn on top of Ghostty. Releases use `tarn-vX.Y.Z`; `vX.Y.Z` tags belong to upstream Ghostty.

## [Unreleased]

## [tarn-v1.3.0] - 2026-10-29

### Added

- New group (Shift+Cmd+T): choose Group with a name or Workspace with a typed project folder path; the folder must exist, accepts `~`, and supplies the workspace name.
- Delete group keeps its tabs ungrouped in place; check "Also close its N tabs" to close them instead, including the only group's tabs.
- Sidebar menus offer "Move to" and "Remove from group"; tabs and group headers can be dropped among ungrouped rows or below all rows.
- `tarn new -- <cmd...>` runs a command in a split below the caller; `--right` splits right, `--cwd` sets its folder, focus stays unchanged (#53).
- `tarn run` opens a split with the command typed for the user to review, edit and submit with Enter (#105).
- `tarn new` and `tarn run` accept `--tab [--title T]`: an unselected tab immediately after the caller, in its group; an ungrouped caller is refused with exit 1 before creation.
- `tarn wait <pane> [--timeout S] [--json]` reports `succeed`, `error` or `closed`; exits 0 on a reported end, 4 for no matching pane, 6 for unavailable exit status, 9 for timeout (#100).
- `tarn read <pane> [--lines N]` prints plain screen and scrollback text, default 80 lines; `tarn close <pane>` closes without confirmation or changing focus (#118).
- `tarn skill` prints usage guidance matched to the build; `tarn module ls [--json]` lists modules as on, off or unavailable (#119).
- Settings > Modules toggles Sidebar, File viewer, Permission card and Notifications, with integration version and status checks (#52); each module's options stand under its switch, and the Tabs and File Viewer pages are gone.
- Cmd+B opens the file viewer with its tree; with a file open it toggles the tree, with none it closes the viewer. Cmd+W closes the active file, on the last file the viewer.
- New group takes the workspace folder from the macOS folder panel (Choose...) or a typed path.

### Changed

- Groups are optional and membership is explicit: a new window starts with one ungrouped tab; starting a process, changing folders or reordering native tabs never regroups tabs.
- Grouped sidebar rows are indented; ungrouped rows have no header; restored groups keep their names; a window saved by 1.2.0 keeps its "Default" group, and Delete group without the box ungroups its tabs.
- Cmd+T inherits the source tab's group and Ghostty's folder and position; splits keep Ghostty's folder inheritance; a tab opened without a source group is ungrouped.
- A group's "+" opens from its last tab, using a workspace's fixed folder or a plain group's inherited folder; new groups start at the bottom; the sidebar New Tab button follows Cmd+T.
- Removing the last tab removes its group.
- `tarn ls [--json]` lists terminal panes in the caller's group, or only its own tab when ungrouped; other tabs are outside `read`, `wait` and `close` scope and return exit 4 (#50).
- `tarn ls` adds GROUP (`-` when ungrouped) and JSON `group` and `folder` (null when absent); the existing `workspace` key remains the group id.
- `tarn ls` drops HOST and JSON `host`; SSH panes show their remote title and process (#98, #101, #120).
- Sidebar tab drags show a visible dragged row and an opening gap between rows (#32).
- Sidebar groups are blocks with their own background and tabs are cards; a tab joins a group when dropped among its tabs and leaves it on the strip between groups (#149-#152).
- A group drags like a tab: its block lifts, other rows part to a gap, and it drops between groups or ungrouped tabs, never into a group (#154, #155).
- A group move reorders the native tabs in one pass, without visible renumbering or lag (#156).
- Updated the Ghostty base to v1.4.0 (#114).

### Fixed

- Undo restores a closed tab to its group, recreating the group if needed; ungrouped tabs stay ungrouped and viewers return with their tab.
- `hook.sh` returns within 100 ms when the app hangs: one detached timer instead of a polling loop (#124).
- `tarn wait` detects missing shell integration by Ghostty's configuration and shell rules, including `run` panes, without falsely reporting completion before the first prompt (#123).

## [tarn-v1.2.0] - 2026-10-26

### Added

- Shift+Cmd+T creates a workspace; Cmd+Z still reopens closed tabs.
- Viewer zoom with Cmd+=, Cmd+- and Cmd+0, shared across viewers and saved across launches.
- Viewer find with Cmd+F, Cmd+G and Shift+Cmd+G in rendered files and source.
- Toggle File Viewer button in the sidebar header.
- Wide sidebar rows show title, folder and time in session state; Settings > Tabs > Row size selects one line.

### Fixed

- Split navigation works with a viewer open, including at window edges.
- Tab, window, Move Divider and Equalize Splits shortcuts work while the viewer has focus.
- Questions answered in the terminal's own dialog leave the sidebar immediately.
- A split tab's sidebar title identifies the pane represented by its state dot.

## [tarn-v1.1.0] - 2026-10-26

### Fixed

- Cmd+click strips a sentence-ending period from a path unless that filename exists.
- Cmd+W no longer crashes through recursive sidebar and workspace refreshes.
- Workspace and tab menu actions work again.
- Sidebar and viewer dividers have a 14 pt grab area and resize cursor.
- Sidebar resizing stops at 400 pt; only the button collapses it.
- Detached viewers open at the drop position on the correct screen.
- Cmd+W closes Settings.
- Tab title updates read each session process once.

### Changed

- Pane drops show an accent line or a refusal reason; terminal-to-terminal drops keep Ghostty's highlight.
- Theme settings show seven base themes and a filterable full list; sidebar and viewer follow the terminal theme with `window-theme = auto` or `ghostty`.
- Sidebar resizing updates the terminal on release; hover and folding share animation timing.
- Help explains which terminal paths support Cmd+click: those containing a slash.

## [tarn-v1.0.0] - 2026-10-25

First release, ad-hoc signed and not notarized; see `docs/install.md`.

### Added

- File viewer with a file tree, tabs, rendered markdown and mermaid, highlighted source, editing with unsaved-change prompts and disk updates; Cmd+B toggles it.
- Restored per-window workspaces, undo for closed workspaces, terminal and viewer splits with draggable dividers and tab drops.
- Settings and Help for tab style, Ghostty options and shortcuts; tarn config at `~/.config/tarn/ghostty.conf`, existing Ghostty config read only.
- Static browser demo of the sidebar, sessions, workspaces, splits and viewer.
- Project notifications for permission, questions and failures, suppressing duplicate terminal notifications from live sessions.
- Cmd+U jumps to a waiting session; sessions never move focus themselves.
- `tarn open`, `tarn ls [--json]` and `tarn notify` for files, sessions and attention; exit 1 when tarn is unavailable.
- `Tarn.app`, bundle id `com.daniil4545.tarn`, own icon, installed beside Ghostty.
- `tarn.mk` checks, release zip with CLI and SHA-256 checksum, and benchmarks against the same upstream commit.
- `install.sh` installs or upgrades from the latest release; see `docs/install.md`.

### Changed

- Removed the updater; Debug settings under the former Ghostty bundle id are not migrated.

### Fixed

- Sidebar drops work below the last row, avoid flickering feedback and accidental workspace moves, and show no drop line for another window.

### Known limits

- Startup is about 17 ms (7%) slower than upstream, above the 5% target; idle CPU and memory meet it. See `docs/bench.md` for results and variation.

## [tarn-v0.0.1] - 2026-10-23

First source-built preview: sidebar and session state; viewer, CLI, notifications, app identity and benchmarks not yet included.

### Added

- Resizable vertical tab sidebar with shortcuts, close on hover, context menu, rename and collapsed icon strip.
- Detected sessions grouped by project git root with icons; same-named projects show their parent folder; tabs return below the divider when sessions exit.
- Plugin session state dots for working, permission, questions, done, unseen completion and errors.
- Permission and single-choice question cards reply through the waiting hook.

### Setup

Build with `macos/build.nu --configuration Debug --action build`, open `macos/build/Debug/Ghostty.app` and install the plugin from `<repo>/plugin`.

### Known limits

- Uses `Ghostty.app` and Ghostty's debug bundle id, sharing notifications and defaults.
- Only the primary integration reports state; other detected sessions have groups and icons only.
- Sessions inside tmux or SSH, or behind wrappers, are not detected.
- Permission state persists until an approved command ends.
