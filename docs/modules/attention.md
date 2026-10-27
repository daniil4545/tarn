# Module: attention

## Purpose

Tells the user once that a session needs them, jumps to that session with Cmd+U, and gives agents the `tarn` CLI to open files, list sessions and ask for attention without moving focus. Spec: `docs/spec.md` R4, R8, sections 2.2, 8, 10, 11, 12.

## Place in the system

```mermaid
flowchart LR
  cli["tarn CLI"] -->|"ls, notify, open"| sock["ControlSocket"]
  sock --> cmd["AttentionCommands"]
  hook["hook events"] --> reg["SessionRegistry"]
  cmd --> reg
  reg -->|"old and new session"| gate["Attention gate"]
  gate -->|"one per need"| route["Ghostty notification route"]
  menu["Cmd+U"] --> jump["AttentionJump"]
  jump -->|"focusSurface"| term["Terminal"]
  route -->|"click"| term
```

Reading: the registry feeds every state change to the gate; the gate decides, Ghostty shows and handles the click. Source: `Attention.swift`, `AttentionJump.swift`, `AttentionCommands.swift`, `cli/tarn`.

## Inputs and outputs

| Direction | What | Where |
|---|---|---|
| In | a state change of a session (old, new, focused) | `SessionRegistry.receive` -> `Attention.consider` |
| In | `{"version":1,"cmd":"notify","surface":<uuid>,"text":...}` | `AttentionCommands.handle`, `SessionRegistry.notify` |
| In | OSC 9/777 of a surface | `Ghostty.App.showDesktopNotification` -> `Attention.suppresses` |
| Out | a notification: title = the project (git root folder name; the working folder outside git; `tarn` when the directory is unknown), body from `docs/spec.md` 11 | `Ghostty.App.showDesktopNotification(_:title:body:)` |

## How it works

Gate (`Attention.body`): a body is raised when the new session has a need (`permission`, `waiting`, `failed`) the old one did not, the surface is not focused and `seen` is false. A repeated state raises nothing. A new permission request while the session is already in `permission` resets `since` and `seen`, like a state change, and raises a banner when the surface is not focused, because approving in the terminal sends no event. The Esc path stores `seen = true` and raises nothing. A change of `failed` alone resets `since` and `seen`, like a state change.

`tarn notify`: the text is trimmed and cut at 500 characters. If the surface is focused, nothing is stored and nothing is raised; the reply is ok. One banner per surface per note: the first `notify` since the user last focused the surface stores the note and `noteSince` and raises one notification with the text as body; while that note is unseen, a different text replaces it silently (no banner, no sound, `noteSince` kept), and the same text changes nothing. Focusing the surface clears the note, also on a seen session (`AgentSession.markFocused`); the next `notify` banners again. The focus watcher ignores the `focusInstant` a surface had before its record existed (`SessionRegistry.focusEvents`), or the first `notify` on a once-focused surface would erase its own note.

Suppression: a terminal notification from a surface whose record has a non-empty `agentSessionID` is dropped. The id comes from `session_id` of hook events; `SessionEnd` clears it except after `/clear` (the agent keeps running, so a second banner would appear).

Jump (`AttentionJump`, after Limpid `AttentionState.swift`): candidates are live sessions with a need or a note. Order: `failed`, `permission`, `waiting` or note; inside a group unseen first (a note counts as unseen), then the longest wait (`since`, or `noteSince` for a note without state). The cursor goes to the entry after the focused session and wraps, so repeated presses cycle through seen sessions too; when the focused session is the only candidate, or there is none, the menu action beeps. `SessionRegistry.liveSessions` drops records whose surface is gone and lists surfaces of every `BaseTerminalController` window: tab groups first, then other windows such as the quick terminal (`SessionRegistry.screenOrder`). Focus uses `BaseTerminalController.focusSurface`, which also shows a hidden quick terminal.

`tarn ls` lists terminal panes, not sessions: [agent-commands.md](agent-commands.md). Its `STATE` column is `AgentSession.listState`: the state name, `failed` for a failed waiting session.

CLI (`cli/tarn`, POSIX sh with `nc -U`, `awk`, `tr`): builds the request line, escapes text into JSON, prints the decoded `text` field or the whole reply for `--json`. Errors go to stderr as `tarn: <text>` with exit 1: the app's `error`, or `tarn is not running`, `no answer from tarn` (5 s, `TARN_TIMEOUT`), `bad answer from tarn`, `TARN_SURFACE is not set`. The reply `version` is not checked. `open` resolves a relative path against `$PWD`. The app puts the CLI folder on `PATH`: the core appends the folder of the app executable (`src/termio/Exec.zig:681-710`), here `Contents/MacOS`.

