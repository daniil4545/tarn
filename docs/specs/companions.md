# Modules and companions

Status: approved by the user 2026-10-31 (T-364); hub placement and the release scope added 2026-11-02 (T-371); the hub deferred past 1.4.0 by the user 2026-11-03. A base to grow rules on once companions are in use: it fixes terms and a few rules, everything else is a default. Extends `docs/specs/modules.md`.

## 1. Idea

The window is the center: a terminal pane, with or without an agent in it. Everything tarn adds on top of Ghostty is a module. A companion is a module drawn beside the windows, a tool for one task: the viewer for files, the hub for agents.

```
[ sidebar ][ window   ][ viewer ][ hub ]
            terminal     tab       global
```

## 2. Terms

| Term | Meaning |
|---|---|
| Window | a terminal pane of a tab; an agent may run in it |
| Module | a standalone tool on top of Ghostty: works without other modules, has one switch and its own settings |
| Setting | an option of a module or of tarn, not a module (Permission card, Notifications) |
| Companion | a module drawn beside the windows, a tool for one task |
| Tab companion | belongs to one tab, works on that tab's windows: the viewer |
| Global companion | the same in every tab of a window: the sidebar, the hub |

## 3. Decided by the user

2026-10-31:

- The window is central; no separate agent window kind.
- Module = standalone tool with a switch and settings; Permission card and Notifications are settings.
- Companions are modules for one task; two kinds, tab and global; a global companion goes with the user to the next tab.
- Several companions at once is normal; the last opened stands rightmost.
- Agents may open, show and close companions; focus never moves and typing never stops.
- The permission card and the hub answer requests by the same rules, under one setting.
- Few rules now: the base first, rules are added from use.
- The hub is a pane on the right of the windows, like the viewer; with both open, the last opened stands rightmost. It opens by a button or a shortcut; its state is global across tabs (epic T-363).

2026-11-02 (epic T-370, release 1.4.0, renamed from 1.3.3 on 2026-11-03):

- Current modules are brought to one companion form in code before the hub: a companion table over the existing switches, menu actions and toggles (T-374). `TerminalController` keeps its nesting of sidebar, viewer and terminal.
- The state model per tab group for global companions comes with the hub (T-427): the sidebar's width and collapse are already global through `@AppStorage` (`Sidebar.swift:710-711`).
- Settings change in naming and grouping only (T-373); stored keys and behavior stay.

## 4. Rules

| # | Rule | Source |
|---|---|---|
| R1 | **Module.** One switch in Settings > Modules, its settings under it; off keeps its state and costs nothing | modules.md rules 1-2 |
| R2 | **Kind.** A tab companion's state lives in its tab, as the viewer's today. A global companion's state (open, width, view) lives in one shared model; every tab of the window draws it from that model, so a tab switch keeps it | how the sidebar works today: each tab draws its own sidebar from shared settings (`TerminalController.swift:65-67`, `Sidebar.swift:852`) |
| R3 | **Toggle.** A companion opens and closes by a button or a shortcut; the user's toggle gives it the keyboard, closing returns it to the window | today's Cmd+B (viewer-pane.md); VS Code toggle command and title-bar controls |
| R4 | **Focus.** Only the user moves focus. An agent may open, show or close a companion: the keyboard stays where it is and the user's typing goes on | tarn invariant "no agent command moves focus or presses Enter for the user"; user decision |
| R5 | **Answers.** One setting, "tarn answers requests", turns on answering from both the sidebar card and the hub; off, Claude Code shows its own prompt | user decision; modules.md section 5 (today's Permission card off) |

## 5. Defaults, not rules yet

These hold until use shows what the rule should be.

- **Place.** The sidebar on the left; other companions on the right of the windows, the last opened rightmost. A companion pane drags like the viewer pane today.
- **Keys.** Each companion keeps the keys it has; Esc keeps its present meaning inside the viewer; the shortcut scheme of all toggles is #167.
- **Width.** As today: the viewer by its split ratio in the tab; a global companion by the shared model.
- **Restore.** As today: the sidebar comes back, viewers do not; the hub's open state and view come back with its shared model.
- **Narrow window.** No rule yet; watch it in use.

## 6. Capabilities

What a companion may have; each one's document says which.

| Capability | Viewer | Hub | Sidebar |
|---|---|---|---|
| Expand to the whole tab (own state, not Ghostty's split zoom, which works only inside the terminal block) | yes | yes | no |
| Shown by an agent (`tarn` CLI, R4) | yes, `tarn open` | not yet | no |
| Answers requests (R5) | no | yes | yes, card |
| Views | rendered, source, tree | List, Board | row size |

## 7. Template

Each companion's document `docs/modules/<name>.md` states:

1. **Task.** The one task it is the tool for.
2. **Kind.** Tab or global; where its state lives (R2).
3. **Content and actions.** What it shows; click, Enter and keys.
4. **Capabilities and settings.** From section 6, and its own settings.
5. **Off and cost.** What the user sees when it is off; zero work while off.
6. **Prior art.** Analog for each behavior, or "Prior art: searched where - found what".

## 8. Planned changes to existing documents

Deferred by the user 2026-11-03: the hub (epic T-363) and the state model per tab group (T-427) come after 1.4.0, the last release of this line; 1.4.0 brings the current modules to the companion form without adding one. The changes below stay planned; the ones that need the hub move with it:

- `docs/specs/modules.md`: Settings > Modules lists Sidebar, File viewer, Hub; "tarn answers requests" (R5) is shown under Sidebar and Hub and read by the card and the hub; Notifications is a tarn setting. Stored keys stay, so saved values survive. In 1.4.0 only the naming and grouping change (T-373).
- Viewer spec: `tarn open` shows the viewer with the file instead of leaving it hidden; focus and typing stay (R4).
- Layout: "Split zoom does nothing from a viewer" is replaced by the expand capability.

## 9. Open for the hub spec

Findings of the 2026-10-31 review of this concept that 1.4.0 does not settle; the hub spec answers each.

| Item | Question |
|---|---|
| State owner | The global model per tab group (T-427): what a detached tab gets (own copy), the quick terminal (no global companions), two windows showing one agent |
| Hub in the layout | The hub as a pane beside the viewer: how a global pane sits in each tab's `AreaTree` and what `ViewerSnapshot` stores for it |
| Expand | Own state, not Ghostty's `toggle_split_zoom`; its key, and which wins with a zoomed terminal split |
| Esc | Innermost first (editor, files tree, then leave) or a separate key; today's viewer Esc stays until then |
| `tarn open` shows the viewer | Showing a pane resizes the terminal under a typing user; keep "hidden stays hidden" with a mark, or show |
| Subject | Which window gets the keyboard back after a global companion closes in another tab |
| Agent shows a closed or off companion | What "show" means for a closed pane, a background tab, an expanded companion |
| Narrow window | Minimum widths; which companion hides first |
| Show and focus | The CLI "show" never focuses; only the user's toggle does |
| Template size | Section 7 against the existing `docs/modules/viewer.md` and `sidebar.md`: rewrite them to the template or keep their format and add only the missing points |
