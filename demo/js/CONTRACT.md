# Demo module contracts

What every slice may rely on. Source of intent: `docs/plans/s5-demo.md` and `docs/plans/s5-demo-contracts.md`. Checks: `demo/test/check_0.py`.

## State

`state.js`: `register(part, initial)` returns the only setter of `part`; a second `register` throws. `read(part)` and `snapshot()` return frozen data. Every setter call emits `state:changed {part}`.

| Part | Writer | Shape |
|---|---|---|
| `workspaces` | `main.js` now, `workspace.js` after slice B | `{tabs: {id: {id, title, cwd, layout}}, wss: [{id, name, tabs}], cur}`, seed in `seed.js` |
| `registry` | `registry.js` | `{paneId: {state, since, seen, failed, request, sawPermissionRequest, permissionAgent, answerable}}` |
| `config` | `config.js` | `{key: value}` for every key of `OPTIONS` |

Write a new part only through `register`. A tab's `layout` is a tree owned by `workspace.js`; the seed has one leaf `{pane: "pN"}` per tab.

## Bus

`bus.js`. `bus.on(event, fn)` returns an off function. `bus.emit(event, detail)`. `bus.handle(name, fn)` sets the single handler of a command (a second one throws). `bus.cmd(name, payload)` runs it. A throwing or unknown command is caught: `console.warn`, an entry in `errors`, a `toast` event; `cmd` returns undefined.

Commands and their writers: table in `docs/plans/s5-demo-contracts.md` section 4. Slice 0 owns `hook`, `config.set`, `config.reset`.

Events: `state:changed {part}`, `config:changed {key, value}` (not sent for the values loaded at start: read `read("config")` once at init), `vfs:changed {path, by}`, `pane:output {id}`, `toast {text}`, `pane:focused {pane}` (the pane module emits it on focus; the registry marks the session seen), `pane:disposed {pane}` (emitted when a pane is freed after the undo window; the registry drops its record).

## Registry

`hook {pane, name, event}`: `name` is a Claude Code hook name, `event` carries `agent_id`, `background_tasks`, `notification_type`, `reason`, `request`, `answerable` as in `SessionRegistry.swift`. Only the registry writes `registry`. `handle(session, name, event)` is the pure transition table (spec section 8). On a state change the registry sets `since` and `seen` (`seen` = the pane is focused now).

Labels follow the canon: `waiting` and not `seen` is shown as "done, not seen"; there is no state `done`.

## Config

`OPTIONS` lists every key with `type`, `def` and bounds or `values`, named as the Ghostty keys, plus `tab-style`. `config.set {key, value}` validates, stores, persists (`tarn-demo-v1:config`) and emits `config:changed`. Invalid values throw, so the bus reports them. `config.reset` restores defaults.

## Keys

Rows are data in `keys/*.js`: `{id, chords, alt, when, group, text, cmd, payload}`; chords like `Cmd+Shift+D`, fallbacks `Ctrl+Alt+<key>`. A slice exports its rows; `main.js` concatenates all rows and calls `installKeys(rows, {focus})`, where `focus()` returns `terminal`, `viewer` or `any` (slice B wires the real focus). `installKeys` throws if `checkRows` finds a duplicate chord in an overlapping `when`, a chord that is shell input (Ctrl+letter, Alt+letter alone), or a fallback that is not Ctrl+Alt+key. Match is by the Latin letter of `e.key`, else by `e.code`; the handler runs in the capture phase and stops the event.

## Pane

`createPane(id, {cwd})` returns `{id, el, term, focus(), screenText(), dispose()}`. `pane-stub.js` is the stand-in; `term-pane.js` (slice A) replaces it with the same shape. `dispose()` removes the element and emits `pane:disposed`.

## Terminal adapter

`term-adapter.js`: `await createTerm(parentEl, options)` returns a `Term`. Only this file imports the engine.

| Member | Meaning |
|---|---|
| `cols`, `rows`, `options` (frozen copy), `lineCount`, `topRow`, `cursorRow` | geometry; rows are absolute: scrollback first, then the screen |
| `write(data)`, `paste(text)`, `focus()`, `fit()`, `dispose()` | |
| `onData(fn)`, `onResize(fn)`, `onSelection(fn)` | each returns an off function; `onSelection` fires after a mouse selection ends |
| `setOption(key, value)` | `theme`, `fontSize`, `fontFamily`, `cursorStyle`, `cursorBlink` |
| `optionAsAlt`, `copyOnSelect` | setters; Alt+key sends ESC + key when on; selection copies to the clipboard when on |
| `lineText(row)`, `screenText()` | text with blanks kept |
| `addLinkProvider(find, activate)` | `find(lineText)` returns `[{start, end, text}]` (columns, end exclusive) |
| `scrollToRow(row)`, `getSelection()`, `clearSelection()`, `select(col, row, length)` | |
| `cellCentre(col, row)` | page position of a visible cell, for tests |

The shell keeps its own prompt rows (engine has no OSC 133 marks): store `cursorRow` when a prompt is written, jump with `scrollToRow`. Pass `fontFamily` as a CSS list; `createTerm` waits for that font before it measures cells. Do not call `t.select`/clicks in tests faster than a double-click interval after a click (the engine counts them as a double click).

## Time

`clock.js`: `now()`, `after(ms, fn)`, `cancel(id)`. All scripts and timeouts of the demo use it. A test calls `__tarn.clock.freeze()` first, then `advance(ms)`.

## Test surface

`window.__tarn` (read only): `snapshot()`, `screen(id)`, `linkAt(id, text)`, `term(id)`, `viewer().state()`, `clock.freeze()`/`advance(ms)`, `errors`, `requests()`. The pane and viewer modules set `hooks.screen`, `hooks.linkAt`, `hooks.term`, `hooks.viewer` from `test-contract.js`; an unset hook throws "test hook not set".

## Persistence

`storage.js`: `load(part, seed)`, `save(part, value)`, `clearAll()`; key `tarn-demo-v1:<part>`; bad JSON gives the seed and a `toast`; a missing or blocked storage is tolerated.

## Viewer bundle in an iframe

Checked in slice 0: the app bundle `macos/Sources/Features/Tarn/Viewer/tarn-viewer.{html,js,css}` runs in an iframe on a static server after two changes: the meta CSP is rewritten (`script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:`) and `window.webkit.messageHandlers.tarn.postMessage` is defined by an external script loaded before `tarn-viewer.js` (an inline script is blocked by the CSP). The page then answers `tarn.setChrome(...)` and `tarn.setDoc(...)` calls (shapes: `ViewerModel.swift` `pushChrome`, `pushDocument`) and posts `{t: "ready"}`, `{t: "tab", ...}` and the other messages. Unmodified, the CSP blocks the script and style, and `window.tarn` is undefined. Images use `tarn-md://file/<abs path>` and need the same rewrite.
