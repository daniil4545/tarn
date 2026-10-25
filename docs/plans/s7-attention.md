# Plan: S7 attention, notifications, jump and the `tarn` CLI

Status: draft for independent spec review, branch `s7-attention` from `main` 8205d36dd.
Canon: `docs/spec.md` sections 1 (R4, R8, principle 5), 2 (2.2, 2.4), 8, 10, 11, 12, 13 (S1-S3 rows); `docs/architecture.md` section 9.
User decisions (2026-10-25): full wave 1 in 1.0.0; jump key Cmd+U through a menu item; jump order per spec section 8 and 10; a click on a notification focuses that session.

## 1. Goal and scope

- Goal: the user learns once that a session needs them, jumps to it with one key, and agents ask for attention without moving focus.
- In: `tarn open|ls|notify` CLI inside the app bundle and on PATH in every surface; socket commands `ls` and `notify`; one notification per need through Ghostty's route; suppression of OSC 9/777 from surfaces with a live agent session; jump (Cmd+U) with its menu item; tests; docs.
- Out: `tarn hook` (the plugin keeps `hook.sh`; spec 2.3 names `tarn hook`, not part of this task), `path:line` in `tarn open`, session addressing by id, notification actions beyond Ghostty's "Show", sound settings, any change to `src/`.

## 2. Ghostty first: what is reused

| Need | Ghostty has | Use |
|---|---|---|
| Show a notification bound to a surface | `Ghostty.App.showDesktopNotification(_ surfaceView:title:body:requireFocus:)` `macos/Sources/Ghostty/Ghostty.App.swift:1630-1651` asks authorization, checks `.authorized`, then calls `SurfaceView.showUserNotification` | call it. It is `private static`; insertion point 21 drops `private` |
| Build and track the request | `SurfaceView.showUserNotification` `Ghostty/Surface View/SurfaceView_AppKit.swift:1776-1830`: `userInfo` `surface` and `requireFocus`, subtitle = surface title, identifier stored in `notificationIdentifiers`, removed after 3 s if focused, removed on focus (`focusDidChange`) and in `deinit` (`:434`) | untouched |
| Show only when not focused | `Ghostty.App.shouldPresentNotification` `Ghostty.App.swift:550-564`, wired in `AppDelegate.swift:970-976`: with `requireFocus` true it presents when `!window.isKeyWindow \|\| !surface.focused` | we pass `requireFocus: true`; our gate (section 4) also skips a focused surface, so no request is created for it |
| Click focuses the surface | `UNUserNotificationCenterDelegate.didReceive` `AppDelegate.swift:958-966` -> `Ghostty.App.handleUserNotification` `Ghostty.App.swift:2508-2524` -> `SurfaceView.handleUserNotification` `SurfaceView_AppKit.swift:1832-1839` (`makeKeyAndOrderFront`, `Ghostty.moveFocus`) | unchanged; works for our notifications because they carry the same `userInfo` |
| Notification category and "Show" action | `AppDelegate.swift:296-309` | unchanged |
| Terminal notification (OSC 9, 777) arrival | core action `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` `Ghostty.App.swift:653-654` -> `showDesktopNotification(app, target:, n:)` `:1609-1627` | one guard before the surface call (insertion point 21). `command_finished` (`:1716`) keeps its own path: the spec suppresses OSC 9/777 only |
| `tarn` on PATH inside surfaces | the core appends the directory of the running executable to `PATH` and sets `GHOSTTY_BIN_DIR`: `src/termio/Exec.zig:681-710` (`std.process.executablePath`, `env.put("GHOSTTY_BIN_DIR", exe_dir)`, appended when not yet in `PATH`). In the app bundle that directory is `Contents/MacOS`. The zsh and bash integrations append it again when feature `path` is on (`src/shell-integration/zsh/ghostty-integration:283-286`, `bash/ghostty.bash:83-86`) | the CLI file lives in `Contents/MacOS/tarn`; no code of ours touches `PATH`. The brief said "prepends"; the code appends, so a foreign `tarn` earlier in `PATH` would win (accepted, documented) |
| Focus a surface across windows and tabs | `makeKeyAndOrderFront` selects the tab; `Ghostty.moveFocus(to:)` `SurfaceView.swift:1075`; the sidebar does the same in `Sidebar.swift:341` | jump uses `window.makeKeyAndOrderFront` + `Ghostty.moveFocus` (the two lines of `SurfaceView.handleUserNotification`) |
| Surface lookup by id | `SessionRegistry.surfaceView(_:)` over `BaseTerminalController.surfaceTree` | reused |

