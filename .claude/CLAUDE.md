# tarn - agent context

## Project

tarn is an agent-first terminal for macOS, a fork of Ghostty. It keeps the Ghostty core and app and adds a narrow set of features for working with CLI coding agents, Claude Code first. The user decides; the canon for behavior is `docs/spec.md`, for structure `docs/architecture.md` (created in stage S0). The project is public: code, docs, commits and this file are in English.

`AGENTS.md`, `macos/AGENTS.md` and `Makefile` belong to upstream Ghostty and stay untouched to keep upstream merges clean. `README.md` and `NOTICE.md` are ours, as in other hard forks of Ghostty (Tellurion); on an upstream merge `README.md` keeps our version. Follow their build commands; never open issues or PRs against `ghostty-org/ghostty`.

## Principles

- Simplicity: a part stays only if something breaks without it. Features outside `docs/spec.md` section 1 are cut, not hidden behind a setting.
- Speed: startup, input latency, idle CPU and memory stay at the level of upstream Ghostty built from the same commit; `make -f tarn.mk bench` decides, not impressions.
- Agent-first: an agent opens files, lists sessions and asks for attention through the `tarn` CLI; focus and keystrokes stay with the human.
- Local only: no account, cloud, telemetry, subscription or built-in AI model.

## Stack

Zig core and Swift macOS app from upstream; our code is Swift. Versions: `build.zig.zon` (`minimum_zig_version`), Xcode per `HACKING.md`.

## Structure

| Path | Role |
| --- | --- |
| `src/` | Ghostty core (Zig), upstream, not modified |
| `macos/` | Ghostty macOS app (Swift), upstream |
| `macos/Sources/Features/Tarn/` | our code: control socket, session registry, sidebar, markdown panel |
| `macos/Tests/Tarn/` | our tests |
| `tarn.mk` | our make targets `check` and `bench` |
| `docs/` | our docs: spec, architecture |

## Commands

| What | Command |
| --- | --- |
| build core library | `zig build -Demit-macos-app=false` |
| build app | `macos/build.nu --configuration Debug --action build` |
| app tests | `macos/build.nu --action test` |
| Swift lint | `swiftlint lint --strict` (in `macos/`) on `Sources/Features/Tarn` and `Tests/Tarn` |
| shell lint | `shellcheck plugin/hooks/*.sh` |
| Python lint | `uvx ruff check` and `uvx ruff format --check` on `plugin/test/` |
| spelling | `typos` on our files (`git diff --name-only origin/main...HEAD`) |
| hook invariant | `python3 -I plugin/test/hook_test.py` |
| acceptance | `make -f tarn.mk check` (stage S0) |
| benchmark | `make -f tarn.mk bench` (stage S0) |
| demo checks | `uv run --with playwright python -I demo/test/check_{0,a,b,c,e2e}.py` and `node --test demo/test/unit` (installed Chrome; how to run: `demo/README.md`) |

## Workflow

Project profile for `~/.claude/docs/pipeline.md`:

| Parameter | Value |
| --- | --- |
| Autonomy | agent decides technical questions within the spec; behavior questions, irreversible steps and spending subscription limits go to the user |
| Subagents | a stage runs through `orchestrate`: plan, `spec-reviewer`, workers, `code-reviewer` thorough, `skeptic` by `regress` |
| Tracker | tix, project `tarn`; stage plan in `docs/plans/<stage>.md` |
| Subagent brief | `~/.claude/templates/subagent-brief.md` |
| Findings file | `docs/findings.jsonl` |

- Feature pipeline (user decision 2026-10-23): approve the feature, survey how other projects built it (read their code and architecture), approve our architecture, then write code. Take proven parts from other projects, then optimize and cut the excess; do not invent what exists. tarn stays MIT so anyone may reuse it (user decision 2026-10-25): copied code must be MIT or Apache-2.0; from GPL and AGPL projects (cmux, Tellurion) we follow structure and behavior and write the code ourselves; Warp is closed source, so only its behavior is followed.
- Demo first (user decision 2026-10-25): `demo/` is one living browser demo of the whole terminal, built features plus planned ones (the README of the demo lists which). A step that changes the UI is first drawn in the demo, the user approves the look, then it is built in the app; once built, the demo marks it as built. The checks in `demo/test/` walk its user paths and must pass before the demo goes to the user.
- Ghostty first (user decision 2026-10-25): we do not build our own systems next to Ghostty's. Before a feature or a mechanism, list what Ghostty already has for it (actions, config options, `SplitTree`, `SplitView`, undo, restore, menus, palette, notifications) with file:line, and build on that; our code only fills what Ghostty lacks. A parallel mechanism (own split tree, own undo, own title, own notification path) needs the user's yes with the reason Ghostty's cannot be used.
- No own mechanism where an analog exists. Before the first line of code of a feature or a fix of a mechanism, the plan names the analog project, file and commit it follows (analog base: OpenViking `agent-terminal/docs/research/landscape*`, then GitHub). No analog found: the plan says "Prior art: searched where - found what" and the user decides. A second fix of our own mechanism stops the work: survey the analogs again before a third.
- Branches: a stage goes in `s<N>-<name>`; merge into `main` on acceptance with the user's confirmation.
- Upstream: `upstream/main` is merged into `main` on a schedule, one merge commit; conflicts at insertion points get their own commit.
- Hosting: GitHub `daniil4545/tarn`. CI: none of ours yet; upstream workflows are not relied on. `gh` resolves to `ghostty-org/ghostty` by default: always pass `-R daniil4545/tarn`.
- Linters: upstream gets `typos` and `prettier` from `nix develop`; here they come from brew. `prettier` is not run on our markdown: padded tables push `docs/` over its size limits.

## Critical invariants

- `src/` is not modified; Swift changes outside `macos/Sources/Features/Tarn/` only at insertion points listed in `docs/architecture.md`.
- No network calls, telemetry or accounts in our code.
- Ported code keeps its license header and an entry in `THIRD_PARTY.md`; no GPL, AGPL, BSL or unlicensed code.
- `tarn hook` never blocks or fails an agent: for any input it exits 0 within 100 ms and prints nothing. The one exception is the `PermissionRequest` hook, which waits for the card while the app holds its connection (`docs/spec.md` 2.3).
- Nothing edits `~/.claude/settings.json`; hooks ship as a Claude Code plugin.
- No agent command moves focus or presses Enter for the user.
- The session registry is the only writer of session state.
