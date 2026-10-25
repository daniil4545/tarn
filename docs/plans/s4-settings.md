# S4: settings module

Plan for the macOS settings window. Look and behaviour: `docs/mockups/tarn.html` (`GHOSTTY`, `KEYS`, `setGhostty`) and checks S1-S12 in `docs/mockups/check.py`. Decision D18 (`docs/plans/windows-workspaces.md`): changed Ghostty options go to `~/.config/tarn/ghostty.conf`, loaded after the user's config; the user's file is never edited. Paths are under `macos/Sources/` unless noted.

## 1. Research (Ghostty first)

### 1.1 Load order and reload

- One function builds every config: `Ghostty/Ghostty.Config.swift:60-95`: `load_file` (if `GHOSTTY_CONFIG_PATH`) or `load_default_files`, then `load_cli_args`, then `load_recursive_files`, then `finalize`.
- `config-file` includes load last (`src/config/Config.zig:4426`). Scalars: last wins. Repeatable options (`font-family`) append; an empty value clears the list (`RepeatableString.parseCLI`).
- `ghostty_config_load_file` needs an absolute path and logs `log.err` for a missing file (`src/config/CApi.zig:71`). Check `fileExists` first.
- Insertion point 12 (add to `docs/architecture.md` section 9): in `loadConfig`, after `ghostty_config_load_recursive_files` and before `finalize`, call `TarnConfigFile.load(into: cfg)`. After the includes, so the tarn file beats them; before `finalize`, so `theme` resolves. CLI flags lose to it; accepted.
- Reload needs nothing new. `Ghostty.App.reloadConfig()` (`Ghostty.App.swift:144`) runs `loadConfig`, then `ghostty_app_update_config`. `configChange` (`Ghostty.App.swift:2441`) posts `.ghosttyConfigDidChange` (`GhosttyPackage.swift:291`) and replaces `ghostty.config`; surfaces refresh (`SurfaceView_AppKit.swift:762`). Menu Reload (`AppDelegate.swift:1003`) uses the same path. Ghostty has no config file watcher.

### 1.2 Effective values

`ghostty_config_get` (`include/ghostty.h:1153`, `src/config/c_get.zig`) returns bool, ints, floats, enums (tag name), types with `cval()`; false for other structs and unset optionals. Existing accessors to copy: `Ghostty.Config.swift:155,214,257,274,354,477,485,493,621`.

| Readable | Options |
|---|---|
| yes | font-size, background-opacity, unfocused-split-opacity, cursor-style, copy-on-select, window-theme, macos-titlebar-style, notify-on-command-finish, window-save-state, confirm-close-surface, drag-handle, mouse-hide-while-typing, clipboard-paste-protection, link-url, window-inherit-working-directory, background-blur (i16), undo-timeout (ms) |
| no | theme, font-family, window-padding-x (struct); cursor-style-blink, macos-option-as-alt (optional, unset) |

"Set in tarn" needs no Ghostty call: the key is a line in our own file. For the five unreadable options, the control shows the tarn value or the default; see Q1.

### 1.3 Keys for Help

`ghostty_config_trigger(cfg, "action", len)` (`include/ghostty.h:1154`, `src/config/CApi.zig:104`) returns the trigger of one action; empty if unbound. Wrappers: `keyboardShortcut(for:)` (`Ghostty.Config.swift:114`, used at `Sidebar.swift:188`) and `KeyboardShortcut.keyList` (`Helpers/Extensions/KeyboardShortcut+Extension.swift:4`, used at `Features/Command Palette/TerminalCommandPalette.swift:133`). No C call lists all bindings, so Help keeps a fixed list (group, label, action) and asks Ghostty for each key. Actions checked in `src/input/Binding.zig`: new_tab, new_window, close_surface, close_tab, close_window, undo, goto_tab:N, previous_tab, next_tab, toggle_fullscreen, new_split, goto_split, resize_split, equalize_splits, toggle_split_zoom, clear_screen, start_search, navigate_search, increase/decrease/reset_font_size, jump_to_prompt, toggle_command_palette, reload_config. Viewer keys (cmd+B/E/S) are not Ghostty bindings: table at `Features/Tarn/ViewerWebView.swift:16`; Help reads it (shared constant), source "tarn".

### 1.4 Mockup values against `src/config/Config.zig`

