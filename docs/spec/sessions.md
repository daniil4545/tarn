# Sessions, attention and the control socket

Canon for what tarn tracks per terminal surface and how it tells the user (R3, R4, R8, R10 of `docs/spec.md`; state table in its section 8); built.

## 1. Sessions

The registry is the only writer of session state; it is in memory and keyed by surface UUID. Inputs: Claude Code and Codex hook events through the plugin, the surface's title, progress report, visible text and focus. The app sets `TARN_SURFACE=<uuid>` in each shell.

- `hook.sh` exits at once without `TARN_SURFACE` or the socket; otherwise it wraps stdin as `{"version":1,"surface","event"}`, sends it with `nc -U -w 1` in the background and waits about 40 ms so events keep order. `receive` drops lines that are not a JSON object with `version` 1, a UUID surface and an event name, and events for unknown surfaces.
- `PermissionRequest` with `"reply":true` joins a per-surface `pending` queue (oldest first). A question the card cannot answer (several questions, multi-select) gets an empty reply at once so Claude Code shows its dialog. A finished tool call drops its own request; the end of a turn (`UserPromptSubmit`, `StopFailure`, `SessionEnd`, `Stop` without background tasks) drops all; a dropped hook gets an empty reply.
- Answer: option 0 allows, other denies with a message; a question's option label goes in `updatedInput.answers`; with no request left the session returns to `working`. No key is ever sent for the user.
- Liveness (Claude Code sends no event on Esc): a 1 s timer checks `working` and `permission` sessions. Working with no progress report and a title starting with `✳` for 2 s becomes `waiting`, seen; permission with "Interrupted" in the last 12 visible lines for 2 s becomes `waiting`. A vanished surface removes its session and answers its hooks. Depends on Claude Code text; a UI change breaks it silently. Approving in the terminal gives no event, so `permission` stays until `PostToolUse`.
- Agent naming: the foreground process name `claude`, `codex`, `opencode` exactly or as a prefix followed by a non-alphanumeric; for a bare version (`2.1.207`) or an interpreter (`node`) argv[0] or the script name via `KERN_PROCARGS2` (ported from macterm, MIT). `claude` and `codex` (with `--no-daemon`) have hooks; `opencode` gets an icon and a group only.

## 2. Attention

- Gate (`Attention.body`): a banner is raised when the new session has a need (`permission`, `waiting`, `failed`) the old one did not, the surface is not focused and `seen` is false. A repeated state raises nothing. A new permission request while already in `permission` resets `since` and `seen` and banners when the surface is not focused. The banner title is the project (git root folder name, the working folder outside git, `tarn` if unknown); texts are in `docs/spec.md` section 11.
- `tarn notify`: the text is trimmed and cut at 500 characters. A focused surface stores and raises nothing. One banner per surface per note: the first note since the user last focused the surface banners; while it is unseen a different text replaces it silently (no banner, no sound), the same text changes nothing; focusing clears the note.
- Suppression: a terminal notification (OSC 9, 777) from a surface whose record has a non-empty `agentSessionID` is dropped. The id comes from hook `session_id`; `SessionEnd` clears it except after `/clear` (the agent keeps running). An agent that dies without `SessionEnd` keeps its surface suppressed.
- Jump (Cmd+U, no default Ghostty binding; a user `super+u` binding wins; after Limpid `AttentionState.swift`): candidates are live sessions with a need or a note. Order: `failed`, `permission`, `waiting` or note; inside a group unseen first, then the longest wait. The cursor goes to the entry after the focused session and wraps; with no other candidate the menu action beeps. It lists surfaces of tab groups first, then other windows such as the quick terminal, and shows a hidden quick terminal. Does nothing while Settings is key.
- Denied notification permission: the sidebar still marks; one log line.

## 3. Control socket and CLI

- `~/Library/Application Support/tarn/tarn.sock`, mode 0600; one JSON line per request and reply, `version` 1. A line is read with a 1 s receive timeout on its own thread, at most 4 MB (dropped and logged beyond). A bind failure or a path over the `sun_path` limit is logged and the app runs without the socket. Before binding, `start` connects to an existing file: a live listener (another tarn or a Debug build) keeps it, a stale file is replaced.
- Dispatch order: `open` (viewer), then agent commands (`ls`, `new`, `run`, `wait`, `read`, `close`, `modules`), then `notify`, then an error for any other `cmd`; a line without `cmd` is a hook event. A line that is not a JSON object gets `malformed request`, except a permission hook's line (`"reply":true`), which gets silence.
- Errors: log line, `{"ok":false,"error":...}`, CLI exit 1, state unchanged. CLI messages: `tarn is not running`, `no answer from tarn` (5 s, `TARN_TIMEOUT`), `bad answer from tarn`, `not in a tarn tab`.
- The CLI is POSIX sh with `nc -U`, `awk`, `tr`: the same base tools as `hook.sh`, nothing to build or sign, no runtime (`python3` on bare macOS is an installer stub). Rejected: a Swift helper, a Python client. It lives in `Contents/MacOS/tarn` (so the app executable keeps the name `ghostty`) and the core puts that folder on `PATH` (`src/termio/Exec.zig:681-710`); a `tarn` earlier in `PATH` hides ours. Rejected: `Contents/Resources/bin/tarn` plus a `PATH` prepend (an own mechanism).
- `tarn ls` and the other pane commands: `docs/spec/agent-cli.md`.
