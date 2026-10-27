# Workspaces as a thin layer over Ghostty

Task: T-249. User decision 2026-10-27: "a wrapper around Ghostty, do not touch its mechanisms,
layer our logic carefully" (option A over "label plus project +" and "keep as is").
Reviewed: `scratchpad/plan-review.md` (spec-reviewer), `scratchpad/plan-skeptic.md` (skeptic).

## Contents

1. Problem
2. Prior art
3. Model
4. Behavior
5. What goes and what stays
6. Slicing
7. Checks
8. Risks
9. Open questions

## 1. Problem

- Ghostty opens a new tab, split and window in the working directory of the focused pane
  (`tab-`, `split-`, `window-inherit-working-directory`, all `true`: `src/config/Config.zig:2085-2099`;
  the shell reports it through OSC 7 shell integration). The first window from launchd or
  `open` starts in `home` (`Config.zig:1581`).
- tarn rewrites that at two insertion points (`AppDelegate.swift:807-808`,
  `BaseTerminalController.swift:673-674`, architecture rows 31 and 32) through
  `WorkspaceRegistry.prepare` (D20): a pane outside the workspace folder opens in the folder.
- Since #97 "~" has the home folder, so Cmd+T or Cmd+D from `/tmp` in "~" opens in home. With
  Workspaces off `prepare` has no frozen guard, so every tab of a workspace with a folder is
  rewritten too (since T-205). Ghostty would open in `/tmp`.
- The agent arrival (D21, D22, D26, D27) is our own mechanism next to Ghostty: pid tracking,
  a queue, a wait for the key window, manual marks, the orange "!" mark.

## 2. Prior art

Survey: `scratchpad/recon-workspace-cwd.md` (T-249), sources there.

| Project | Split cwd | New tab cwd | Auto-move between groups |
| --- | --- | --- | --- |
| cmux b7be2944 | Ghostty inherit | inherited from the selected tab of the target workspace (`Sources/TabManager.swift:2014-2048`) | none found |
| Warp | setting per pane | setting: Home (default), previous session, custom | none found |
| VS Code | inherited (`splitCwd` default) | workspace root | no |
| Zed | n/a | project directory (default) | no |
| iTerm2 | profile: home, reuse previous, custom | same, per tab | no groups |
| WezTerm | active pane cwd, else home | same | not documented |

Conclusion: a split inherits everywhere. A new tab varies: inherit (cmux, WezTerm), project root
(VS Code, Zed) or a setting (Warp, iTerm2). No analog moves a tab between groups by itself.
Gaps: Tellurion not read; cmux grouping by cwd read only in part; VS Code new terminal against
the focused pane not confirmed.

## 3. Model

- Ghostty owns windows, native tabs, splits, the working directory of every new surface,
  restore and undo.
- tarn owns one map: tab to workspace, per window set (`WorkspaceBook`, `WorkspaceSet`).
- A workspace is a name, a fold state and an optional folder. The folder is used for a tab
  tarn opens itself on an explicit action: the first tab of a workspace created from a folder
  (`TerminalController.newTab(_:from:withBaseConfig:)` with only `workingDirectory` set), and
  "+" of the header per Q1.
- "~" is a name with no folder: the start workspace of a fresh set and the target of Workspaces
  off.
