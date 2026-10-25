# Plan: S5 browser demo

Status: pass 2, closes review `sr-demo.md` (M1-M13). Branch `s5-demo`. Date 2026-10-25.
Details, contracts, tables: `docs/plans/s5-demo-contracts.md` ("C" below). Canon: `docs/spec.md` (states in section 8), `docs/architecture.md`.

## 1. Goal and scope

- `demo/` is a static site: the tarn window with a real terminal emulator per pane, a simulated shell, every Help (KEYS) row working, every settings option live, workspaces, viewer, drag-and-drop zones, agent states, permission card.
- It serves two jobs: a storefront before download, and the first place a new feature is tried. It replaces `docs/mockups/` (living mockup moves to `demo/`).
- Out: backend, network beyond our own static files, real PTY, touch UI, publishing (Pages comes later).
- Supported browsers: current Chrome and Edge (full screen plus Keyboard Lock gives the real keys); Safari and Firefox work with the fallback keys.

## 2. Choices (research and sources in C section 1)

| Need | Choice | Why |
|---|---|---|
| Engine | ghostty-web 0.4.0 (MIT, coder/ghostty-web), `term-adapter.js` hides it; fallback xterm.js 6.0.0 (MIT) | same VT parser as the app; 0.x risk bounded by a pass/fail spike (C section 2) |
| Shell | own, pure function `createShell({vfs, emit, write, clock})`, about 600 lines | no maintained lib fits (just-bash: 16 deps, 21 MB, browser build unverified) |
| Viewer | the app's built bundle `macos/Sources/Features/Tarn/Viewer/tarn-viewer.{html,js,css}` (source `viewer-web/`: markdown-it, highlight.js, mermaid 12, CodeMirror), in an iframe with a `window.webkit.messageHandlers.tarn` shim | one renderer for demo and app; no second markdown stack. Shim replaces `ViewerModel.swift` role in `viewer.js` |
| Build | none: ES modules, import map, vendored files | static hosting, no toolchain |

## 3. State model (closes M1, M2, M3)

One store, `state.js`. Each part has one writer; everything else sends a command on the bus and reads a frozen snapshot.

| Part | Single writer | Source of input | Canon |
|---|---|---|---|
| `registry` (agent sessions) | `registry.js`, transition table of spec section 8 | hook events only (`UserPromptSubmit`, `PermissionRequest`, `PostToolUse`, `Stop`, `SessionEnd`) | `SessionRegistry.swift:6-44`, `AgentSession.handle` |
| `workspaces`, tabs, layout trees | `workspace.js` (in `state.js`) | commands `tab.*`, `pane.*`, `ws.*` | architecture sidebar model |
| `undo` stack | `workspace.js` | close commands; window = config `undo-timeout` | `ExpiringUndoManager` |
| `config` | `config.js` | settings UI, reset | `TarnSettings.swift` |
| `vfs` | `vfs.js` | shell commands, viewer save, agent script | disk |

Rules: `layout.js` holds pure tree functions only (no writes). The permission card sends an answer, never a state. The agent script emits hook events like the real hook bridge; states are `idle, working, permission, waiting` plus `seen`, `failed`; "done, not seen" is `waiting` and not `seen` (Question 3). Rollup order and jump order follow spec section 8.

## 4. Pane lifecycle (closes M3)

`PaneRegistry` (in `term-pane.js`): `id -> {el, engine, shell, script, subs}`. A pane is created once. Layout render moves (reparent) the element; it never rebuilds it. A tab not shown gets `display:none`. Close detaches the pane and keeps it until the undo window ends, then `dispose()`: stops script timers, drops bus subscriptions, frees the engine. Undo re-attaches the same instance (scrollback, history, running `claude` survive). Cap: 8 panes; the 9th split shows a toast and does nothing.

## 5. Modules and slices (closes M4)

Module map and the app counterpart with file:line are in C section 3. Slice 0 creates every shared file; later slices own disjoint files and never edit another slice's file.

| Slice | Owns | Done when |
|---|---|---|
| 0 Skeleton (worker 1) | `index.html`, `css/base.css`, `bus.js`, `state.js`, `registry.js`, `config.js` (store, emits `config:changed`), `keymap.js` (dispatcher, `when`), `keys/schema`, `THIRD_PARTY.md`, `vendor/`, `CONTRACT` (C), `test/lib.py`, pane stub, spike report | spike all pass/fail items decided; page boots; contract tests green |
| A Terminal and shell (worker 1) | `term-adapter.js`, `term-pane.js`, `shell.js`, `commands/`, `vfs.js`, `agent-script.js`, `keys/terminal.js`, `css/pane.css`, `test/check_a.py`, Node tests | typing, history, Tab, `tarn`, `claude` pass; old terminal/link checks ported |
| B Layout and chrome (worker 2) | `layout.js`, `workspace.js`, `tabs.js`, `sidebar.js`, `dnd.js` (incl. drag handle), `find.js` (incl. find bar), `palette.js`, `keys/tabs.js`, `keys/splits.js`, `css/chrome.css`, `test/check_b.py` | old sidebar, tab, split, dnd checks ported and pass on the stub pane; real pane after A |
| C Viewer, settings, close (worker 3) | `viewer.js`, `viewer-shim.js`, `tools/sync-viewer.sh`, `settings.js`, `keys/viewer.js`, `keys/help.js`, `css/viewer.css`, `css/settings.css`, `test/check_c.py`; last: delete `docs/mockups/`, update `.claude/CLAUDE.md` and links | viewer, settings checks pass; gate in section 8 met |

