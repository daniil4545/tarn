# Changelog

Changes of tarn on top of Ghostty. Releases are tagged `tarn-vX.Y.Z`; the `vX.Y.Z` tags in this repository belong to upstream Ghostty.

## [Unreleased]

### Fixed

- Sidebar drag and drop: a workspace or tab can be dropped below the last row, the drop line no longer blinks over the gaps between rows, the only tab of a workspace dropped on it no longer moves the workspace to the end, and a drag from another window shows no line.

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
