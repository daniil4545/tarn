# S4: settings module

Plan for the macOS settings window. Look: `docs/mockups/tarn.html`, checks S1-S12 in `docs/mockups/check.py`. D18 (`docs/plans/windows-workspaces.md`): changed Ghostty options go to `~/.config/tarn/ghostty.conf`, loaded after the user's config; the user's file is never edited. Paths are under `macos/Sources/` unless noted.

## 1. Research (Ghostty first)

### 1.1 Load order and reload

- One function builds every config: `Ghostty/Ghostty.Config.swift:60-95`: `load_file` (if `GHOSTTY_CONFIG_PATH`) or `load_default_files`, then `load_cli_args`, then `load_recursive_files`, then `finalize`.
- `config-file` includes load last (`src/config/Config.zig:4426`). Scalars: last wins. Repeatable options (`font-family`) append; an empty value clears the list (`RepeatableString.parseCLI`).
- `ghostty_config_load_file` needs an absolute path and logs `log.err` for a missing file (`src/config/CApi.zig:71`). Check `fileExists` first.
- Insertion point 12 (`docs/architecture.md` section 9, text: "parameter plus one call"): `loadConfig` gets a parameter `tarnFile: URL? = nil`; after `ghostty_config_load_recursive_files` and before `finalize` it calls `TarnConfigFile.load(into: cfg, from: tarnFile)` when non-nil. Only `convenience init(at:finalize:)` (`Ghostty.Config.swift:40`, called by `Ghostty.App.swift:50,154,174`) passes the real path. `TemporaryConfig` and upstream tests pass nothing, so a developer's real file never reaches them; our tests pass a temp URL. After the includes, so the tarn file beats them; `finalize` replays our lines after the theme (`Config.zig:4739`). CLI flags lose to it; accepted.
- Reload needs nothing new. `Ghostty.App.reloadConfig()` (`Ghostty.App.swift:144`) runs `loadConfig`, then `ghostty_app_update_config`. `configChange` (`Ghostty.App.swift:2441`) posts `.ghosttyConfigDidChange` (`GhosttyPackage.swift:291`) at `:2446`, before it sets `ghostty.config` at `:2459`; per-surface reloads post it with `object: surfaceView` (`:2466`). So the Store reads the config from `userInfo[GhosttyConfigChangeKey]` and accepts only `object == nil`. Menu Reload (`AppDelegate.swift:1003`) uses the same path; there is no file watcher.

### 1.2 Effective values

`ghostty_config_get` (`include/ghostty.h:1153`, `src/config/c_get.zig`) returns bool, ints, floats, enums (tag name), types with `cval()`; false for other structs and unset optionals. Accessors to copy: `Ghostty.Config.swift:155,214,274,477,485,621`.

| Readable | Options |
|---|---|
| yes | all other catalog options: floats, bools, enums (tag name), background-blur (i16), undo-timeout (ms) |
| no | theme, font-family, window-padding-x (struct without `cval`) |
| when set | cursor-style-blink, macos-option-as-alt: optionals; `c_get` returns false only when unset (`c_get.zig:56`), shown as "default (auto)" |

"Set in tarn" needs no Ghostty call: the key is a line in our own file. The three unreadable options show the tarn value if set, else the text "from Ghostty config" (user decision Q1); no second parser.

### 1.3 Keys for Help

`ghostty_config_trigger(cfg, "action", len)` (`include/ghostty.h:1154`, `src/config/CApi.zig:104`) returns the trigger of one action; empty if unbound. Wrappers: `keyboardShortcut(for:)` (`Ghostty.Config.swift:114`, used at `Sidebar.swift:188`) and `KeyboardShortcut.keyList` (`Helpers/Extensions/KeyboardShortcut+Extension.swift:4`). No C call lists all bindings, so Help keeps a fixed list (group, label, action) and asks Ghostty for each key. The action strings come from `AppDelegate.swift:1209-1247` (with parameters, e.g. `goto_split:previous`, `resize_split:up,10`, `navigate_search:next`, `open_config`); the rest are checked in `src/input/Binding.zig`: `goto_tab:N`, `last_tab` (cmd+9), `previous_tab`, `next_tab`, `toggle_fullscreen`, `equalize_splits`, `clear_screen`, `increase_font_size:1`, `reset_font_size`, `jump_to_prompt:-1`, `toggle_command_palette`. An empty trigger shows "not bound". Key symbols come from `keyList` (arrows, return); the mockup data follows it. Viewer keys (cmd+B/E/S) are not Ghostty bindings: table at `Features/Tarn/ViewerWebView.swift:16`; Help reads it (shared constant), source "tarn".