A and B start after slice 0 merges; each owner subscribes to its own `config:changed` keys (A: font, size, theme, cursor, padding, option-as-alt; B: undo, confirm-close, cwd inherit, titlebar, tab style, unfocused opacity, drag-handle; C: window-theme, save-state, reset). Estimate: slice 0 one day, A/B/C three to four days.

## 6. Keys (closes M5)

Rows are data in `keys/*.js`: `{id, chords, alt, when, group, text}` (one chord per entry, no "1 ... 8"). Dispatcher: capture phase on `document`, match by `e.code`, `e.key` only as fallback (Cyrillic layouts). `when` encodes focus (terminal, viewer, any), so Cmd+D, Cmd+W resolve by focus. Fallback set `alt`: Ctrl+Alt+<same key> for rows the spike shows as browser-reserved; Help shows both. Auto-checks: no two rows share a chord in one `when`; no chord equals a shell input (Ctrl+letter, Alt+letter alone); fallback never collides with Ctrl+Cmd or Alt+Cmd rows. Playwright cannot see browser accelerators, so a pass proves only our handler; a manual step on a real Chrome (full screen, Keyboard Lock), Safari and a Russian layout is part of acceptance (C section 2).

## 7. Errors, invariants, persistence (closes M9, M10, M13)

- Error rule: catch at the module boundary, `console.warn` with pane id and command, never `console.error`; the user sees one line in the pane (`tarn-demo: <cmd>: internal error`) or a toast; the app lives. Broken storage: seed plus toast. Engine missing: message in the pane. `file://`: hint to start a static server.
- Invariants, each with a test: (1) no network request except same-origin; (2) no agent command (`tarn open`, `tarn new`, `claude`) moves focus or presses Enter; (3) the registry is the only writer of agent state; (4) a pane instance survives reparent and undo; (5) ported code keeps its license header and a `THIRD_PARTY.md` entry (ghostty-web, fonts, themes, viewer bundle).
- Persistence and "Reset demo" (settings and palette): table in C section 5. Mid-`claude` reload starts the pane at a fresh prompt; it never resumes a script.

## 8. Tests and acceptance (closes M6, M7, M8)

- Surface `window.__tarn` (C section 4) is the only way tests read state; old checks keep their name and user path, only the measuring changes; seed keeps ids `t1`, `w1`. `test/lib.py` (server, helpers) from slice 0; each slice writes `test/check_<slice>.py`. Gate for deleting the mockup: a script compares the 115 old check names with the new ones; none missing, all green.
- New checks: typing/history/Tab/^C; `tarn open`, `tarn ls`; `claude` through card with fake clock; every KEYS row from data (fails on a row without test); every setting row (C section 5 measure); no external request; idle draws 0 per second with blink off and 6 panes; gzip size computed by the test.
- Budgets (assumptions, to be measured in slice 0): first load under 1 MB gzip without viewer; viewer bundle and mermaid load on first open.
- Acceptance: (1) static server, zero console errors; (2) typing in a pane works, selection and scrollback behave; (3) all Help rows and settings work and persist; (4) workspaces, splits, zones, viewer (markdown, mermaid, code, save, `tarn open`, `path:line` click) match the mockup; (5) `claude` runs through the card; (6) all checks green and budgets met; (7) manual Chrome/Safari/Russian-layout pass done and noted in the PR.

## 9. Risks

| Risk | Mitigation |
|---|---|
| ghostty-web 0.x bugs | spike checklist; adapter; xterm.js fallback |
| Browser keys (Cmd+T/N/W, digits) | Keyboard Lock in full screen plus fallback keys; table from spike |
| Many panes | cap 8; hidden tabs paused; idle check |
| Viewer bundle is IIFE with a strict CSP for `tarn-md:` | `sync-viewer.sh` copies and rewrites CSP and paths; if iframe load fails the viewer slice stops and asks |
| Drift demo vs app | every Swift feature PR checks "demo updated or marked not yet" |
| Mobile | notice below 800 px |

## 10. Questions

1. Spec and canon: add the demo to `docs/spec.md` section 1 and replace "Mockup first" in `.claude/CLAUDE.md` with "Demo first". Recommend yes (slice C does the text after your OK).
2. `tarn new` is open in spec section 12 question 4. Recommend: demo opens a new tab with a plain shell, no auto `claude`, until you decide.
3. Labels: demo follows the canon (`waiting`, unseen), so the mockup's "done" label changes. Recommend yes; show "done, not seen" as the text of unseen `waiting`.
