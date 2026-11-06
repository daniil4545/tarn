# Modules, companions and settings

Canon for the switchable features of tarn (issue #34, T-205; companions T-364), the settings window and its option file. Built, except the hub.

## 1. Terms

| Term | Meaning |
| --- | --- |
| Module | a standalone tool on top of Ghostty with one switch and its own settings: Sidebar, File viewer |
| Setting | an option of tarn that is not a module: Permission card, Notifications |
| Companion | a module drawn beside the windows, a tool for one task; tab kind (the viewer, state in its tab) or global kind (the sidebar, the hub, one shared model) |
| Stored / effective state | the switch in UserDefaults / stored on and every module it needs effectively on |

The window is central: a terminal pane, with or without an agent. With the hub (T-373) Settings will name Permission card and Notifications as settings; keys and behavior stay.

## 2. Decided by the user

2026-10-27 (modules): Sidebar, File viewer, Permission card, Notifications are switchable; several viewers around the terminal are part of the file viewer. Only Permission card needs another module (Sidebar). A switch applies at once, no restart. An off module shows no UI and does not react to events; light observers (socket, registry) may run. State lives in UserDefaults. Claude Code has one agent line in Modules, no module gated by version; Codex, pi, OpenCode come when supported. `docs/spec.md` principle 1 allows these four to be switched off; features outside its section 1 are still cut. Groups have no switch (2026-10-29, T-300).

2026-10-31 and 2026-11-02 (companions): no separate agent window kind; two companion kinds; a global companion goes with the user to the next tab; several companions at once is normal, the last opened stands rightmost; agents may open, show and close companions but focus never moves and typing never stops; the permission card and the hub answer requests by the same rules under one setting; few rules now, add from use. The hub (a pane right of the windows, global across tabs, epic T-363) and the per-tab-group state model (T-427) are deferred past 1.4.0 (2026-11-03); the companion form of current modules in code (T-374) and the Settings renaming (T-373) move with the hub.

## 3. Rules

1. Off keeps state: viewer tabs, unsaved edits and areas stay in memory and restore data; on again draws them as they were.
2. One read path: every path that draws a module or creates its objects (commands, clicks, socket, restore, undo, reopen, detach, drop) reads the effective state at that moment.
3. Off gives the agent its own behavior back where tarn replaces it (permission dialog, terminal notifications).
4. Owners observe `UserDefaults.didChangeNotification`, compare the effective set with the last and act on the difference; the writer does not matter.
5. A key with a wrong type counts as on and is logged (`os_log`, category `settings`); a failed agent check shows its hint; nothing crashes.
6. Companion toggle: a button or shortcut; the user's toggle gives it the keyboard, closing returns it to the window (Cmd+B; VS Code toggles). Only the user moves focus (R4 invariant). One setting, "tarn answers requests", covers the card and the hub (off: Claude Code shows its own prompt).
7. Defaults, not rules yet: the sidebar left, other companions right; each keeps its keys; viewer width by split ratio; sidebar restored, viewers not.

| Module | Key | Needs | Off: what the user sees |
| --- | --- | --- | --- |
| Sidebar | `TarnTabStyle`: `sidebar` on, `top` off | - | native tab bar at the top with agent marks and the group name (only with two or more groups) |
| File viewer | `TarnFileViewer` | - | see `docs/spec/viewer.md` |
| Permission card | `TarnModule.permissionCard` | Sidebar | card has no Allow, Deny or answers; every `PermissionRequest` gets an empty reply at once, so Claude Code shows its own dialog; waiting hooks are released on switch-off |
| Notifications | `TarnModule.notifications` | - | no new banners; Cmd+U does nothing and its item is hidden; `tarn notify` answers "notifications are off in Settings"; OSC 9 and 777 are no longer suppressed |

All default on. With Sidebar off, Permission card keeps its stored value, greys out with "needs Sidebar" and behaves as off. Menu items (Toggle File Viewer, Jump to Waiting Session) are hidden by walking `NSApp.mainMenu`, so no Ghostty file needs a hook. Launch arguments (`-TarnTabStyle top`, `-TarnModule.notifications NO`) win without writing; the bench uses them.

Companion capabilities: expand to the whole tab (own state, not Ghostty's split zoom): viewer, hub; shown by an agent: viewer by `tarn open`; answers requests: hub, sidebar card. A companion's document states: task, kind and where state lives, content and actions, capabilities, off and cost, prior art. Open for the hub spec: state owner for detached tabs and the quick terminal; hub in each tab's layout; expand key; Esc order; whether `tarn open` shows a hidden viewer.

Prior art: Tellurion `26620ed` (AGPL, behavior only): one enum of features, a UserDefaults Bool each, one `isOn` guard at the point of use, teardown on switch-off; Stats `69efd1c` (MIT): `enable()` and `disable()` per module. "Needs X" is ours.

## 4. Settings window

Cmd+, opens one window (640 by 400, Escape and Cmd+W close) with sections Modules (first), Appearance, Terminal, Windows, Help. Each module's options sit under its switch, visible but disabled when it is off; Row size is under Sidebar. The Agents line shows Claude Code with its version and three checks run off the main thread when the pane opens, no network: found (`claude --version` from `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.claude/local`, else `$SHELL -l -i -c` killed after 5 s; the version is the line `N.N.N (Claude Code)`), plugin (`tarn@tarn` under `plugins` in `~/.claude/plugins/installed_plugins.json`), events (the registry got a hook event since start); each failure shows a hint.

Ghostty options (22 in the catalog `GhosttyOption.all`: toggle, choice, theme, number, slider, text) are written to `~/.config/tarn/ghostty.conf` (or under an absolute `$XDG_CONFIG_HOME`), which loads after the user's config and its includes, before finalize; a scalar's last line wins, so tarn beats the user's file. A launch with `-e` skips it. The user's own files are never edited.

- A control change always writes its line, even equal to the default; only Reset removes it, so the user's own value never resurfaces. Hand-written lines and comments survive. A number out of range is reported in the row and not written. A failed write keeps the old file and does not reload. A symlinked file stays a symlink. Values with line breaks are rejected.
- A row shows the file value if the control can show it, else a raw read-only text with Reset (`undo-timeout = 7s`), else the effective value; unreadable options (`theme`, `font-family`, `window-padding-x`) say "from Ghostty config". A set option shows "set in tarn" with Reset and says when it applies (live, new windows, restart). A rejected line after reload opens Ghostty's configuration errors window.
- `macos-titlebar-style` offers transparent, native and hidden (`tabs` removed on purpose). The theme row lists 8 base themes (default, Catppuccin, Atom One, Gruvbox, Dracula) with samples, then every installed theme with a filter; one theme, no light and dark pair.
-
