# State

## In progress

- T-62 (tix): Ghostty ecosystem research and the S0 plan. Step: the base is decided, the spec is being aligned with the PRD of 2026-10-23 (`~/Dev/self-projects/agent-terminal/docs/prd.md`).
- Branch `s1-sidebar`: sidebar MVP accepted by the user on screen with simulated hook events. Tabs of a window grouped by git project with folding; agent state as a colored dot (working blue, needs you orange, done unseen green, done grey, error red); one card popover beside the row (hover on tabs with a state, force click on any tab) with Allow/Deny and question options; ⌘⇧U jumps to the session that needs the user. Hooks reach the app through the `plugin/` Claude Code plugin, `hook.sh` and the control socket; `TARN_SURFACE` names the surface. State machine tests in `macos/Tests/Tarn/`.
- Not verified live: a real Claude Code session (the `claude` binary was missing from the system on 2026-10-23), Allow/Deny on a real dialog (the key goes only when the screen shows `1. Yes` or the option label), the Esc liveness rules. `swiftlint` is not installed.

## Done

- 2026-10-22, T-62: research of the Ghostty ecosystem (Reddit, Discussions, upstream, Tellurion) and an overview of interesting Ghostty projects, in the private research folder `~/Dev/self-projects/agent-terminal/docs/research/` (merged into `landscape.md`, `code-sources.md`, `phone-access.md`; trial checklist `tellurion-trial-2026-10-22.md`). Draft stage plan `docs/plans/s0-core.md`. Checked: upstream milestones and tags with `gh api`, Tellurion tree and diff against `v1.3.1`.
- 2026-10-22, T-69 (personal): phone access to the Mac works without tarn: NovaScale (SSH with embedded Tailscale) and Remote Login. R14 needs no code of ours.
- 2026-10-23, T-62: Tellurion trial ended. Verdict: tarn on Ghostty per `docs/spec.md`, no fork of Tellurion. The user liked its sidebar, project groups, statuses, quick approve and hover card; rejected its style and animations.

## Next

1. The user runs `~/tellurion-rollback.sh` (Tellurion hooks out of `~/.claude/settings.json`; the agent was not allowed to edit it), reinstalls Claude Code and installs the plugin: `claude plugin marketplace add <repo>/plugin`, `claude plugin install tarn@tarn`. Then a live pass: permission, question, both Esc cases, a subagent.
2. Release v0.0.1 by the `merge` skill: `s1-sidebar` into `main`, tag. Tag name to agree: upstream `v1.x` tags live in the same repo.
3. Spec edits to agree: the file panel (tree, viewer, editor) moves to the first wave; hover card and quick approve are added; the hook bridge is a shell script instead of `tarn hook`.
4. Next features by the pipeline in `.claude/CLAUDE.md`: system notifications, the file panel, tabs of all windows in one list.
4. Apply `docs/plans/s0-core.md` section 6, run `spec-reviewer` on the plan, open the S0 ticket. Start needs the `v1.4.0` tag and 30 GB of free disk (T-65).

## Open

- Disk: 13 GB free of 460 GB; S0 needs about 30 GB (T-65).
- `main` is 15 commits behind `upstream/main`; base decision is the `v1.4.0` tag (due 2026-10-23).
