# State

## In progress

- T-62 (tix): Ghostty ecosystem research and the S0 plan. Step: waiting for the user's trial of Tellurion (2-3 days from 2026-10-22). After the verdict the user picks one of two paths: build tarn on Ghostty per `docs/spec.md`, or fork Tellurion and strip it.

## Done

- 2026-10-22, T-62: research of the Ghostty ecosystem (Reddit, Discussions, upstream, Tellurion) and an overview of interesting Ghostty projects, in the private research folder `~/Dev/self-projects/agent-terminal/docs/research/` (`ghostty-ecosystem`, `ghostty-reddit`, `ghostty-projects-overview`, `tellurion-trial`, all 2026-10-22). Draft stage plan `docs/plans/s0-core.md`. Checked: upstream milestones and tags with `gh api`, Tellurion tree and diff against `v1.3.1`.
- 2026-10-22, T-69 (personal): phone access to the Mac works without tarn: NovaScale (SSH with embedded Tailscale) and Remote Login. R14 needs no code of ours.

## Next

1. Tellurion trial verdict from the user; checklist in `agent-terminal/docs/research/tellurion-trial-2026-10-22.md`. After it, roll back Tellurion hooks from `~/.claude/settings.json` using the snapshot in `~/.tellurion-backup-2026-10-22/`.
2. If tarn on Ghostty: apply the spec edits listed in `docs/plans/s0-core.md` section 6 (user agreed to all), run `spec-reviewer` on the plan, open the S0 ticket. Start needs the `v1.4.0` tag and 30 GB of free disk (T-65).
3. If Tellurion is forked: measure how much style and code removal costs, then rewrite the spec around the fork.

## Open

- Disk: 13 GB free of 460 GB; S0 needs about 30 GB (T-65).
- `main` is 15 commits behind `upstream/main`; base decision is the `v1.4.0` tag (due 2026-10-23).
