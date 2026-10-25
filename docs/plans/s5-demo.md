# Plan: S5 browser demo

Status: draft for review, branch `s5-demo`. Date: 2026-10-25.
Canon: `docs/spec.md`; look and behavior: `docs/mockups/tarn.html` (1700 lines, KEYS at line 1463, GHOSTTY settings at 1433, `check.py` 116 checks).
## 1. Goal and scope

- In: the mockup becomes `demo/`, a static site. Each terminal pane is a real terminal emulator fed by a simulated shell. Every key in the Help page (KEYS) works. Every setting in the settings window applies live. Workspaces, viewer (markdown, mermaid, code), drag-and-drop zones, agent states, permission card.
- Out: backend, network calls beyond our static files, publishing (Pages is later), real PTY, touch UI.
- Rule: a new feature lands in the demo first, then in Swift.

## 2. Research (facts with sources, checked 2026-10-25)

### 2.1 Terminal engine

| | ghostty-web | xterm.js |
|---|---|---|
| Repo | github.com/coder/ghostty-web | github.com/xtermjs/xterm.js |
| License | MIT | MIT |
| Latest release | v0.4.0, 2025-12-09 (npm `ghostty-web@0.4.0`, modified 2026-06-28) | `@xterm/xterm` 6.0.0, 2025-12-22 |
| Activity | last push 2026-10-15, about 3.0k stars, open PRs and issues through #208 | very active, years of use |
| Size | about 400 KB WASM (README); npm unpacked 2.2 MB | npm unpacked 5.9 MB (source and maps; shipped JS is far smaller) |
| Engine | Ghostty's own VT parser compiled to WASM, canvas renderer, xterm.js-compatible API (`init()`, `new Terminal`, `open`, `write`, `onData`, `onResize`, `loadAddon`, FitAddon in `lib/addons/`) | hand-written JS parser, DOM/canvas/WebGL renderers |
| Options | `fontSize`, `fontFamily`, `theme`, `cursorStyle`, `cursorBlink`, `allowTransparency` (lib/interfaces.ts) | all, plus `letterSpacing`, `lineHeight` |
| Maturity | young (0.x), one author team (Coder). Open bugs that touch us: #203 Alt+key sends no ESC prefix; #192 `attachCustomKeyEventHandler` return value is inverted vs xterm.js; #198 and #207 fractional devicePixelRatio and cell-width seams; #208 render loop redraws every frame (idle CPU); #184/#185 Powerline glyphs; #205 `translateToString` empty cells | stable |

