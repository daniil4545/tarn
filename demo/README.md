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
| File viewer: arrows between tree and file, scroll keys in view mode, editing and saving any text file with colors by language, Settings switch (File Viewer) | built: off, open panes are hidden (their tabs and unsaved text stay) and come back when it is on again; Cmd+B and path clicks open no pane and say so, `tarn open` answers that the viewer is off; the Toggle File Viewer button hides |
| Workspaces, splits, layout | built |
| Find in the viewer (Cmd+F, Cmd+G, Shift+Cmd+G while the viewer has the keyboard): a bar at the top right like Ghostty's terminal search, n/m count, Enter and Shift+Enter step, Esc gives the keyboard back or closes an empty bar; view and source mode | built: Ghostty's Find menu items reach the page |
| Settings | built |
| Settings > Modules (first section): four switches Sidebar, File viewer, Permission card, Notifications, each applies at once; Permission card is greyed with "needs Sidebar" while Sidebar is off; Agents line with Claude Code version and three checks (sample data); the tab style picker moves into the Sidebar row; a Settings button at the top right of the window (demo only, the app keeps Cmd+, and the menu) | built (T-205, #34; the Settings button at the top right is demo only) |
| Permission card off: the hover card keeps title and state and drops Allow, Deny and answers | built (T-205, #34) |
| Notifications off: no banner for an agent that needs you, Cmd+U does nothing (the demo draws the banner and Cmd+U, built in the app as R4) | built (T-205, #34) |
| Drop feedback: a 3 px system accent line where the dragged window will stand (at the cut), a gray chip with the reason on a refusal; a workspace dragged in the sidebar shows an accent line where it lands | built in 1.0.1; a terminal dropped on a terminal keeps Ghostty's own half highlight |
| Sidebar tab drag as in Warp: the row lifts out solid and follows the pointer, the rows slide apart to a gap where it lands (above a row in its upper half, below it in its lower half, at the end of a workspace over its header) | built: the app keeps the macOS drag copy, which is translucent; a header with rows that stands below the gap keeps the gap where it is |
| Easy-to-catch grab zones: 14 px grab zones centred on split dividers and on the sidebar edge, resize cursor; the pane handle stays Ghostty's (80x12, dots in the top 20% of the pane) | built in 1.0.1; the app's sidebar zone leans into the sidebar so the first terminal column stays clickable |
| Sidebar width stops at its limits when dragged; only the toggle button folds it to the rail | built in 1.0.1 |
| Theme picker: base themes on top (three light and dark pairs and Dracula), all 771 themes below with a filter, one theme chosen; sidebar, title bar, menus and viewer take their colors from the terminal theme; the demo starts dark | built in 1.0.1 |
| Wide sidebar rows (task title, then folder and time in its state; the icon names the agent) with a Settings switch Row size, wide by default; header buttons Toggle File Viewer and New Workspace; Shift+Cmd+T for a new workspace | built in the app (#18, #21, #22) |
| Card answers AskUserQuestion with several questions one at a time ("Question 1 of 2"), then sends all answers in one reply; a multi-select question still goes to the terminal. Try it: ask `claude` something with a question mark | planned: drawn here for approval |
| Workspace by folder (`docs/specs/workspace-folder.md`): a new workspace asks for a folder and is named after it (a folder already open selects its workspace); new tabs and splits start in the current folder as in Ghostty, the "+" of a workspace in the folder of its tab (D20 dropped, T-249); the folder is fixed at creation and shown in the header tooltip; a tab stays in the workspace it was opened in, also when an agent starts in another project's folder (D21, D22 dropped, T-249); with tabs at the top and two or more workspaces each title starts with its workspace, dimmed; a new window starts with an ungrouped tab, where tabs and splits open as in Ghostty (T-245, T-249; restored sets keep "No project") | stage 1 built in the app (#51); the folder panel, a fixed folder in the header tooltip, the start workspace; the app shows the macOS folder panel where the demo asks for a path. stage 2 built in the app: new tabs and splits start in the current folder as in Ghostty, the "+" of a workspace in the folder of its tab (D20 dropped, T-249). stage 3b (agent tabs joining by folder, the outside-folder mark) built, then dropped (T-249). The top tab prefix is planned |
| Tab groups (T-266, `docs/specs/workspace-folder.md`): a group is optional and membership is explicit. The first tab of a window and a tab from another window are ungrouped; Cmd+T takes the group of its tab, right after it (Ghostty). Ungrouped rows have no header and no indent and may stand between groups; rows of a group are indented under its header. Shift+Cmd+T, the header button or "+ New group" ask for a Group (a name) or a Workspace (a group with a project folder, named after it, a folder icon in its header); the new group goes to the bottom. The "+" of a group adds at its end, in the workspace folder or the current tab's folder. Only sidebar commands change membership: drag a row onto a group or below all rows, Move to, Remove from group (the tab stands right below the group). The last tab leaving a group removes it; Delete group asks, with "Also close its tabs" unchecked the tabs stay where they are, ungrouped. `tarn ls` lists the caller's group with a GROUP column (JSON `group` and `folder`); an ungrouped caller sees its own tab only. A store with a workspace "~" opens with its tabs ungrouped in place | planned: drawn here for approval |
| `tarn` CLI | built in the app: `tarn open`, `tarn ls`, `tarn notify`, `tarn new` (a split below the caller, or right with `--right`, focus unchanged), `tarn run` (the same split, a shell with the command typed, Enter left to the user), `tarn wait`, `tarn read <pane> [--lines N]` (last lines of the screen, plain text), `tarn close <pane>` (no confirmation, focus unchanged). The demo has `open`, `ls`, `new`, `run`, `wait`, `read` and `close`; its `new` pane is a shell and does not run the command |

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
uv run --with playwright python -I demo/test/check_modules.py  # Settings > Modules and its switches
node --test demo/test/unit                                  # the shell without a browser
```

Every check runs on the real `index.html` with Chrome (`channel="chrome"`). On a shared machine put
`nice -n 10` in front. `demo/test/keys.html` is a manual page for the reserved browser keys.
`window.__tarn` is the only way tests read state (`js/CONTRACT.md`).

The viewer bundle is copied from the app by `tools/sync-viewer.sh`; run it after the viewer changes.

The structure of `demo/js/` and its app counterparts: `docs/modules/demo.md`; contracts: `js/CONTRACT.md`.