Wrong or misleading (all others match name, type, default and values):

| Option | Problem |
|---|---|
| cursor-style-blink | default is `null` (line 902), not true; explicit `true` ignores DEC mode 12 |
| macos-option-as-alt | default is `null` (3527): true on US layouts, false elsewhere; mockup says false; add "(default)" entry |
| notify-on-command-finish | action defaults to bell only (1228), threshold 5 s (1265); help text says "notify" |
| background-blur | accepts bool, radius, `macos-glass-regular|clear` (9948); checkbox covers bool only; show read-only text for others |
| font-family | repeatable (177): the writer must emit `font-family = ""` before the value, else the tarn font is only a fallback |
| undo-timeout | duration (2733); a value outside the list (7s) needs a custom entry |
| window-padding-x | value `N` or `L,R`, default 2,2 (2006); unreadable |
| theme | `?Theme` (601); names from `<Resources>/ghostty/themes` and `~/.config/ghostty/themes` (`src/config/theme.zig:20`) |

### 1.5 Analogs (licenses via `gh api`, 2026-10-25)

| Project | License | Use |
|---|---|---|
| chlee1001/chostty PR 24 (`Features/Settings/ConfigEditor/*`: ConfigDocument, ConfigSchema, ThemeCatalog, tests) | MIT | read before slices A and C; copy with header and `THIRD_PARTY.md` entry |
| alxhill/ghostty `ah/config-ui` (Modified view, reset, writes to the file that sets the option) | MIT | behaviour match for "set in tarn" plus Reset |

Prior art for a side file loaded after the user's config: none found; that part is ours.

Atomic write: `createDirectory(withIntermediateDirectories: true)` for `~/.config/tarn` (base `$XDG_CONFIG_HOME` if set, as `file_load.defaultXdgPath` does), then `Data.write(to:options: .atomic)` (temp file, then rename).

## 2. Architecture

```
SettingsView: Tabs | Appearance | Terminal | Windows | Help
   | set / reset                    ^ effective value, set-in-tarn
   v                                |
GhosttyOptionStore --reads--> GhosttyOptionReader (ghostty.config)
   | writes TarnConfigFile
   v
~/.config/tarn/ghostty.conf --reloadConfig()--> Ghostty.App --> .ghosttyConfigDidChange
```

All new types are in `Features/Tarn/`.

| Type | Job |
|---|---|
| `TarnConfigFile` | path; parse to ordered entries plus verbatim unknown lines; set, remove, serialize; atomic save; `load(into:)` |
| `GhosttyOption` | catalog row (key, kind, default, values, help, section): the mockup `GHOSTTY` table as data |
| `GhosttyOptionReader` | effective value through `ghostty_config_get`; nil if unreadable |
| `GhosttyOptionStore` | `@MainActor` model; set (equal to default removes the line), reset; save, then `reloadConfig()`; refresh on `.ghosttyConfigDidChange`; re-read the file before each save and merge by key |
| `KeyReference` | Help list and key text via `keyboardShortcut(for:)?.keyList` |
| `TarnSettings.swift` | window and sidebar; panes split into `GhosttyOptionsPane.swift`, `HelpPane.swift` |

File format: header comment (what the file is, "delete a line to give the option back"), then `key = value`, one per line, catalog order. Values with edge spaces, quotes or backslashes are quoted and escaped; the Ghostty round-trip test proves it. Hand-written unknown lines are kept. Choice and bool controls write at once; number and text on commit (Tab, Return); sliders on release, debounced 300 ms. Tab style stays in `UserDefaults`.

## 3. Slices

| Slice | Owns | Done when |
|---|---|---|
| A. Config file | `TarnConfigFile.swift`, `Tests/Tarn/TarnConfigFileTests.swift`; one call in `Ghostty.Config.swift`; architecture row 12 | tests green; a hand-written tarn file changes font-size in a running Debug app after menu Reload |
| B. Catalog, reader | `GhosttyOption.swift`, `GhosttyOptionReader.swift`, `Tests/Tarn/GhosttyOptionTests.swift` | catalog defaults equal Zig defaults (after 1.4 fixes); unreadable keys marked |
| C. Options panes | `GhosttyOptionStore.swift`, `GhosttyOptionsPane.swift`; section enum in `TarnSettings.swift` | S7-S10, S12 in the real window |
| D. Help | `KeyReference.swift`, `HelpPane.swift`; key table in `ViewerWebView.swift` | S11 in the real window |

