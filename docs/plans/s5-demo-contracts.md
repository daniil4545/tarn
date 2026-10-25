# S5 demo: research, contracts, tables

Companion of `docs/plans/s5-demo.md`. Slice 0 turns sections 4 and 6 into `demo/js/CONTRACT.md` and contract tests.

## 1. Research (checked 2026-10-25, `gh api`, `npm view`, repo README and `lib/`)

| | ghostty-web | xterm.js |
|---|---|---|
| Source | github.com/coder/ghostty-web, MIT | github.com/xtermjs/xterm.js, MIT |
| Release | v0.4.0, 2025-12-09; npm modified 2026-06-28; push 2026-10-15; about 3.0k stars | `@xterm/xterm` 6.0.0, 2025-12-22 |
| Size | about 400 KB WASM (README), npm unpacked 2.2 MB | npm unpacked 5.9 MB (sources, maps) |
| API | xterm-compatible: `init()`, `Terminal`, `open`, `write`, `onData`, `onResize`, FitAddon (`lib/addons/fit.ts`); options `fontSize`, `fontFamily`, `theme`, `cursorStyle`, `cursorBlink`, `scrollback`, `allowTransparency` | all, plus `letterSpacing`, `lineHeight` |
| Open issues that touch us | #203 Alt+key sends no ESC; #192 custom key handler return inverted; #205 `translateToString` empty cells; #198/#207 fractional DPR seams; #208 render loop redraws every frame; #184 Powerline glyphs; #187 no screen reader | stable |

Shell candidates: `just-bash` 3.6.0 (Apache-2.0, pushed 2026-10-22; 16 dependencies, 21 MB, browser build not verified, no line editor); `@wasmos/ash` 0.0.2 (MIT, early). No maintained fake-shell library for xterm.js found. Prior art searched: npm and GitHub; found nothing to reuse. Own shell: pipes and redirects print `not supported in the demo`.

## 2. Spike (slice 0): pass/fail, any fail means the xterm.js fallback

