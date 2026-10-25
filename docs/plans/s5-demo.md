# Plan: S5 browser demo

Status: draft for review, branch `s5-demo`. Date: 2026-10-25.
Canon: `docs/spec.md`; look and behavior: `docs/mockups/tarn.html` (1700 lines, KEYS at line 1463, GHOSTTY settings at 1433, `check.py` 116 checks).
User words: a storefront people use before downloading, and the place where new features are tried first. It must feel like the real terminal.

## 1. Goal and scope

- In: the mockup becomes `demo/`, a static site. Each terminal pane is a real terminal emulator fed by a simulated shell. Every key in the Help page (KEYS) works. Every setting in the settings window applies live. Workspaces, viewer (markdown, mermaid, code), drag-and-drop zones, agent states, permission card.
- Out: any backend, any network call except loading our own static files, publishing (GitHub Pages is later, not now), real PTY, touch-first UI.
- Rule: the demo is a living mockup. A new feature lands here first, then in Swift.

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
| Options we need | `fontSize`, `fontFamily`, `theme`, `cursorStyle` (block/underline/bar), `cursorBlink`, `scrollback`, `allowTransparency` (lib/interfaces.ts) | all of them, plus `letterSpacing`, `lineHeight` |
| Maturity | young (0.x), one author team (Coder). Open bugs that touch us: #203 Alt+key sends no ESC prefix; #192 `attachCustomKeyEventHandler` return value is inverted vs xterm.js; #198 and #207 fractional devicePixelRatio and cell-width seams; #208 render loop redraws every frame (idle CPU); #184/#185 Powerline glyphs; #205 `translateToString` empty cells | stable |

Source: README and `lib/` of the repo, `gh api` and `npm view`, 2026-10-25.