Own, because Ghostty lacks it: the jump order, the notification gate (dedupe by need), the socket commands, the CLI. No parallel notification center, focus system or PATH logic.

Question for the main window (blocks the CLI location, see section 8): `Contents/MacOS` holds the app executable. `EXECUTABLE_NAME = ghostty` today (`project.pbxproj:551`). If the s8 agent renames the executable to `tarn`, the copy phase would overwrite the app binary. Default of this plan: CLI at `Contents/MacOS/tarn`; s8 must keep the executable name different from `tarn` (for example `tarn-app`, or keep `ghostty`). The alternative is `Contents/Resources/bin/tarn` plus one more insertion point that prepends that directory to `PATH` in `SurfaceView.swift` next to row 7; it works with any executable name but is a mechanism of our own.

## 3. Contracts

### 3.1 Socket (extends `docs/modules/control-socket.md`)

Request and reply are one JSON line, both with `"version":1`. Errors carry text without the `tarn: ` prefix: `{"ok":false,"error":"<text>","version":1}`; the CLI adds the prefix. The existing `open` errors lose their `tarn: ` prefix for this reason (no test or doc pins them).

| Command | Request | Reply on success | Errors (`error` text) |
|---|---|---|---|
| `open` (exists) | `{"version":1,"cmd":"open","surface":<uuid>,"path":"/abs"}` | `{"ok":true,"version":1}` | unchanged texts, prefix dropped |
| `ls` | `{"version":1,"cmd":"ls","json":false}` | `{"ok":true,"text":"<rows>","version":1}`; with `"json":true`: `{"ok":true,"sessions":[...],"version":1}` | `unsupported version` |
| `notify` | `{"version":1,"cmd":"notify","surface":<uuid>,"text":"..."}` | `{"ok":true,"version":1}` | `unsupported version`, `unknown surface`, `empty text` |
| any other `cmd` | | | `unknown command: <name>` (spec 3, "Bad request": error reply, log line, state unchanged) |

Keys are written sorted, so a reply starts with `{"error"` or `{"ok"`. Each refusal logs `os_log` category `socket` with command, surface and reason (spec 2.2 rule 3).

`ls` row (spec 11): `<n>  <project>  <branch>  <state>  <age>`, columns separated by two spaces, `n` the 1-based position in window, tab, split order, `state` one of `idle working waiting permission failed` (`failed` when `failed` and `waiting`), `age` since `stateSince`: `45s`, `2m`, `3h`, `2d`. Empty branch prints `-`. One row per registry record; no records, no output, exit 0. `sessions` JSON entries have the `Session` fields of spec 5: `surface`, `agentSessionID`, `cwd`, `project`, `branch`, `state` (the raw state; `waiting`), `since` (ISO 8601), `seen`, `failed`, `note`.

`project` is the git root folder name, else the cwd folder name; `branch` is read from `.git/HEAD` of the root (also for a worktree, where `.git` is a file with `gitdir:`), empty outside git or on a detached HEAD.

### 3.2 `tarn` CLI (`cli/tarn`, POSIX sh)

| Call | Does | Output |
|---|---|---|
| `tarn open <path>` | absolute path, or resolved against `$PWD`; sends `open` with `$TARN_SURFACE` | nothing, exit 0 |
| `tarn ls [--json]` | sends `ls` | rows, or the reply line with `--json` |
| `tarn notify <text...>` | words joined by one space; sends `notify` with `$TARN_SURFACE` | nothing, exit 0 |
| anything else, `-h` | usage on stderr (`tarn: usage: tarn open <path> \| ls [--json] \| notify <text>`), exit 1 | |