- Writers of membership stay as today: reconcile of a new tab (target: pending target of "+",
  else the selected tab's workspace, else `lastSelected`, `WorkspaceBook.swift:211`), rule 4
  repair of a reorder, drag, merge, sidebar move, delete, undo `reinsert`, restore `adopt`,
  frozen join. Fallback: one log line, the tab goes to the target (`docs/modules/workspaces.md`).
- tarn calls Ghostty's `move_tab` only to keep every workspace one run of native tabs: rule 5
  (a new tab goes after the last tab of its workspace), regroup when Workspaces is on again,
  and sidebar moves. Unchanged by this plan.

## 4. Behavior

| Event | Ghostty | tarn | Source |
| --- | --- | --- | --- |
| first launch | window in home | one set, "~" with the tab | Ghostty `working-directory` |
| Cmd+N | window inherits the focused cwd | new set "~" | Ghostty, D10 |
| Cmd+T in any workspace | tab inherits the focused cwd | tab joins the target, moved after its last tab | Ghostty, cmux, WezTerm |
| Cmd+D | split inherits the focused cwd | nothing | Ghostty, VS Code `splitCwd` |
| Shift+Cmd+T, folder picked | first tab at the folder via `newTab(withBaseConfig:)` | new workspace named after the folder | VS Code, Zed |
| folder already in the window | nothing | selects that workspace's first tab | unchanged |
| "+" in a workspace header | per Q1 | tab joins that workspace | Q1 |
| reorder by drag in the tab bar | native reorder | rule 4: the mover joins the upper neighbour's workspace | unchanged |
| tab to another window | native | joins that window's target | unchanged |
| tab dropped outside every window | new window | new set "~" | unchanged |
| Merge All Windows | native | first set wins; a plain window (one unrenamed "~", "No project" or "Default" with no folder) joins | unchanged |
| close and Cmd+Z | Ghostty undo | tombstone restores set, workspace and place (`reinsert`, `WorkspaceBook.swift:306-318`) | unchanged, without manual and pid |
| delete a workspace | closes its tabs | removes it, the last one stays | unchanged |
| quick terminal | its own window | not a `TerminalController`: untouched | unchanged |
| hidden titlebar (S34) | Cmd+T opens a window | the window starts a new set "~" | Ghostty |
| an agent starts in a tab | nothing | the tab stays; icon and status as today | no analog auto-moves |
| tab prefix (D25) | native titles | "<workspace> · <title>" with two or more workspaces | unchanged, writers: rename, workspace count, moves |
| Workspaces off | nothing | new tabs join "~" (made when missing) | T-205 |
| restore | Ghostty restores windows | names and folders; old `manual` keys ignored; a "~" with the home folder loads as "~" with no folder | format v1 |

## 5. What goes and what stays

Code that goes:

- PR 1: home folder of "~" (`makeHome`, `isHome`, `isPlain` one rule, `WorkspaceFolder.home`
  exclusion); migration in `WorkspaceSnapshot.makeSet`: a workspace named "~" whose folder is
  the standardized home loads with no folder.
- PR 2: `WorkspaceRegistry.prepare`, `landsInWorkspace`, both insertion points (the two Ghostty
  functions go back to upstream, `let config` included; architecture rows 31 and 32 removed);
  `WorkspaceBook.folderForNewSurface`, `WorkspaceFolder.startDirectory`; Q1 in `newTab(in:from:)`.
- PR 3, arrival: `WorkspaceBook.arrival`, `checkArrival`, `takeArrival`, `runnable(in:)`,
  `arrived(_:selected:)`, `pendingTabs`, `deciding`, `pending`, `ClosedTab.deciding`;
  `WorkspaceRegistry.checkArrivals`, `scheduleArrivals`, `runArrivals`, `isAlive`,
  `arrivalScheduled` and their calls (:121, :131, :225); `WorkspaceFolder.home`.
- PR 3, manual marks: `WorkspaceSet.manual` (init, `remove`, `absorb`, revision, rule 4 mark),
  `isManual`, `markManual`, `byUser` of `join` and `moveTab`, `ClosedTab.manual`,
  `WorkspaceSnapshot.manual` (:31, :46, :69, :100; old keys are ignored by the decoder).
- PR 3, outside mark: `WorkspaceBook.isOutsideFolder`, `WorkspaceRegistry.isOutsideFolder`,
  `Sidebar.swift` `outsideFolder` (:37, :268, :1156, :1186, :1201, :1204); `WorkspaceFolder.contains`
  if `display` no longer needs it.

Stays: `KeyHops`, `moveNatively` (sidebar moves, rule 5, regroup), `AgentProcessCache` (sidebar
icon), `targetWorkspace` and the pending target, folder picking, `standardized`, `display`, D25.

Tests: PR 2 edits `StartDirectoryTests.swift` and `AgentArrivalTests.swift:160`
(`folderForNewSurface`); PR 3 removes `AgentArrivalTests.swift`, rewrites the rule 4 cases of
`ManualMarkTests.swift` on membership only and drops the rest.

Docs:

- `docs/specs/workspace-folder.md`: D20 (PR 2), D21, D22, D26, D27 (PR 3) marked "Dropped
  2026-10-27 (T-249)" with one line why; rows S5-S10, S34 (PR 2), S11-S21, S26-S33, the arrival
  writer of S35 (PR 3); the "replaced" rows :148-151 restore D11 and D15; R2 and R4 dropped; D24
  and D1 (`windows-workspaces.md:28`) say "~" has no folder (PR 1). D25 keeps its behavior with
  the reason "shows the workspace of a native tab".
- `docs/modules/workspaces.md` lines :5, :55, :61, :107, :130, :139 (PR 1); :51, :79, :122 (PR 2);
  :47, :53, :57, :63, :65, :121 (PR 3).

Demo: `demo/js/workspace.js` :115, :141-149, :185-190, :324-340, :357; `demo/js/sidebar.js`
:71, :94; `demo/test/check_e2e.py` :89-98; seed and `openWindow` "~" without a folder (PR 1).

## 6. Slicing

Each PR under 400 lines of code, into `dev`, review and stand before merge. Each builds and
passes tests alone.

| PR | Content | Visible change |
| --- | --- | --- |
| 1 | "~" without a folder, migration of a restored "~" | Cmd+T, Cmd+D in "~" open as in Ghostty; no "!" in "~" |
| 2 | remove `prepare` and the insertion points, D20, Q1 | Cmd+T, Cmd+D open as in Ghostty everywhere; "+" per Q1 |
| 3 | remove arrival, manual marks, outside mark | agent tabs stay; no "!" |

## 7. Checks

- App tests (`macos/build.nu --action test`), swiftlint strict, demo checks, typos.
- Removed tests carry `Test-change:` lines.
- PR 1: a restored snapshot with "~" at the home folder loads with no folder and is plain;
  Workspaces off on it makes no second "~".
- PR 2: `git diff upstream/main` of `ghosttyNewTab` (`AppDelegate.swift`) and
  `ghosttyDidNewSplit` (`BaseTerminalController.swift`) shows no change, `let config`
  included; a Q1 test for "+" with the focus in another workspace.
- PR 3: `rg` for every removed symbol in `macos/` and `demo/` finds nothing; a snapshot with a
  `manual` key restores; rule 4 membership cases from `ManualMarkTests` still pass.
- Stand (`make -f tarn.mk live`): in "~" and in "tarn" at `F`, `cd /tmp`, Cmd+T and Cmd+D open
  in `/tmp`; again with `shell-integration = none`, recorded as Ghostty's own result. Shift+Cmd+T
  on a folder opens its first tab there. PR 3: "tarn" at `F`, a tab in "~" at `F/macos`, start
  `claude`: the tab stays in "~" (on dev it moved).

## 8. Risks

Checked by the skeptic, hold: rule 4 does not read marks (`WorkspaceSet.swift:324`); the
tombstone does not need marks or pids (`WorkspaceBook.swift:306-319`); snapshot v1 loads both
ways (`decodeIfPresent`, `WorkspaceSnapshot.swift:69`); no other reader of the removed fields.
Open:

1. "+" of a project workspace after PR 2 (Q1).
2. A user workspace at the home folder (Shift+Cmd+T on home) no longer takes Workspaces-off tabs.
3. Hidden titlebar: "+" opens a window; its pending target expires after 1 s and leaves no
   empty workspace (`WorkspaceRegistry.swift:440-443`).

## 9. Open questions

- Q1. "+" in a workspace header:
  - (a) Ghostty's Cmd+T: the focused pane of the selected tab;
  - (b) `newTab(withBaseConfig:)` at the folder, no folder means (a), a deleted folder is
    dropped by Ghostty (`Exec.zig:982-986`); analog VS Code, Zed;
  - (c) inherit from the selected or last tab of that workspace: the same
    `ghostty_surface_inherited_config` as today (`WorkspaceRegistry.swift:426-428`) with another
    source surface; analog cmux. Ghostty decides the cwd, the project is kept.
  - Recommendation: (c), it is Ghostty's own inheritance from the right tab.