Order: A, B, then C and D in parallel (D adds its case to the section enum after C merges). Each under 400 changed lines.

## 4. Unit tests (`macos/Tests/Tarn/`)

The directory is injectable (`TarnConfigFile.directory`); tests never touch the real `~/.config/tarn`.

| Test | Proves |
|---|---|
| writer round-trip | serialize then parse is identical; comments and unknown lines survive; spaces, quotes, `#`, backslash, empty value |
| Ghostty reads it | `Ghostty.Config(at:)` plus our load; `ghostty_config_get` returns the value (covers quoting) |
| precedence | user `font-size = 12`, tarn `16`: effective 16; a `config-file` include with 10 loses; no tarn file: user value, no error |
| font-family | user `A`, tarn `B`: effective list is only B |
| Reset | removes only that line; empty file loads; user value returns |
| set to default | removes the line |
| atomic save | failed write leaves the old file intact and reports an error |
| catalog | defaults match Zig; every key readable or marked; every Help action gives a trigger in a default config |

## 5. Acceptance (mockup checks)

| Check | Status | Verified by |
|---|---|---|
| S1 cmd+, opens; S3 Escape closes | exists (`showTarnSettings:`, `cancel`) | run app |
| S2, S5, S6 tab style | exists | switch, relaunch |
| S4, S4a-c tab bar | outside S4 | none |
| S7 section shows its options only | C | open Appearance, count rows |
| S8 mark "set in tarn" and applies | C | font-size 16; open terminal redraws without restart |
| S9 file lists changed options only | C | `cat` of the file equals the Windows-pane preview |
| S9a drag-handle never hides dots | C | set never; dots gone in an open split |
| S10 Reset | C | line and mark gone, user value returns |
| S11 Help shows keys in effect | D | user file `keybind = cmd+shift+w=close_tab`, reload, Help shows it |
| S12 survive restart | A | quit, start; font-size still 16 |

App check: launched Debug build, a screenshot per check, file content.

## 6. Ghostty provides / we add

| Need | Ghostty provides | We add |
|---|---|---|
| Parse, validate | config parser, diagnostics | nothing; controls give valid values only |
| Load order | `load_file`, `load_recursive_files`, `finalize` | one call in `loadConfig` |
| Apply to windows | `reloadConfig`, `ghostty_app_update_config`, `.ghosttyConfigDidChange` | call after a write |
| Effective value | `ghostty_config_get` (most keys) | reader; "set in tarn" from our file |
| Keys in effect | `ghostty_config_trigger`, `keyList` | action list and labels |
| Open user file | `ghostty.openConfig()` (button stays) | none |
| Theme list | theme directories | directory listing |
| Side file, atomic write | nothing | `TarnConfigFile` |

## 7. Risks

| Risk | Handling |
|---|---|
| Five options unreadable | Q1 |
| Tarn `font-family` only a fallback | two-line write plus test |
| Bad value in the file (hand edit, removed theme) makes Ghostty show a config error | controls give valid values; theme picker lists installed themes |
| Slider drag reloads often | write on release, 300 ms debounce |
| `ghostty.config` replaced asynchronously | refresh on `.ghosttyConfigDidChange`, not after `reloadConfig()` returns |

## 8. Questions

Q1. Current value of theme, font-family, window-padding-x, cursor-style-blink, macos-option-as-alt when the user's own file sets it (the C API cannot return it).
- A. Show the default and the note "your Ghostty config may set this". Cheap; the control can show a stale value, but a change still wins.
- B. Scan the user's files for these five keys. Shows the truth; a second reader, which "no parallel config parser" forbids without your yes.
- C. Leave these five to Ghostty Config. Honest; loses theme and font, the most wanted.
- Recommendation: A first; B if it bites.

Q2. `macos-titlebar-style = tabs` with the tarn sidebar is untested. A: keep, test in slice C, hide the value if broken. B: remove now. Recommendation: A.

Q3. Mockup fixes from 1.4 (blink default, option-as-alt default, blur read-only case, notify text). A: fix the mockup and `check.py` first (project rule "mockup first"). B: fix in the app only. Recommendation: A.
