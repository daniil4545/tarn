# Changelog

Changes of tarn on top of Ghostty. Releases are tagged `tarn-vX.Y.Z`; the `vX.Y.Z` tags in this repository belong to upstream Ghostty.

## [Unreleased]

### Added

- Settings > Modules: switch Sidebar, File viewer, Workspaces, Permission card and Notifications on or off at once; a Claude Code line with its version and checks (#34).

### Changed

- A new window starts in the workspace "~" with the home folder instead of "No project", and its first tab starts there; saved workspaces keep their names.
- A tab dragged in the sidebar leaves the list, and the rows slide apart to a gap where it will land, as in Warp; no accent line for tabs.

## [tarn-v1.2.0] - 2026-10-26

### Added

- Shift+Cmd+T opens a new workspace; it no longer reopens a closed tab (Cmd+Z still does).
- Viewer zoom: Cmd+=, Cmd+- and Cmd+0 in a viewer pane, one zoom for every viewer, kept across launches.
- Find in the viewer: Cmd+F, Cmd+G and Shift+Cmd+G, in the rendered file and in the source.
- Toggle File Viewer button in the sidebar header.
- Wide sidebar rows: the tab title, then the folder and the minutes in the agent's state. Settings, Tabs, Row size switches to one line.

### Fixed

- With a viewer open, split terminals move among themselves again, also at the window edge.
- While a viewer has the keyboard, the tab and window keys work (Cmd+1 to Cmd+9, next and previous tab, and the rest), and so do Move Divider and Equalize Splits.
- A question answered in Claude Code's own dialog leaves the sidebar at once.
- A tab split into several terminals names, in its sidebar row, the pane its state dot speaks of.

## [tarn-v1.1.0] - 2026-10-26

### Fixed

- Cmd+click on a path that ends a sentence (`/tmp/a/plan.md.`) opens the file without the period, unless a file with the period in its name exists.
- Cmd+W no longer crashes tarn: closing a tab made the sidebar and the workspaces refresh each other until the stack ran out, which looked like the whole window closing.
- Workspace and tab menus work again: every item had an action its target did not handle, so Rename, Delete and the rest did nothing.
- The sidebar edge and the line between the terminal and a viewer are easy to grab: a 14 pt hit strip centered on the line, above both sides, with the resize cursor.
- Dragging the sidebar edge to its widest stays at 400 pt; only the button collapses the sidebar.
- A viewer dragged out of the window opens where it was dropped, on any screen, not on the first one.
- Cmd+W closes the Settings window.
- A tab title change reads each agent process once, not twice per tab for every tab.

### Changed

- Drop feedback: a 3 pt accent line where the pane goes, and a gray plate with the reason when the drop is refused. A terminal dropped on a terminal keeps Ghostty's own highlight.
- Settings, Theme: seven base themes on top (Catppuccin Latte and Mocha, Atom One Light and Dark, Gruvbox Light and Dark, Dracula), the full list with a filter below. While `window-theme` is `auto` or `ghostty`, the sidebar and the viewer take their colors from the terminal theme; with `system`, `light` or `dark` they keep the built-in colors.
- Resizing the sidebar resizes the terminal once, when the mouse is released. Hover and workspace folding animate with one duration and curve.
- Help lists which paths in terminal output open on Cmd+click: those with a slash.

## [tarn-v1.0.0] - 2026-10-25

First release. The build is ad-hoc signed and not notarized; see `docs/install.md`.

### Added

- File viewer: a pane beside the terminal with a files tree, file tabs, rendered markdown (with mermaid diagrams), a code view with highlighting, and a text editor with unsaved-edit questions. Cmd+B shows or hides it; it follows file changes on disk.
- Workspaces and layout: a set of workspaces per window in the sidebar, restored after a restart, with undo for a closed workspace. Terminals and viewers sit in one area tree; drop a tab on a pane edge to split, and drag the grips to resize.
- Settings window and Help: tab style and a short list of Ghostty options, plus a Help page with the keys in effect. Tarn options live in `~/.config/tarn/ghostty.conf`; your Ghostty config is read, never written.
- Demo: a static site (`demo/`) that shows the tarn window in a browser, with a scripted `claude` session, workspaces, splits and the viewer.
- Notifications: one banner per need ("Needs your permission", "Waiting for you", "Failed, see the session"), named by project. Terminal notifications from a tab with a live agent session are suppressed, so you get no duplicates.
- Jump: Cmd+U (Window, "Jump to Waiting Session") goes to the session that waits for you. Agents never move focus.
- `tarn` command inside tarn terminals: `tarn open <path>` opens a file in the viewer, `tarn ls [--json]` lists sessions, `tarn notify <text>` marks the session and notifies. It fails with `tarn: <text>` and exit code 1 when no tarn runs.
- App identity: `Tarn.app`, bundle id `com.daniil4545.tarn`, version 1.0.0, own icon. It installs next to Ghostty and shares its config files.
- `tarn.mk` with `check`, `release` and `bench`; the release is an ad-hoc signed zip with the `tarn` command inside and a `.sha256` file, `bench` compares it with upstream Ghostty built from the same commit (`docs/bench.md`).
- `install.sh`: one `curl ... | sh` command installs or upgrades from the latest release, see `docs/install.md`.

### Changed

- No updater: the menu item is gone and no feed is set. Sidebar settings saved by a Debug build under the old Ghostty bundle id are not carried over.

### Fixed

- Sidebar drag and drop: a workspace or tab can be dropped below the last row, the drop line no longer blinks over the gaps between rows, the only tab of a workspace dropped on it no longer moves the workspace to the end, and a drag from another window shows no line.

### Known limits

- Startup is about 17 ms (7%) slower than upstream Ghostty built from the same commit, over the +5% of `docs/spec.md` section 7: the first layout of the sidebar. Idle CPU and memory are within it; the `cat` result moves by about 6% between runs. Numbers in `docs/bench.md`.

## [tarn-v0.0.1] - 2026-10-23

First preview, built from source. The sidebar and Claude Code session state work; the rest of the first version (markdown panel, `tarn` CLI, notifications, app identity, benchmark) is not in yet.

### Added

- Vertical sidebar in place of the native tab bar: tabs of a window with their shortcuts, close on hover, right-click menu, rename, resizable width, collapse to an icon strip.
- Agent groups: a tab where `claude`, `codex` or `opencode` runs moves into the group of its project, keyed by the git root, with the agent's icon; it returns below the divider when the agent exits. Two projects with the same folder name show their parent folder.
- Claude Code session state through the `tarn` plugin: working, needs permission, asks a question, done, done but not seen, stopped with an error, as a colored dot.
- A card beside a tab answers a permission request or a single-choice question; the answer goes back through the waiting hook, so it reaches exactly that request.

### Setup

1. Build the app: `macos/build.nu --configuration Debug --action build`, then open `macos/build/Debug/Ghostty.app`.
2. Add the plugin: `claude plugin marketplace add <repo>/plugin`, then `claude plugin install tarn@tarn`.
3. Start `claude` in a tab of the app; the plugin does nothing outside tarn.

### Known limits

- The app still builds as `Ghostty.app` with Ghostty's debug bundle id, so it shares notifications and defaults with an installed Ghostty debug build.
- codex and opencode get a group and an icon but no state.
- Agents inside tmux or ssh, or behind a wrapper script, are not detected.
- After you approve a long command, the session shows "needs permission" until the command ends.