### 1.4 Mockup values against `src/config/Config.zig`

Wrong or misleading (the rest match Zig):

| Option | Problem |
|---|---|
| cursor-style-blink | default is `null` (line 902), not true; explicit `true` ignores DEC mode 12 |
| macos-option-as-alt | default is `null` (3527): true on US layouts, false elsewhere; mockup says false; add "(default)" entry |
| macos-titlebar-style | user decision Q2: offer only transparent, native, hidden (`tabs` removed) |
| background-opacity, titlebar-style, font-size | do not change live: opacity needs a restart on macOS (`Config.zig:1010`), titlebar style applies to new windows (`:3456`), font-size does not change a terminal after cmd+= (`Surface.zig:1856`); see `applies` in section 2 |
| notify-on-command-finish | action defaults to bell only (1228), threshold 5 s (1265); help text says "notify" |
| background-blur | accepts bool, radius, `macos-glass-regular|clear` (9948); checkbox covers bool only; show read-only text for others |
| font-family | repeatable (177): the writer must emit `font-family = ""` before the value, else the tarn font is only a fallback |
| theme | `?Theme` (601); names from `<Resources>/ghostty/themes` and `~/.config/ghostty/themes` (`src/config/theme.zig:20`) |

### 1.5 Analogs (licenses via `gh api`, 2026-10-25)

| Project | License | Use |
|---|---|---|
| chlee1001/chostty PR 24 (`Features/Settings/ConfigEditor/`) | MIT | read before slices A and C |
| alxhill/ghostty `ah/config-ui` (Modified view, reset) | MIT | behaviour match for "set in tarn" plus Reset |

No prior art for a side file loaded after the user's config; that part is ours.

## 2. Architecture

Write: create `~/.config/tarn` (base `$XDG_CONFIG_HOME` if set), then `Data.write(to:options: .atomic)`.

Flow: `GhosttyOptionStore` writes `~/.config/tarn/ghostty.conf`, calls `reloadConfig()`, and reads the new config back through `GhosttyOptionReader`.

All types are in `Features/Tarn/`.

| Type | Job |
|---|---|
| `TarnConfigFile` | path; parse to ordered entries plus verbatim unknown lines; set, remove, serialize; atomic save; `load(into:)` |
| `GhosttyOption` | catalog row (key, kind, default, values, help, section, applies): the mockup `GHOSTTY` table as data |
| `GhosttyOptionReader` | effective value through `ghostty_config_get`; nil if unreadable |
| `GhosttyOptionStore` | `@MainActor` model; set (always writes), reset; save, then `reloadConfig()`; refresh from the notification's config (`object == nil`); re-read the file before each save and merge by key |
| `KeyReference` | Help list and key text via `keyboardShortcut(for:)?.keyList` |

File format: header comment (what the file is, "delete a line to give the option back"), then `key = value`, one per line, catalog order. Values with edge spaces, quotes or backslashes are quoted and escaped; the Ghostty round-trip test proves it. Choice and bool controls write at once; number and text on commit (Tab, Return); sliders on release.

Rules: a change in a control always writes the line, even when the value equals the Ghostty default; only Reset removes it, so the user's own value never resurfaces. Each option has `applies`: `live`, `new windows` or `restart`; the row shows that text (opacity: "restart needed", titlebar style: "new windows"). The writer rejects values with `\n` or `\r`, saves through `resolvingSymlinksInPath()` (a dotfiles symlink survives), and the header says `config-file` lines are ignored.

Failures: (1) write fails (directory not writable, read-only disk): log with `Logger` (path, error), show a message in the option row, the control returns to the last saved value, no `reloadConfig()`; (2) the file holds a value the control cannot show (`undo-timeout = 7s`, unknown enum): show the raw text read-only with Reset; (3) Ghostty rejects the line after reload: the standard configuration errors window opens and the mark "set in tarn" stays.

## 3. Slices