Why a shell client: it needs the same base tools as `hook.sh` (`sh`, `nc -U`, `awk`, `tr`), nothing to build or sign, no runtime (`python3` on a bare macOS is an installer stub). Rejected: a Swift helper target, a Python client. The CLI lives in `Contents/MacOS/tarn`, so the app executable must keep a different name (`ghostty`); the alternative `Contents/Resources/bin/tarn` plus a `PATH` prepend was rejected as an own mechanism.

Cmd+U has no default Ghostty binding; a user binding on `super+u` wins over the menu item. Known limits: Cmd+U does nothing while the Settings window is key. `agentSessionID` is not reset when an agent dies without `SessionEnd`, so terminal notifications of that surface stay suppressed.

## Files

| Path | Role |
|---|---|
| `macos/Sources/Features/Tarn/Attention.swift` | `AgentNeed`, gate, suppression, delivery |
| `macos/Sources/Features/Tarn/AttentionJump.swift` | order, cursor, menu action |
| `macos/Sources/Features/Tarn/AttentionCommands.swift` | `ls`, `notify`, reply format |
| `macos/Sources/Features/Tarn/ProjectInfo.swift` | project name and branch |
| `macos/Sources/Features/Tarn/SessionRegistry.swift` | fields, `notify`, `liveSessions` |
| `cli/tarn` | the client |

## Ghostty mechanisms used

| Mechanism | Where |
|---|---|
| Show a notification for a surface (authorization, `showUserNotification`) | `Ghostty.App.swift` `showDesktopNotification(_ surfaceView:...)`, `SurfaceView_AppKit.swift` `showUserNotification` |
| Show only when not focused | `Ghostty.App.shouldPresentNotification`, `AppDelegate.userNotificationCenter(_:willPresent:)` |
| Click focuses the surface | `AppDelegate.userNotificationCenter(_:didReceive:)` -> `Ghostty.App.handleUserNotification` -> `SurfaceView.handleUserNotification` |
| Focus a surface | `BaseTerminalController.focusSurface` |
| `tarn` on `PATH` | `src/termio/Exec.zig:681-710` |

## Insertion points in upstream files

Rows 20, 21 and 22 of [architecture.md](../architecture.md) section 9.

## Invariants and failure rules

| Rule | Enforced by |
|---|---|
| Agents never move focus: `notify` and `open` only mark or open | no focus call in `AttentionCommands` or `SessionRegistry.notify`; review (not verified by a test) |
| One notification per need, one per unseen note | `Attention.body`, `Attention.note`; `AttentionTests`, `AttentionRegistryTests` |
| No dead session in the jump or in `ls` | `SessionRegistry.liveSessions` |
| A line that is not a JSON object (junk, invalid UTF-8) gets `malformed request`; a permission hook's line (`"reply":true`) gets silence, because that hook prints the answer; the line is parsed once, in `SessionRegistry.start` | `AttentionCommands.refuse`, `isMalformed`; `MalformedLineTests` |
| Errors: log line, `{"ok":false,"error":...}`, CLI exit 1, state unchanged | `AttentionCommands.answer`; `AttentionCommandsTests`, `cli_test.py` |
| A second app never takes over a live socket | `ControlSocket.hasListener`; `ControlSocketOwnershipTests` |
| Denied notification permission: sidebar still marks; one log line | `Attention.raise` |

## Tests

`AttentionTests` (order, cursor, gate, notes, session id), `AttentionRegistryTests` (a stub surface and a recorded banner list: hook events reach the gate, suppression, `notify`, focus watcher, screen order, malformed lines), `AttentionCommandsTests` (rows, ages, JSON fields, reply format, refusals), `ProjectInfoTests`, `ControlSocketOwnershipTests`; `python3 -I cli/test/cli_test.py` (CLI against a fake socket); `shellcheck cli/tarn`. Not tested: a real banner and its click; `tarn` on `PATH` in a live surface.

## Extending it

| Change | Goes to |
|---|---|
| New need or text | `AgentNeed`, `AgentSession.need`, `AttentionJump.group` |
| New CLI command | `cli/tarn` and a case in `AttentionCommands.perform` |
| Change the key | `MainMenu.xib` item "Jump to Waiting Session" (a user binding on `super+u` still wins) |
