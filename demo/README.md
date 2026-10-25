# tarn demo

A static site that shows the tarn window in a browser: a real terminal emulator per pane, a simulated
shell, a scripted `claude` session with the permission card, workspaces, splits, drag-and-drop zones,
the viewer and the settings window. It is a storefront before download and the place where a UI step is
drawn and approved before it is built in the app ("Demo first", `.claude/CLAUDE.md`).

No backend, no build step, no network: ES modules and vendored files only.

## Built vs planned

| Part | State |
| --- | --- |
| Sidebar and agent states | built (PR #3-#5) |
| Viewer (markdown, mermaid, code, save) | built (PR #3-#5) |
| Workspaces, splits, layout | built (PR #3-#5) |
| Settings | built (PR #3-#5) |
| `tarn` CLI (`tarn open`, `tarn ls`, `tarn new`) | planned: the app only has the socket command that opens a file, and a click on a path does the same. The demo keeps the commands to try the idea and prints "planned: not in the app yet" on `tarn --help` and on the first run of each subcommand |

## Run

```sh
python3 -m http.server 8000 --directory demo
```

Open http://localhost:8000. `file://` does not work (ES modules, WASM). Use current Chrome or Edge;
in full screen the page gets Cmd+T, Cmd+W and Cmd+N through Keyboard Lock. Elsewhere use the
`Ctrl+Alt+<key>` form that Help (Cmd+, then Help) lists beside each row.

## Test

```sh
uv run --with playwright python -I demo/test/check_0.py     # engine, contracts, boot
uv run --with playwright python -I demo/test/check_a.py     # terminal, shell, claude script
uv run --with playwright python -I demo/test/check_b.py     # layout, workspaces, sidebar, drop zones
uv run --with playwright python -I demo/test/check_c.py     # viewer, settings, Help
uv run --with playwright python -I demo/test/check_e2e.py   # the whole user story
node --test demo/test/unit                                  # the shell without a browser
```

Every check runs on the real `index.html` with Chrome (`channel="chrome"`). On a shared machine put
`nice -n 10` in front. `demo/test/keys.html` is a manual page for the reserved browser keys.
`window.__tarn` is the only way tests read state (`js/CONTRACT.md`).

The viewer bundle is copied from the app by `demo/tools/sync-viewer.sh`; run it after the viewer changes.

## Modules (`demo/js/`)

| Area | Files | App counterpart |
| --- | --- | --- |
| Core | `main.js` (boot order), `bus.js`, `state.js`, `storage.js`, `clock.js`, `config.js`, `test-contract.js` | `ControlSocket.swift`, `TarnSettings.swift` |
| Agent state | `registry.js`, `agent-script.js`, `session-rows.js` | `SessionRegistry.swift` |
| Terminal | `term-adapter.js` (the only engine importer), `term-pane.js`, `pane-options.js`, `pane-links.js`, `paste-guard.js`, `themes.js`, `seed-screens.js` | Ghostty surface |
| Shell | `shell/` (line editor, parser, completion), `commands/`, `vfs.js`, `vfs-seed.js` | the shell and the disk |
| Layout | `layout.js` (pure tree functions), `workspace.js` (only writer), `view.js`, `dnd.js`, `frame.js` | Ghostty `SplitTree`, `SidebarModel` |
| Chrome | `chrome.js`, `sidebar.js`, `sidebar-drag.js`, `tabs.js`, `tabcard.js`, `tab-status.js`, `find.js`, `palette.js`, `toast.js` | `Sidebar.swift`, `TabCardPopover.swift` |
| Viewer | `viewer.js`, `viewer-model.js`, `viewer-paths.js`, `viewer-shim.js`; bundle in `viewer/` | `ViewerModel.swift`, `ViewerHost.swift` |
| Settings | `settings.js`, `settings-data.js`, `settings-effects.js`, `settings-help.js`, `demo-reset.js` | `TarnSettings.swift` |
| Keys | `keymap.js` (dispatcher), `keys/` (rows as data) | menu key bindings |

Rules: each state part has one writer; other modules send commands on the bus. A pane is created once
and moved in the DOM, never rebuilt. Details: `js/CONTRACT.md`, `docs/plans/s5-demo.md`.