Errors (spec 2.2, 11): stderr `tarn: <text>`, exit 1, nothing on stdout. Client-side errors: `TARN_SURFACE is not set (run inside a tarn surface)` (open, notify), `tarn is not running` (no socket file or connect refused), `no answer from tarn` (empty reply or timeout 5 s), `bad answer from tarn` (a reply without `"ok":true` and without `"error"`). A reply with `"ok":true` is a success; `"ok":true` cannot appear inside a JSON string because quotes are escaped there.

Why a shell client: same base tools as `plugin/hooks/hook.sh` (`sh`, `nc -U`, `awk`, `sed`, `tr`), nothing to build or sign separately, no runtime to install (python3 on a bare macOS is an installer stub; perl is deprecated for removal). It must encode user text into JSON (awk `gsub` of `\`, `"`, tab, CR, newline; other control bytes dropped by `tr`) and decode one string field of the reply (`error`, `text`; `sed` for `\"`, `\\`, `\/`, `\n`, `\t`). Rejected: a Swift helper target (a second Xcode target, signing and a build phase for 60 lines of logic), a Python client (not guaranteed on the machine).

### 3.3 Registry additions (`SessionRegistry.swift`)

- `AgentSession` gets `agentSessionID` (set from `session_id` of every hook event, cleared on `SessionEnd`), and `note` (text of the last `tarn notify`, cleared on focus). Both take part in `==`.
- `AgentSession.need`: `.permission` for `permission`, `.failed` for `waiting` with `failed`, `.waiting` for any other `waiting`, nil otherwise.
- A change of `need` counts as a state change in `receive` (resets `since` and `seen`, spec 8 "every change resets"); today only `state` is compared, so `waiting` -> `StopFailure` -> `waiting, failed` would not reset.
- Focus clears `note` next to setting `seen` (`observeFocus`).

## 4. Notification and jump logic

New files in `macos/Sources/Features/Tarn/`, all logic pure and tested:

| File | Role |
|---|---|
| `Attention.swift` | `AttentionGate.notification(old:new:focused:project:) -> (title, body)?`, `AttentionGate.note(...)`, `suppressesTerminalNotification(_ session:)`, delivery through `Ghostty.App.showDesktopNotification`; a replaceable `deliver` closure for tests |
| `AttentionJump.swift` | `AttentionJump.order(_ sessions:)`, `next(sessions:excluding:)`, `@IBAction jumpToWaitingSession(_:)` on `BaseTerminalController`, focus of the chosen surface |
| `AttentionCommands.swift` | socket handler for `ls`, `notify` and unknown `cmd`; `ls` text and JSON builders |
| `ProjectInfo.swift` | project name and branch of a cwd (`.git` walk, `HEAD` read); the sidebar keeps its own private copy of the root walk, not touched here because `Sidebar.swift` is edited by other branches |

Gate rules (`docs/spec.md` 2.4 rule 3 and 4, section 3 "Repeat"):

1. A notification is raised when `new.need` is non-nil, differs from `old.need` (a missing record counts as nil), the surface is not focused (`NSApp.isActive`, key window, `view.focused`; same test as `SessionRegistry.isFocused`) and `new.seen` is false. The Esc path of `checkLiveness` stores `seen = true`, so it raises nothing.
2. Text: `permission` -> `Needs your permission`, `waiting` -> `Waiting for you`, `failed` -> `Failed, see the session`; title = project name (cwd folder name outside git; `tarn` when the cwd is unknown).
3. Same state repeated: `need` unchanged, nothing. Moving `permission` -> `waiting` or `waiting` -> `failed` is a new need, one notification each.
4. `notify`: the text is trimmed; empty -> error. If the surface is focused, no note is stored and nothing is raised (the user is looking at it; decision of this plan, spec silent). Otherwise: same text as the current `note` -> nothing; else store the note and raise one notification with the text as body. A surface without a record gets one (state `idle`). The sidebar ignores `idle` sessions, so the note shows in the jump and in `tarn ls` only.
5. Suppression: the guard in `Ghostty.App.showDesktopNotification(app, target:, n:)` returns when the surface's record has a non-empty `agentSessionID`. A surface with no record or an empty id keeps Ghostty's behavior.
6. Authorization denied: Ghostty's route returns silently (it logs the request error, `Ghostty.App.swift:1637-1639`). `deliver` logs one info line `raised <need> for <surface>`, so a missing banner is explained by that line plus Ghostty's. Gap: we cannot see the denial itself.

Jump order (spec 8 and 10, user decision), `AttentionJump.order`: candidates are records with `need` non-nil or a non-empty `note`. Group 0 `failed`, group 1 `permission`, group 2 `waiting` or note. Inside a group: unseen before seen, then smaller `since` first, then surface id for a stable result. `next` skips the surface that is focused now (the key goes to "the next session", never to the one in front of you) and returns nil when no candidate is left; then the menu action beeps and does nothing. The chosen surface: `makeKeyAndOrderFront` of its window and `Ghostty.moveFocus(to:)`; focusing marks it seen, so the next press moves on.

The menu item is Window > "Jump to Waiting Session", `keyEquivalent="u"`, Command, action `jumpToWaitingSession:` to the first responder (target `-1`). Verified free: no default Ghostty binding uses `u` (`src/config/Config.zig`: the default `unicode = '...'` keys are a c d e f g i j k n o p q t v w z); `MainMenu.xib` key equivalents are `, ? b f h m`. A user binding on `super+u` wins over the menu (Ghostty's key handling runs first), which is the intended override.

## 5. Files

| Path | Change |
|---|---|
| `cli/tarn` | new, mode 755, the CLI |
| `cli/test/cli_test.py` | new, CLI against a fake socket |
| `macos/Sources/Features/Tarn/Attention.swift`, `AttentionJump.swift`, `AttentionCommands.swift`, `ProjectInfo.swift` | new |
| `macos/Sources/Features/Tarn/SessionRegistry.swift` | `agentSessionID`, `note`, `need`; call the gate in `receive`; clear note on focus; `notify` and `rows` accessors; start callback calls `AttentionCommands.handle` after `ViewerRouter.handleCommand` |
| `macos/Sources/Features/Tarn/ViewerHost.swift` | `open` errors lose the `tarn: ` prefix; `open` reply gets `version` |
| `macos/Ghostty.xcodeproj/project.pbxproj` | file reference `../cli/tarn`, copy phase "Copy tarn CLI" (`dstSubfolderSpec = 6`, Executables) added to the app target; one hunk, no build setting |
| `macos/Tests/Tarn/AttentionTests.swift`, `AttentionCommandsTests.swift` | new |
| `docs/spec.md` section 10 status; `docs/modules/attention.md` (new); `docs/modules/control-socket.md`, `sessions.md`; `docs/architecture.md` sections 1, 9, 10 | docs |

## 6. Insertion points (new rows of `docs/architecture.md` section 9)

| # | File | Insertion | Why |
|---|---|---|---|
| 20 | `macos/Sources/App/MainMenu.xib` | Window menu: item "Jump to Waiting Session", key equivalent `u`, action `jumpToWaitingSession:` to the first responder, after "Show/Hide All Terminals" | Cmd+U jump; the action is in `AttentionJump.swift` |
| 21 | `macos/Sources/Ghostty/Ghostty.App.swift` | in `showDesktopNotification(_ app:target:n:)` surface case: `if Attention.suppresses(surfaceView) { return }` before the call; `private` removed from `showDesktopNotification(_ surfaceView:title:body:requireFocus:)` | OSC 9/777 of a live agent session is dropped; our notification goes through Ghostty's route |
| pbxproj | `project.pbxproj` | file reference and copy phase for `cli/tarn` (not a Swift change, listed for the merge rule) | the CLI ships in `Contents/MacOS` |

## 7. Tests

Swift (`macos/Tests/Tarn/AttentionTests.swift`, `AttentionCommandsTests.swift`, Swift Testing):

- Jump: failed before permission before waiting; R4 example (one failed, two waiting: failed, then the unseen one waiting longer; seen after unseen); idle and working without note and the focused surface are skipped, nil when empty; a note makes an idle record a candidate.
- Gate: raises once per need (idle -> permission, same state again nothing, permission -> waiting raises, waiting -> failed raises); focused surface and `seen` (Esc path) raise nothing; texts and title of spec 11; note dedupe (same text nothing, new text raises, focused stores nothing, focus clears); `need` change resets `since` and `seen`.
- Suppression: non-empty `agentSessionID` suppresses; empty or no record does not; `SessionEnd` clears the id; events set it.
- Socket: `ls` text rows (format, `-` branch, `failed`, ages, order) and JSON fields; `notify` reply; errors (bad version, unknown surface, empty text, unknown command) give `ok:false`, text without prefix, state unchanged; `open` errors without prefix; `ProjectInfo` (git root, branch, worktree file, detached HEAD, no git).

CLI (`python3 -I cli/test/cli_test.py`, fake unix socket in a temp `HOME`, like `plugin/test/hook_test.py`): open absolute and relative; JSON escaping (quotes, backslash, tab, newline, UTF-8); notify joins words; `ls` and `--json` output; error reply -> stderr `tarn: <text>`, exit 1, empty stdout; no `TARN_SURFACE`; no socket, refused, silent server (timeout shortened by env), garbage reply; usage errors; `shellcheck cli/tarn` and `ruff` clean.

Not tested, reported as such: `tarn` on PATH in a new surface (build product listing, `codesign --verify`); a real banner and its click. I will not launch the app: `ControlSocket.start` removes the user's live socket file.

## 8. Order of work and risks

1. Registry fields, `need`, gate, jump order (pure, tests first).
2. Socket commands, `ProjectInfo`, `open` error cleanup.
3. Insertion points 20, 21; wiring in `receive`, `observeFocus`.
4. CLI and its tests; pbxproj hunk.
5. Docs; build; Tarn tests; `swiftlint --strict`; `typos`; `shellcheck`; ruff for the CLI test.

| Risk | Handling |
|---|---|
| Executable name collision in `Contents/MacOS` (section 2) | decision requested; default as in section 2 |
| `pbxproj` merge conflict with s8 | hunk limited to the new file reference, the group child, the copy phase and one entry in the target's `buildPhases` |
| `nc -U` behavior with a server that closes first, or a hung app | tested against a fake server; timeout 5 s |
| A Ghostty keybinding or the web view eats Cmd+U | binding check in section 4; the viewer's `performKeyEquivalent` checked while implementing |
| Spec says `tarn hook`; the plugin uses `hook.sh` | left as is; noted in `architecture.md` section 10 |
| Notification when the app is not authorized | Ghostty's route is silent (gap in section 4 rule 6) |

## 9. Changes after the spec review (2026-10-25)

Decisions of the main window: CLI at `Contents/MacOS/tarn`, executable stays `ghostty`; jump order per spec section 8 with Limpid's cursor (the entry after the focused one, wrapping, so seen sessions keep cycling; beep when none); `notify` on a focused surface stores nothing and raises nothing; focus through `BaseTerminalController.focusSurface`; `ControlSocket.start` leaves a live socket alone.

Done differently from sections 2 to 8:

- The copy phase with `CodeSignOnCopy` does not sign a script (`codesign: code object is not signed at all`, reproduced on a Debug build). The pbxproj hunk is a shell phase that installs and signs `cli/tarn` (insertion point 22, no file reference).
- Jump: `next` replaces the "skip focused" rule; a record without a live surface is dropped by `liveSessions` (M2); a note counts as unseen and sorts by `noteSince`; the focus observer clears a note also on a seen session (M1).
- Gate: a new permission request in `permission` counts as a new need; the banner text of a note is cut at 500 characters; one log line per raise plus one when notifications are not authorized.
- `ls` numbering is screen order (windows in tab groups, tabs, splits) among live records. `cwd` is the surface `pwd`. Replies are written with sorted keys; the CLI decodes in one awk pass and ignores the reply `version`.
- Prior art: jump order follows Limpid `AttentionState.swift` at 327e41d3c087 (MIT), credited in `THIRD_PARTY.md`. CLI: no analog needed beyond `plugin/hooks/hook.sh`.
- Not done: addressing the action through `AppDelegate` (Cmd+U is off while the Settings window is key); resetting `agentSessionID` when the agent dies without `SessionEnd` (the spec keys suppression on the id alone); `SessionEnd` after `/clear` keeps the id (spec 5 says empty; a user decision is needed).