Decision: ghostty-web (sources: repo README, `lib/`, `gh api`, `npm view`, 2026-10-25). It is the project rule and the same parser as the app; the API matches xterm.js, so the fallback is one import line behind `term-adapter.js`. Spike first (slice 0); on a blocker (#203, #192, idle CPU with 6 panes) switch and report.

Workarounds: our keymap handles shortcuts in the capture phase on `document` (so #192 is moot); Alt+key encoded in the adapter (#203); hidden panes get `display:none` and closed ones `dispose` (#208).

### 2.2 Simulated shell

Searched: npm and GitHub for in-browser shells with a virtual filesystem.

`just-bash` 3.6.0 (vercel-labs, Apache-2.0, pushed 2026-10-22): bash interpreter with in-memory FS, but 16 dependencies, 21 MB unpacked, browser build unverified, and no line editor or tarn-specific output. `@wasmos/ash` 0.0.2 (MIT): early, FS unconfirmed. No maintained xterm.js fake-shell library found.

Decision: own small shell, `shell.js` plus `vfs.js`, about 600 lines, no dependencies. Tarn output (agent states, `tarn open`) cannot come from a generic interpreter anyway. Re-check `just-bash` if users want pipes.

Commands: `ls [-la]`, `cd`, `pwd`, `cat`, `echo`, `clear`, `mkdir`, `touch`, `rm`, `head`, `whoami`, `date`, `help`, `exit` over an in-memory VFS seeded from the mockup `FILES`/`TREE`; `git status|log|branch` canned from the seed; `tarn open <path>[:line]`, `tarn ls`, `tarn new [name]`, `tarn status` through the bus; `claude` (below); unknown gives `zsh: command not found`.

Shell features: line editing (arrows, ^A ^E ^U ^K ^W ^C ^L ^D), history, Tab completion of commands and paths, ANSI colors, OSC 7 cwd (new tab inherits it), OSC 133 prompt marks (cmd+up/down), `path:line` links (cmd+click opens the viewer).

`claude` script (`agent-script.js`): timed steps `{at, text | state | action}`: spinner and thoughts, tab state `working`, a VFS file edit (viewer shows it), `waiting` with the permission card (Allow/Deny, keys y/n), then the diff and `done`. Same state machine as the mockup `STATE`, `agentEdit()`, `agentOpensTab()`.

## 3. Repo layout and the fate of docs/mockups

```
demo/
  index.html            shell of the page, import map, no inline logic
  css/                  tarn.css (moved from the mockup), themes.css
  js/                   modules, section 4
  vendor/               ghostty-web (js + wasm), markdown-it, highlight.js, mermaid; pinned, license files kept
  test/check.py         moved from docs/mockups, plus new checks
```

- `docs/mockups/tarn.html` goes away (`git mv` keeps `check.py` history) once the demo passes every old check; links in `s2-files.md` and the spec change in the same commit.
- No bundler: ES modules and an import map. Vendor files are committed and pinned in `vendor/VERSIONS.md`. The mockup loads libs from CDNs; the demo vendors them (no network rule). Mermaid (about 3 MB) loads lazily.

## 4. Module map

Mirrors the app (`macos/Sources/Features/Tarn/`): one JS module per Swift area.

| Module | Owns | App counterpart |
|---|---|---|
| `bus.js` | tiny event emitter and command registry (`bus.emit('open', {...})`, `bus.on`); the only coupling between modules | control socket |
| `state.js` | store: workspaces, tabs, layout trees, closed-stack for undo (5 s), `localStorage` persistence | session registry |
| `config.js` | settings schema (from mockup `GHOSTTY`), values, `apply(key)` fan-out, config text export | Ghostty config |
| `vfs.js` | in-memory filesystem, seed, watch events | disk |
| `shell.js` | line editor, parser, commands (`commands/*.js`), prompt, OSC output | zsh |
| `agent-script.js` | scripted `claude` session, states, permission card trigger | the agent + hooks |
| `term-adapter.js` | wraps ghostty-web: create, fit, write, focus, dispose, `applyOptions`; the only file that imports the engine | Ghostty surface |
| `term-pane.js` | one pane: adapter + shell + padding box + drag handle + find bar | SurfaceView |
| `layout.js` | split tree (split, close, zoom, equalize, resize, focus by direction), render | SplitTree |
| `dnd.js` | drag sources, drop zones (Rectangle-style, `windows-workspaces.md` 3a), drop preview | drag and drop |
| `sidebar.js` | workspaces, tab list, rollup state dots, tab hover card, menus | Sidebar |
| `tabs.js` | tab actions: new, close, move, undo, go to N | tab model |
| `viewer.js` | viewer pane: file tabs, tree, view/source, save, links | viewer |
| `markdown.js` | markdown-it + highlight.js + mermaid lazy | markdown panel |
| `settings.js` | settings window UI from `config.js` schema, Help page from `keymap.js` | settings window |
| `keymap.js` | KEYS table as data (single source for Help and handler), capture-phase dispatcher | key bindings |
| `palette.js`, `find.js` | command palette, find | palette, search |
| `main.js` | boot order, wiring | app delegate |

Data flow: key event -> `keymap.js` (capture phase on `document`) -> `bus` command -> `state.js` mutates -> `layout`/`sidebar` re-render. Shell: engine `onData` -> `shell.js` -> `adapter.write`; `tarn open` -> `bus` -> `viewer.js`. Settings: `config.js` -> `apply` fan-out.

Settings apply through `config.js` fan-out: engine options (font, size, theme, cursor, blink, `allowTransparency` for opacity), CSS variables (padding then refit, split dimming, titlebar and tab style, drag-handle, blur by `backdrop-filter`), and state hooks (copy-on-select, paste confirm, option-as-alt in the adapter, links, notifications as toasts, undo timeout, cwd inherit, save state, close confirm). One schema row per option, taken from the mockup `GHOSTTY`.

## 5. Slices and ownership

Three workers, after a short slice 0 by one worker (skeleton and contracts). A slice owns its files; nobody edits another's file, they ask through `bus` names listed in `demo/js/CONTRACT.md` (written in slice 0, 1 page: bus event names, state shape, config keys).

| Slice | Who | Owns | Depends | Done when |
|---|---|---|---|---|
| 0 Skeleton | worker 1 | `index.html`, `css/`, `vendor/`, `bus.js`, `state.js`, `config.js` (schema only), `main.js`, `CONTRACT.md`, server in `check.py` | none | page boots, one ghostty-web terminal echoes typed keys, spike verdict on the engine |
| A Terminal and shell | worker 1 | `term-adapter.js`, `term-pane.js`, `shell.js`, `commands/`, `vfs.js`, `agent-script.js` | 0 | typing, history, completion, `tarn`, `claude` script run in a pane; shell unit tests (Node, no browser) |
| B Layout and chrome | worker 2 | `layout.js`, `tabs.js`, `sidebar.js`, `dnd.js`, `keymap.js` (Tabs, Splits, Terminal groups), `palette.js`, `find.js` | 0 | all mockup layout/sidebar/dnd checks pass on real panes; all non-Viewer KEYS work |
| C Viewer and settings | worker 3 | `viewer.js`, `markdown.js`, `settings.js`, `config.js` (apply fan-out), `keymap.js` Viewer group, fonts, themes | 0 | viewer checks pass; every setting applies live |

`keymap.js`: B owns the file; C adds the Viewer group after B lands. Order: 0, then A/B/C, then one integration commit (seed, mockup removal).

## 6. Test plan (Playwright, `demo/test/check.py`)

- All 116 mockup checks stay; fake-terminal selectors move to the real pane. Run: `uv run --with playwright python -I demo/test/check.py` (it starts a static server; modules and WASM do not load from `file://`).
- Canvas text is not DOM: `window.__tarn.screen(paneId)` returns the buffer text; screenshots cover visuals.
- New checks: (1) typing, history, Tab, ^C ^L ^U, `clear`; (2) `tarn open/ls/new`; (3) `claude` goes working, waiting (card, orange dot), `y`, done, file changed in viewer; (4) every shortcut, table-driven from `keymap.js` data, fails if a KEYS row has no test; (5) every setting, table-driven from the schema, effect checked and kept after reload; (6) any non-local request fails the run; (7) idle draw count with 6 panes (guards #208); (8) first-load size budget.
- Shell logic also has Node unit tests (`node --test`). Tests run under `nice -n 10`, one browser.

## 7. Acceptance

1. Static server, no console error, no external request.
2. Typing in a pane gets shell answers; selection, scrollback, wheel work.
3. Every Help row works; every setting applies at once, persists, and resets.
4. Workspaces, splits, zones, viewer (markdown, mermaid, code, save, `tarn open`, `path:line` click) work as in the mockup.
5. `claude` script runs through the permission card.
6. All checks green, size and idle CPU within budget.

## 8. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Browser reserves ⌘T, ⌘N, ⌘W, ⇧⌘W, ⌘1-9, ⌘D and cannot be overridden by `preventDefault` in a normal tab | Core of "every key works" fails in Chrome/Safari | See question 1. Keyboard Lock API (`navigator.keyboard.lock`, Chromium only) works in full screen; ⌘↩ already is "Full screen" |
| ghostty-web is 0.x with open bugs (#203, #192, #198, #207, #208) | wrong input or blur at some zoom, idle CPU | spike first; adapter workarounds; xterm.js fallback behind adapter |
| Many panes (canvas plus WASM each) | slow page | pause hidden tabs, cap at 8 panes, idle check |
| Size | slow load | under 1.5 MB gzip without mermaid (WASM about 400 KB, subset fonts, hljs core plus 6 languages) |
| Mobile | no hardware keys | out of scope; notice below 800 px |
| Drift between demo and app | demo lies | every Swift feature PR checks: demo updated or marked not yet |
| Vendored licenses | legal | MIT/Apache/ISC/BSD/OFL only, license files kept, NOTICE entry |

## 9. Questions

1. Browser-reserved keys (⌘T, ⌘N, ⌘W, ⌘1-9, ...). Options: (a) accept that these work only in full screen (Keyboard Lock, Chromium) and give a second binding that always works (for example ⌥ plus the key, shown in Help as "in the browser"); (b) only alternate bindings, Help shows both; (c) a browser extension or installed PWA only. Recommendation (a): full screen gives the real keys, the page tells the user once ("press ⌘↩ for the real shortcuts").
2. Engine: ghostty-web, xterm.js fallback after a 1-day spike (recommended), or xterm.js at once. Cost: 0.x bugs; gain: same parser as the app.
3. Shell: own (recommended) or `just-bash` for real pipes; revisit on demand.
4. Smaller choices, recommended: commit libraries into `demo/vendor/` (no npm); delete the mockup after the demo passes; mobile gets a notice only; ship 3 OFL fonts (JetBrains Mono, Fira Code, Source Code Pro) so the font setting is visible.