Decision: ghostty-web. Reasons: project rule "Ghostty first"; it is the same VT code as the app, so the demo shows real behavior; the API matches xterm.js, so a fallback costs one import line. Fallback: xterm.js 6.0.0 behind a thin `term-adapter.js` (section 4), switched by one constant. Run a 1-day spike first (slice A, exit test in section 7); if a blocker bug hits (#203, #192, idle CPU with 6 panes), take the fallback and report it.

Workarounds we plan, not rely on: our own keymap handles every shortcut in the capture phase on `document`, before the terminal sees the event (so #192 does not matter); Alt+key we encode ourselves in the adapter (`ESC` + key) until #203 is fixed; pause the render loop of hidden panes (#208) by `display:none` plus `term.dispose` of closed ones.

### 2.2 Simulated shell

Searched: npm and GitHub for in-browser shells with a virtual filesystem.

| Candidate | License | Verdict |
|---|---|---|
| `just-bash` 3.6.0 (vercel-labs, pushed 2026-10-22) | Apache-2.0 | A bash interpreter in TypeScript with an in-memory filesystem. 16 runtime dependencies, 21 MB unpacked, 970 files; browser build not verified. It is a command runner, not a terminal line editor, so we still write prompt, history, tab completion, colors. Too heavy for a storefront page. Keep as a later option for pipes/globs |
| `@wasmos/ash` 0.0.2 | MIT | Early stage, filesystem not confirmed. Rejected |
| xterm.js "fake shell" snippets | n/a | No maintained library found; all are demos |

Decision: write our own small shell, `shell.js` plus `vfs.js`, about 600 lines, no dependencies. We need a fixed set, not bash: tarn-specific output (agent states, `tarn open`) cannot come from a generic interpreter anyway. Marked as "Ready-made: searched, nothing fits" per the Ghostty-first spirit. Re-check `just-bash` if users ask for pipes.

Command set (v1):

| Command | Behavior |
|---|---|
| `ls [-la] [path]`, `cd`, `pwd`, `cat`, `echo`, `clear`, `mkdir`, `touch`, `rm`, `head`, `whoami`, `date`, `help`, `exit` | over the in-memory VFS seeded from the mockup's `FILES`/`TREE` (README.md, docs/*.md) |
| `git status`, `git log`, `git branch` | canned output from the seed, dirty files follow VFS edits from the viewer |
| `tarn open <path>[:line]`, `tarn ls`, `tarn new [name]`, `tarn status` | call the app bus (section 4): open in viewer, list sessions, new workspace, print states |
| `claude` | scripted agent session, see below |
| unknown | `zsh: command not found: x` |

Shell features: prompt like the mockup `promptLine`, line editing (arrows, Home/End, ^A ^E ^U ^K ^W ^C ^L ^D), history (up/down), Tab completion for commands and VFS paths, output with ANSI colors, cwd reported by OSC 7 (so "new tab inherits cwd" works), OSC 133 prompt marks (for jump-to-prompt, cmd+up/down), path:line recognized as links (cmd+click opens the viewer).

`claude` script (`agent-script.js`): a data list of steps `{at ms, text | state | action}`: prints a spinner line and thoughts, sets tab state `working`, edits a file in the VFS (viewer shows the change), raises state `waiting` with the permission card (Allow / Deny, keys y/n), on Allow continues and prints the diff, ends in `done` while the pane is unfocused or `waiting` for the next prompt. Same state machine as the mockup `STATE` (waiting 3, working 2, done 1) and `agentEdit()`/`agentOpensTab()`.

## 3. Repo layout and the fate of docs/mockups

```
demo/
  index.html            shell of the page, import map, no inline logic
  css/                  tarn.css (moved from the mockup), themes.css
  js/                   modules, section 4
  vendor/               ghostty-web (js + wasm), markdown-it, highlight.js, mermaid; pinned, license files kept
  fonts/                JetBrains Mono (OFL) and 2 more for the font setting
  test/check.py         moved from docs/mockups, plus new checks
```

- `docs/mockups/tarn.html` is deleted when the demo passes every old check (`git mv` check.py, keep history). Until then both exist. Docs that link to the mockup (`docs/plans/s2-files.md`, spec) get the new path in the same commit.
- No bundler. ES modules + import map; vendor files are committed, pinned by version in `demo/vendor/VERSIONS.md`. The mockup loads libs from CDNs (cdnjs, jsdelivr); the demo vendors them to meet "no network except our assets". Mermaid (about 3 MB) loads lazily on first diagram.
- Build step optional later: `esbuild` single command for a minified release, not needed to develop.
- Serving for tests: `python -m http.server` in `demo/` (ES modules and WASM do not load from `file://`; `check.py` starts the server itself).

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
| `palette.js`, `find.js` | command palette (⇧⌘P), find (⌘F/G) | palette, search |
| `main.js` | boot order, wiring | app delegate |

Data flow: key event -> `keymap.js` (capture phase on `document`) -> `bus` command (`pane.split`, `tab.new`, ...) -> `state.js` mutates -> subscribers re-render (`layout`, `sidebar`). Shell typing: engine `onData` -> `shell.js` -> output string -> `adapter.write`. Shell command `tarn open` -> `bus 'viewer.open'` -> `viewer.js`. Settings change -> `config.js` -> `apply` fan-out: `term-adapter.applyOptions` (font, size, theme, cursor, blink), CSS variables (opacity, padding, split dimming, tab style, titlebar style, drag-handle), `layout`/`sidebar` re-render.

Setting to mechanism (all 11 appearance + 6 terminal + 5 windows options of the mockup):

| Setting | How it applies live |
|---|---|
| theme, window-theme | engine `theme` + CSS vars; 3 themes in v1, add more as data |
| font-family, font-size | engine option, then refit all panes; fonts vendored; ⌘= ⌘- ⌘0 per pane |
| background-opacity, background-blur | `allowTransparency` + rgba theme background; `backdrop-filter` on the window over a wallpaper image |
| window-padding-x | CSS padding on the pane box, then refit |
| unfocused-split-opacity | CSS var on `.pane:not(.focused)` |
| cursor-style, cursor-style-blink | engine options; shell prompt shows bar like shell integration |
| macos-titlebar-style, tab style | CSS classes on the window frame |
| copy-on-select, mouse-hide-while-typing, clipboard-paste-protection | selection hook, CSS cursor, confirm dialog on multi-line paste |
| macos-option-as-alt | adapter key encoding |
| link-url, notify-on-command-finish | link provider on/off; in-page toast when an unfocused pane finishes |
| window-save-state, confirm-close-surface, window-inherit-working-directory, undo-timeout, drag-handle | `state.js` persistence, close dialog, cwd copy, undo timer, handle CSS |

## 5. Slices and ownership

Three workers, after a short slice 0 by one worker (skeleton and contracts). A slice owns its files; nobody edits another's file, they ask through `bus` names listed in `demo/js/CONTRACT.md` (written in slice 0, 1 page: bus event names, state shape, config keys).

| Slice | Who | Owns | Depends | Done when |
|---|---|---|---|---|
| 0 Skeleton | worker 1 | `index.html`, `css/`, `vendor/`, `bus.js`, `state.js`, `config.js` (schema only), `main.js`, `CONTRACT.md`, server in `check.py` | none | page boots, one ghostty-web terminal echoes typed keys, spike verdict on the engine |
| A Terminal and shell | worker 1 | `term-adapter.js`, `term-pane.js`, `shell.js`, `commands/`, `vfs.js`, `agent-script.js` | 0 | typing, history, completion, `tarn`, `claude` script run in a pane; shell unit tests (Node, no browser) |
| B Layout and chrome | worker 2 | `layout.js`, `tabs.js`, `sidebar.js`, `dnd.js`, `keymap.js` (Tabs, Splits, Terminal groups), `palette.js`, `find.js` | 0 | all mockup layout/sidebar/dnd checks pass on real panes; all non-Viewer KEYS work |
| C Viewer and settings | worker 3 | `viewer.js`, `markdown.js`, `settings.js`, `config.js` (apply fan-out), `keymap.js` Viewer group, fonts, themes | 0 | viewer checks pass; every setting applies live |

`keymap.js` is split by file section: B owns the file, C sends a PR-style patch for the Viewer group through B's worker (or lands it after B). Merge order: 0, then A/B/C in any order, then a final integration commit by one worker (wires mockup seed, removes `docs/mockups/tarn.html`).

Estimate: slice 0 about 1 day, A/B/C about 3 to 4 days each in parallel.

## 6. Test plan (Playwright, `demo/test/check.py`)

- Keep all 116 mockup checks; selectors that read fake terminal DOM change to the real pane container (`.pane[data-id]`). Run: `uv run --with playwright python -I demo/test/check.py`.
- Reading terminal text: expose `window.__tarn.screen(paneId)` that returns the buffer text (engine `buffer.active`), so tests assert on what the user sees. Also take screenshots of the canvas for the visual checks (canvas is not DOM).
- New checks:
  1. Typing: type `ls`, Enter; screen contains seeded names; `cd docs`, `pwd`; Up recalls; Tab completes; ^C, ^L, ^U work; `clear`.
  2. `tarn open README.md` opens the viewer; `tarn ls`, `tarn new` change sidebar.
  3. `claude`: states go working, waiting (card visible, sidebar dot orange), press `y`, then done; file changed in viewer.
  4. Every shortcut: table-driven from `keymap.js` data. For each row of KEYS, dispatch the keys, assert the effect (tab count, split count, zoom class, font size value, find bar visible, palette visible, ...). A test fails if a KEYS row has no test entry.
  5. Every setting: table-driven from the schema. For each key set a value through the settings UI, assert the effect (computed style, engine option via `__tarn.term(id).options`, class on the window). Also assert persistence after reload.
  6. No network: `page.route('**/*')` aborts anything not from the local origin; test fails on any blocked request.
  7. Idle CPU: after 10 s idle with 6 panes, rAF-driven work under a budget (count of canvas draws via a hook); guards #208.
  8. Size: transfer size of first load (without mermaid) under budget in section 8.
- Shell logic additionally has Node unit tests (`node --test demo/test/shell.test.mjs`), no browser, fast.
- CPU rule: tests run with `nice -n 10`, one browser, workers 1.

## 7. Acceptance list

1. Open `demo/index.html` through any static server: no console errors, no external request.
2. Click a pane and type: the shell answers; the cursor, selection, scrollback, and mouse wheel behave like a terminal.
3. Every row of the Help page works as described.
4. Every option of the settings window changes the page at once, survives reload, and "reset" restores defaults.
5. Workspaces: create, rename, delete, drag a tab between them, rollup dot shows the highest state.
6. Splits: split, close, zoom, equalize, resize, focus by direction, drag a pane to a zone (Rectangle-style).
7. Viewer: markdown rendered, mermaid diagram drawn, code with line numbers, view/source, save writes to the VFS, `tarn open` and cmd+click on `path:line` open it.
8. `claude` script runs to the end through the permission card.
9. First load size and idle CPU within section 8 budgets.
10. All checks green; mockup checks included.

## 8. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Browser reserves ⌘T, ⌘N, ⌘W, ⇧⌘W, ⌘1-9, ⌘D and cannot be overridden by `preventDefault` in a normal tab | Core of "every key works" fails in Chrome/Safari | See question 1. Keyboard Lock API (`navigator.keyboard.lock`, Chromium only) works in full screen; ⌘↩ already is "Full screen" |
| ghostty-web is 0.x with open bugs (#203, #192, #198, #207, #208) | wrong input or blur at some zoom, idle CPU | spike first; adapter workarounds; xterm.js fallback behind adapter |
| Performance with many panes (each has a canvas, WASM instance) | slow page | hide and pause inactive tabs, limit demo to 8 panes, measure in check 7 |
| Size | slow first load | budget: first load under 1.5 MB gzip without mermaid (WASM about 400 KB, fonts subset, markdown-it, hljs core + 6 languages); mermaid lazy |
| Mobile | no hardware keys, small screen | out of scope v1; show a notice "best on desktop" below 800 px width; touch input via engine only if cheap |
| Canvas text is not in the DOM | accessibility, tests | `__tarn.screen()` for tests; a11y later (ghostty-web #187 open) |
| Drift between demo and app | demo lies | CONTRACT section lists app source for each module; checklist item in every Swift feature PR: "demo updated or marked not yet" |
| Licenses of vendored files | legal | MIT/Apache/ISC/BSD/OFL only; keep license files in `vendor/` and `fonts/`; NOTICE entry |
| WASM and strict CSP on GitHub Pages | none by default | Pages sets no CSP; ghostty-web #188/#196 concern strict CSP only |

## 9. Questions

1. Browser-reserved keys (⌘T, ⌘N, ⌘W, ⌘1-9, ...). Options: (a) accept that these work only in full screen (Keyboard Lock, Chromium) and give a second binding that always works (for example ⌥ plus the key, shown in Help as "in the browser"); (b) only alternate bindings, Help shows both; (c) a browser extension or installed PWA only. Recommendation (a): full screen gives the real keys, the page tells the user once ("press ⌘↩ for the real shortcuts").
2. Engine: ghostty-web with xterm.js fallback after a 1-day spike (recommended) or xterm.js from the start. Cost of ghostty-web: 0.x bugs; gain: same parser as the app.
3. Shell: own 600-line shell (recommended) or `just-bash` (Apache-2.0, 21 MB, 16 dependencies) for real pipes and globs. Recommend own; revisit if visitors ask.
4. Vendoring: commit libraries into `demo/vendor/` (recommended, simple, offline) or add npm + a one-command build.
5. What happens to the mockup: delete `docs/mockups/tarn.html` after the demo passes (recommended) or keep both for a release.
6. Mobile: notice only (recommended) or invest in a touch layout later.
7. Fonts for the font-family setting: ship JetBrains Mono + 2 more (Fira Code, Source Code Pro, all OFL) so the setting has visible effect; the user's own installed fonts via `local()` also work. Recommend ship 3.