| # | Item | Pass when |
|---|---|---|
| 1 | Load as ES module and WASM from a static server, no bundler | `init()` resolves, a terminal draws |
| 2 | Read screen text (#205) | `buffer` gives full text of a 24x80 screen incl. blanks, cyrillic |
| 3 | Link provider on `path:line` | click on canvas text reports the cell text |
| 4 | Prompt jump | OSC 133 marks readable, or the shell keeps its own prompt rows (then pass) |
| 5 | Selection API | `getSelection()` and a selection event for copy-on-select |
| 6 | Search | buffer search possible by our own scan of the buffer |
| 7 | Keys (#192, #203) | capture-phase handler plus own Alt+key encoding works |
| 8 | Idle cost (#208) | 6 panes, blink off, 0 canvas draws per second |
| 9 | Fractional DPR (#198, #207) | no seams at DPR 1.25 and 2 |
| 10 | Reserved keys | 15-line page: `requestFullscreen()`, `navigator.keyboard.lock()`, log `keydown`; press every KEYS chord in Chrome, Safari, Firefox; the table decides which rows get a fallback chord |

Manual acceptance step (not automatable): real Chrome in full screen, Safari, Russian layout; each KEYS row pressed once; result in the PR.

## 3. Module map (app counterparts at HEAD of s5-demo)

| Module | Role | App counterpart |
|---|---|---|
| `bus.js` | `EventTarget` events plus `Map` commands | `ControlSocket.swift` |
| `state.js`, `workspace.js` | workspaces, tabs, trees, undo | `Sidebar.swift:16` `SidebarModel` |
| `registry.js` | agent state | `SessionRegistry.swift:177`, `AgentSession.handle` `:47` |
| `config.js`, `settings.js` | options, window | `TarnSettings.swift:50`, `:91` |
| `vfs.js` | in-memory files | disk, `FileWatcher.swift` |
| `shell.js`, `commands/` | zsh stand-in | the shell |
| `agent-script.js` | scripted Claude Code | Claude Code plus hook bridge |
| `term-adapter.js`, `term-pane.js` | engine, pane, registry | Ghostty surface |
| `layout.js`, `dnd.js` | tree functions, zones | Ghostty `SplitTree` |
| `sidebar.js`, `tabs.js`, card | sidebar, tab card | `Sidebar.swift:491`, `TabCardPopover.swift:7` |
| `viewer.js`, `viewer-shim.js` | tabs, documents, bridge | `ViewerModel.swift:8`, `ViewerTabs.swift:14`, `FileTree.swift:12` |
| `keymap.js`, `keys/*.js` | dispatcher, rows | menu key bindings |
| `palette.js`, `find.js` | palette, find | Ghostty palette, search |

## 4. Contract: bus, `window.__tarn`

Bus: `bus.cmd(name, payload)` runs the single handler; `bus.on(event, fn)` for events. Payloads:

| Command | Payload | Handler (writer) |
|---|---|---|
| `tab.new`, `tab.close`, `tab.go`, `tab.move` | `{ws?, id?, n?, to?}` | `workspace.js` |
| `pane.split`, `pane.close`, `pane.focus`, `pane.zoom`, `pane.resize`, `pane.equalize`, `pane.undo` | `{id?, dir}` | `workspace.js` |
| `ws.new`, `ws.rename`, `ws.delete` | `{id?, name}` | `workspace.js` |
| `hook` | `{pane, name, event}` (names of spec section 8) | `registry.js` |
| `card.answer` | `{pane, allow}` | `agent-script.js` (then emits `hook`) |
| `viewer.open` | `{path, line?, pane?}` | `viewer.js` |
| `config.set`, `config.reset` | `{key, value}` | `config.js` |
| `vfs.write` | `{path, text, by}` | `vfs.js` |

Events: `state:changed {part}`, `config:changed {key, value}`, `vfs:changed {path, by}`, `pane:output {id}`, `toast {text}`.

`window.__tarn` (read only, never writes state): `snapshot()` frozen copy of all parts (ids `t1`, `w1` kept); `screen(paneId)` buffer text; `linkAt(paneId, text)` cell centre of the first match, for clicks; `term(paneId).options`; `viewer().state()`; `clock.advance(ms)` drives agent script timers; `errors` list of caught errors; `requests` list of fetches. Old checks use it instead of globals `cur`, `wss`, `flat()`, `renderSidebar()`.

## 5. Settings: effect and measure (closes M8)

| Key | Effect in demo | Measure |
|---|---|---|
| theme | engine theme plus CSS vars; themes Dracula, Catppuccin Mocha, Nord from the iTerm2-Color-Schemes set shipped with Ghostty (MIT, THIRD_PARTY entry) | `term(id).options.theme.background` |
| window-theme | auto/system follow `prefers-color-scheme`; light/dark force; ghostty follows terminal bg | `html[data-theme]` |
| font-family | vendored OFL fonts (JetBrains Mono, Fira Code, Source Code Pro) or any `local()` name; unknown name falls back to JetBrains Mono plus a toast | `options.fontFamily`, cell width changes |
| font-size | engine option, refit; Cmd+= Cmd+- Cmd+0 per pane | `options.fontSize`, rows/cols |
| background-opacity, background-blur | rgba bg with `allowTransparency`; blur by `backdrop-filter` over a wallpaper | computed bg alpha, filter |
| window-padding-x | CSS padding on the pane box, refit | computed padding, cols |
| unfocused-split-opacity | CSS var on unfocused panes | computed opacity |
| cursor-style, cursor-style-blink | engine options | `options.cursorStyle` |
| macos-titlebar-style | class on window frame | class |
| copy-on-select | on selection event copy to clipboard | clipboard text via test permission |
| mouse-hide-while-typing | CSS `cursor:none` until mouse move | computed cursor |
| clipboard-paste-protection | confirm dialog on multi-line paste | dialog visible |
| macos-option-as-alt | adapter encodes Alt+key as ESC + key | bytes the shell received |
| link-url | link provider on/off | `linkAt` clickable or not |
| notify-on-command-finish | toast when a command over 3 s (`sleep N`, `claude`) ends in an unfocused pane or hidden page | toast |
| window-save-state | default = always in browser; never = no layout persisted | storage after reload |
| confirm-close-surface | dialog if the pane runs `claude` or `sleep`; always = every close | dialog |
| window-inherit-working-directory | new tab or split gets the focused cwd | shell `pwd` |
| undo-timeout | window of `pane.undo` | undo fails after N s (fake clock) |
| drag-handle | CSS class | handle visibility |

"Reload the Ghostty config" (Shift+Cmd+,) in the demo re-applies stored config and toasts "config reloaded". Help rows that cannot exist in a browser (Cmd+N new window) open a second demo workspace window frame, not a browser window.

Persistence (key `tarn-demo-v1:<part>`; other version or bad JSON gives seed plus toast):

| Part | Survives reload | After "Reset demo" |
|---|---|---|
| config | yes | defaults |
| workspaces, tabs, layout (if save-state allows) | yes | seed (ids `t1`, `w1`) |
| vfs edits | yes | seed |
| shell history | yes (last 200) | cleared |
| scrollback, running `claude`, undo stack | no | no |

## 6. Shell and `claude` details

- `createShell({vfs, emit, write, clock})` is pure over its arguments; Node unit tests run it without browser or engine. Line editor: arrows, Home/End, ^A ^E ^U ^K ^W ^C ^L ^D, history, Tab, wide and Cyrillic characters. cwd goes to the bus by `emit`, not OSC 7.
- Commands: `ls [-la]`, `cd`, `pwd`, `cat`, `echo`, `clear`, `mkdir`, `touch`, `rm`, `head`, `sleep N`, `whoami`, `date`, `help`, `exit`, `git status|log|branch` (canned from the seed, dirty files follow VFS), `tarn open <path>[:line]`, `tarn ls` (row format of spec section 11: `3  tarn  main  permission  2m`, plus `--json`), `tarn new` (Question 2), `claude`. `tarn status` is dropped (not in spec). Unknown: `zsh: command not found: x`.
- `claude`: timed steps through `clock`: spinner, `UserPromptSubmit`, a VFS edit (viewer follows), `PermissionRequest` with the card; the card or typing `y`+Enter in the pane answers; a terminal answer sends no event (spec section 8 "Known limit"), the script continues with `PostToolUse` after its next step, so `permission` stays until then; `Stop` ends in `waiting`. ^C aborts the script and sends `Stop`. One script per pane; two panes run independently, registry keys by pane id.
