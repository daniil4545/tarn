# lull - agent context

## Project

lull is an agent-first terminal for macOS, a fork of Ghostty. It keeps the Ghostty core and app and adds a narrow set of features for working with CLI coding agents, Claude Code first. The user decides; the canon for behavior is `docs/spec.md`, for structure `docs/architecture.md` (created in stage S0). The project is public: code, docs, commits and this file are in English.

`AGENTS.md` and `README.md` at the root belong to upstream Ghostty and stay untouched to keep upstream merges clean. Use the commands from `AGENTS.md`; never open issues or PRs against `ghostty-org/ghostty`.

## Principles

- Simplicity: a part stays only if something breaks without it. Features outside `docs/spec.md` section 1 are cut, not hidden behind a setting.
- Speed: startup, input latency and memory stay at the level of upstream Ghostty built from the same commit; `make bench` decides, not impressions.
- Agent-first: everything the user does by mouse, an agent can do through the `lull` CLI.
- Local only: no account, cloud, telemetry, subscription or built-in AI model.

## Stack

Zig core and Swift macOS app from upstream; our code is Swift. Versions: `build.zig.zon` (`minimum_zig_version`), Xcode per `HACKING.md`.

## Structure

| Path | Role |
| --- | --- |
| `src/` | Ghostty core (Zig), upstream, not modified |
| `macos/` | Ghostty macOS app (Swift), upstream |
| `macos/Sources/Features/Lull/` | our code: session registry, sidebar, file panel, control socket |
| `docs/` | our docs: spec, architecture, research |

## Commands

| What | Command |
| --- | --- |
| build core | `zig build -Demit-macos-app=false` |
| build app | `zig build` |
| core tests | `zig build test -Dtest-filter=<name>` |
| Swift lint | `swiftlint lint --strict` |
| acceptance | `make check` (stage S0) |
| benchmark | `make bench` (stage S0) |

## Workflow

Project profile for `~/.claude/docs/pipeline.md`:

| Parameter | Value |
| --- | --- |
| Autonomy | agent decides technical questions within the spec; behavior questions, irreversible steps and spending subscription limits go to the user |
| Subagents | a stage runs through `orchestrate`: plan, `spec-reviewer`, workers, `code-reviewer` thorough, `skeptic` by `regress` |
| Tracker | `tk`, project `lull`; stage plan in `docs/plans/<stage>.md` |
| Subagent brief | `~/.claude/templates/subagent-brief.md` |
| Findings file | `docs/findings.jsonl` |

- Branches: a stage goes in `s<N>-<name>`; merge into `main` on acceptance with the user's confirmation.
- Upstream: `upstream/main` is merged into `main` on a schedule, one merge commit; conflicts at insertion points get their own commit.
- Hosting: GitHub `daniil4545/lull`. CI: none of ours yet; upstream workflows are not relied on.

## Critical invariants

- `src/` is not modified; Swift changes outside `macos/Sources/Features/Lull/` only at insertion points listed in `docs/architecture.md`.
- No network calls, telemetry or accounts in our code.
- Ported code keeps its license header and an entry in `THIRD_PARTY.md`; no GPL, BSL or unlicensed code.
- `lull hook` never blocks or fails an agent: when the app is not running it exits 0 within 100 ms.
- The session registry is the only writer of session state.
