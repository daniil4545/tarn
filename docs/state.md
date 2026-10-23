# State

## In progress

- T-62 (tix): Ghostty ecosystem research and the S0 plan. Step: the base is decided, the spec is being aligned with the PRD of 2026-10-23 (`~/Dev/self-projects/agent-terminal/docs/prd.md`).
- Branch `s1-sidebar`: sidebar v1 accepted by the user on screen (tabs of a window grouped by git project, folding, paths from `~`, resize). Not covered yet: tabs of all windows in one list, agent states, hover card, quick approve; `swiftlint` not installed, no tests.

## Done

- 2026-10-22, T-62: research of the Ghostty ecosystem (Reddit, Discussions, upstream, Tellurion) and an overview of interesting Ghostty projects, in the private research folder `~/Dev/self-projects/agent-terminal/docs/research/` (merged into `landscape.md`, `code-sources.md`, `phone-access.md`; trial checklist `tellurion-trial-2026-10-22.md`). Draft stage plan `docs/plans/s0-core.md`. Checked: upstream milestones and tags with `gh api`, Tellurion tree and diff against `v1.3.1`.
- 2026-10-22, T-69 (personal): phone access to the Mac works without tarn: NovaScale (SSH with embedded Tailscale) and Remote Login. R14 needs no code of ours.
- 2026-10-23, T-62: Tellurion trial ended. Verdict: tarn on Ghostty per `docs/spec.md`, no fork of Tellurion. The user liked its sidebar, project groups, statuses, quick approve and hover card; rejected its style and animations.

## Next

1. The user approves the spec edits (side panel with file tree, viewer and editor moves to the first wave; hover card and quick approve are added).
2. Roll back Tellurion hooks from `~/.claude/settings.json` using the snapshot in `~/.tellurion-backup-2026-10-22/`.
3. Per feature: approve, survey other projects, approve our architecture, code (pipeline in `.claude/CLAUDE.md`). Next feature: agent states, hover card and quick approve on top of the sidebar.
4. Apply `docs/plans/s0-core.md` section 6, run `spec-reviewer` on the plan, open the S0 ticket. Start needs the `v1.4.0` tag and 30 GB of free disk (T-65).

## Open

- Disk: 13 GB free of 460 GB; S0 needs about 30 GB (T-65).
- `main` is 15 commits behind `upstream/main`; base decision is the `v1.4.0` tag (due 2026-10-23).
