# tarn demo

A static site that shows the tarn window in a browser: a real terminal emulator per pane, a simulated
shell, a scripted `claude` session with the permission card, workspaces, splits, drag-and-drop zones,
the viewer and the settings window. It is a storefront before download and the place where a UI step is
drawn and approved before it is built in the app ("Demo first", `.claude/CLAUDE.md`).

No backend, no build step, no network: ES modules and vendored files only.

## Built vs planned

| Part | State |
| --- | --- |
| Sidebar and agent states | built |
| Viewer (markdown, mermaid, code, save) | built |
| Cmd+B Toggle Pane (fallback Ctrl+Alt+B) and Cmd+W in the pane | built: Cmd+B opens the pane with the tree, hides it with tabs and unsaved text kept, shows it back, never closes; Cmd+W closes the file tab, the last tab or an empty pane; Enter on a file in the tree moves the keyboard to the file; a hidden pane with unsaved text still asks on close |
| File viewer: arrows between tree and file, scroll keys in view mode, editing and saving any text file with colors by language, Settings switch (File Viewer) | built: off, Cmd+B and path clicks open no pane and say so, `tarn open` answers that the viewer is off, an open pane keeps working |
| Workspaces, splits, layout | built |
| Find in the viewer (Cmd+F, Cmd+G, Shift+Cmd+G while the viewer has the keyboard): a bar at the top right like Ghostty's terminal search, n/m count, Enter and Shift+Enter step, Esc gives the keyboard back or closes an empty bar; view and source mode | planned: drawn for approval |
| Settings | built |
| Drop feedback: a 3 px system accent line where the dragged window will stand (at the cut), a gray chip with the reason on a refusal; the sidebar frames a workspace header a tab goes into and marks where a tab or workspace lands between rows with an accent line (a tab: above a row in its upper half, below it in its lower half) | built in 1.0.1; a terminal dropped on a terminal keeps Ghostty's own half highlight |
| Easy-to-catch grab zones: 14 px grab zones centred on split dividers and on the sidebar edge, resize cursor; the pane handle stays Ghostty's (80x12, dots in the top 20% of the pane) | built in 1.0.1; the app's sidebar zone leans into the sidebar so the first terminal column stays clickable |
| Sidebar width stops at its limits when dragged; only the toggle button folds it to the rail | built in 1.0.1 |
| Theme picker: base themes on top (three light and dark pairs and Dracula), all 771 themes below with a filter, one theme chosen; sidebar, title bar, menus and viewer take their colors from the terminal theme; the demo starts dark | built in 1.0.1 |
| Wide sidebar rows (task title, then folder and time in its state; the icon names the agent) with a Settings switch Row size, wide by default; header buttons Toggle File Viewer and New Workspace; Shift+Cmd+T for a new workspace | built in the app (#18, #21, #22) |
| Card answers AskUserQuestion with several questions one at a time ("Question 1 of 2"), then sends all answers in one reply; a multi-select question still goes to the terminal. Try it: ask `claude` something with a question mark | planned: drawn here for approval |
| `tarn` CLI | built in the app: `tarn open`, `tarn ls`, `tarn notify`. The demo has `open` and `ls`; `tarn new` (R15, second wave) is planned and prints "planned: not in the app yet" on its first run |

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
uv run --with playwright python -I demo/test/check_review.py # regressions found in code review, privacy scan
node --test demo/test/unit                                  # the shell without a browser
```

Every check runs on the real `index.html` with Chrome (`channel="chrome"`). On a shared machine put
`nice -n 10` in front. `demo/test/keys.html` is a manual page for the reserved browser keys.
`window.__tarn` is the only way tests read state (`js/CONTRACT.md`).

The viewer bundle is copied from the app by `tools/sync-viewer.sh`; run it after the viewer changes.

The structure of `demo/js/` and its app counterparts: `docs/modules/demo.md`; contracts: `js/CONTRACT.md`.