| Slice | Owns | Done when |
|---|---|---|
| M. Mockup data | `docs/mockups/tarn.html`, `docs/mockups/check.py` (user decision Q3, before Swift) | data fixed per 1.4 plus `applies` labels, keep-line-on-default, arrow symbols; `check.py` passes |
| A. Config file | `TarnConfigFile.swift`, `Tests/Tarn/TarnConfigFileTests.swift`; `tarnFile` parameter and one call in `Ghostty.Config.swift`; architecture row 12 | tests green; a hand-written tarn file changes font-size in a running Debug app after menu Reload |
| B. Catalog, reader | `GhosttyOption.swift`, `GhosttyOptionReader.swift`, `Tests/Tarn/GhosttyOptionTests.swift` | catalog defaults equal Zig defaults |
| C. Options panes | `GhosttyOptionStore.swift`, `GhosttyOptionsPane.swift`; section enum in `TarnSettings.swift` | S7-S10 in the real window |
| D. Help | `KeyReference.swift`, `HelpPane.swift`, `Tests/Tarn/KeyReferenceTests.swift`; key table in `ViewerWebView.swift` | S11 in the real window; every action gives a trigger in `TemporaryConfig("")` |

Order: M, A, B, then C and D in parallel (D adds its enum case after C merges). Each under 400 lines.

## 4. Unit tests (`macos/Tests/Tarn/`)

Tests pass a temp URL as `tarnFile`; no global path, parallel tests do not collide, the real `~/.config/tarn` is never read.

| Test | Proves |
|---|---|
| writer round-trip | serialize then parse is identical; comments and unknown lines survive; spaces, quotes, `#`, backslash, empty value |
| Ghostty reads it | `ghostty_config_get` returns the value (covers quoting) |
| precedence | user 12, tarn 16: 16; a `config-file` include with 10 loses; user `theme = X`, tarn 16: 16 (before `finalize`); no tarn file: user value |
| font-family | user `A`, tarn `B`: effective list is only B |
| Reset | removes only that line; empty file loads; user value returns |
| set to default | user 12, set 13 in tarn: line `font-size = 13` written, effective 13; only Reset removes it |
| atomic save | failed write leaves the old file intact and reports an error; a symlinked file stays a symlink; a value with a newline is rejected |
| out of control | `undo-timeout = 7s` in the file is shown as raw text with Reset |
| notification | Store takes the config from `userInfo` and ignores a notification with an `object` |
| catalog | defaults match Zig |

## 5. Acceptance (mockup checks)

| Check | Status | Verified by |
|---|---|---|
| S1-S6 window, Escape, tab style, tab bar | exist or outside S4 | run app |
| S7 section shows its options only | C | open Appearance, count rows |
| S8 mark "set in tarn" and applies | C | font-size 16 in a terminal where cmd+= was not used; it redraws without restart; opacity row says "restart needed" |
| S9, S9a file lists changed options only; drag-handle never hides dots | C | `cat` of the file equals the preview; dots gone in a split |
| S10 Reset | C | line and mark gone, user value returns |
| S11 Help shows keys in effect | D | user file `keybind = cmd+shift+w=close_tab`, reload, Help shows it |
| S12 survive restart | A | quit, start; font-size still 16 (after C) |

## 6. Ghostty provides / we add

| Need | Ghostty provides | We add |
|---|---|---|
| Load order | `load_file`, `load_recursive_files`, `finalize` | one call in `loadConfig` |
| Apply to windows | `reloadConfig`, `ghostty_app_update_config`, `.ghosttyConfigDidChange` | call after a write |
| Effective value | `ghostty_config_get` (most keys) | reader; "set in tarn" from our file |
| Keys in effect | `ghostty_config_trigger`, `keyList` | action list and labels |
| Side file, atomic write | nothing | `TarnConfigFile` |

## 7. Risks

| Risk | Handling |
|---|---|
| Three options unreadable | text "from Ghostty config" |
| Bad value in the file (hand edit, removed theme) | failure rule 3 |
| Launch with `-e`: our replay steps land after `-e` (`Config.zig:4434`) | skip the tarn file when argv has `-e` |

## 8. Decisions taken

Q1: unreadable options show "from Ghostty config" unless set in tarn. Q2: titlebar style offers transparent, native, hidden. Q3: mockup data fixed first (slice M). M4: a change always writes the line; only Reset removes it. No open questions.
