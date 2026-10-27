# tarn - agent context

## Project

tarn is an agent-first terminal for macOS, a fork of Ghostty. It keeps the Ghostty core and app and adds a narrow set of features for working with CLI coding agents, Claude Code first. The user decides; the canon for behavior is `docs/spec.md`, for structure `docs/architecture.md`. The project is public: code, docs, commits and this file are in English.

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
| `macos/Sources/Features/Tarn/` | our code: control socket, session registry, sidebar, workspaces, layout, viewer pane, settings, attention |
| `macos/Tests/Tarn/` | our tests |
| `cli/` | the `tarn` command (POSIX sh) and its tests |
| `plugin/` | Claude Code plugin: hook scripts and the hook test |
| `demo/` | static browser demo of the window and its checks |
| `viewer-web/` | sources of the viewer page bundle |
| `tools/` | GIF capture, viewer bundle sync, benchmark |
| `install.sh` | the installer `curl ... \| sh` runs |
| `tarn.mk` | our make targets `check`, `release` and `bench` |
| `docs/` | our docs: spec, architecture, install guide, module documents |

## Commands

| What | Command |
| --- | --- |
| build core library | `zig build -Demit-macos-app=false` |
| build app | `macos/build.nu --configuration Debug --action build` |
| app tests | `macos/build.nu --action test` |
| Swift lint | `swiftlint lint --strict` (in `macos/`) on `Sources/Features/Tarn` and `Tests/Tarn` |
| shell lint | `shellcheck plugin/hooks/*.sh install.sh cli/tarn cli/test/install_test.sh` |
| Python lint | `uvx ruff check` and `uvx ruff format --check` on `plugin/test/` |
| spelling | `typos` on our files (`git diff --name-only origin/main...HEAD`) |
| hook invariant | `python3 -I plugin/test/hook_test.py` |
| CLI and installer tests | `python3 -I cli/test/cli_test.py`, `sh cli/test/install_test.sh` |
| viewer bundle | `node --test viewer-web/licenses.test.mjs`, `uv run --with playwright python -I viewer-web/test-mermaid.py` |
| acceptance | `make -f tarn.mk check` |
| task worktree | `make -f tarn.mk worktree NAME=<branch>` in the main checkout: branch from `origin/dev`, links to the built core |
| dev build | `make -f tarn.mk dev`: Debug `Tarn.app` without coverage, 4 jobs, log `macos/build/dev.log` |
| stand | `make -f tarn.mk live [STAND_APP=<built Tarn.app>]`: a second Tarn with its own socket; prints `HOME` and `TARN_SURFACE` for `cli/tarn`; `sh tools/stand/stand.sh stop` |
| drive the stand | `sh tools/stand/drive.sh type\|key\|action\|screen\|shot\|tarn ...`; the path is skill `stand` |
| release build | `make -f tarn.mk release` (ad-hoc signed `dist/tarn-<version>-macos.zip` with `.sha256`) |
| benchmark | `make -f tarn.mk bench` (report `docs/bench.md`) |
| demo checks | `uv run --with playwright python -I demo/test/check_{0,a,b,c,e2e,review,modules}.py` and `node --test demo/test/unit` (installed Chrome; how to run: `demo/README.md`) |

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
- Behavior comes from analogs (user decision 2026-10-27). Before a spec states how a feature behaves (a command's semantics, a wait rule, an exit code, an output format, a refusal), find how analogs do it and take their behavior; each rule in the spec names its source. Own behavior only where no analog has one, with the line "Prior art: searched where - found what", and the user decides. This applies to specs and answers, not only to code.
- No own mechanism where an analog exists. Before the first line of code of a feature or a fix of a mechanism, the plan names the analog project, file and commit it follows (analog base: OpenViking `agent-terminal/docs/research/landscape*`, then GitHub). No analog found: the plan says "Prior art: searched where - found what" and the user decides. A second fix of our own mechanism stops the work: survey the analogs again before a third.
- Branches (user decision 2026-10-26): `dev` is the working branch, every task branch starts from `origin/dev` and its PR goes into `dev` (`gh pr create --base dev`); the agent merges it after review without waiting for CI. One small PR at a time.
- Agent testing (user decision 2026-10-27): the agent builds dev apps and runs the checks itself, live on the stand by skill `stand`: build, drive, read the screen as text and screenshots. After merges into `dev` it runs the dev build check of that skill.
- Acceptance (user decision 2026-10-27): before a merge the agent checks the change live on the stand (`make -f tarn.mk live`) and posts the result as a `Stand:` line in the PR, next to the `Review:` line; `~/.claude/scripts/merge-gate.py` merges only with both. The user checks by hand once per batch: after several PRs, one `dev` build, everything changed since the last hand check. Parallel windows take items of `docs/plans/<milestone>.toml` from `plan.py ready`. `main` takes only release PRs from `dev`, on the user's command, with the full CI green.
- Work record is the GitHub PR (user decision 2026-10-25): acceptance and review remarks, blocking questions and their answers go as comments on the PR, not into files or session messages; a peer session is pointed to the comment link.
- Upstream: `upstream/main` is merged into `main` on a schedule, one merge commit; conflicts at insertion points get their own commit.
- Hosting: GitHub `daniil4545/tarn`. CI: `tarn-ci.yml` runs the demo checks (Linux, about 5 min) on PRs and pushes to `dev`, nothing waits on them; on PRs and pushes to `main` it also runs `make -f tarn.mk check` (runner `xcode-27`, about 11 min), and `main` merges only with both green. A tag `tarn-v<version>` builds the release zip in `tarn-release.yml` and attaches it to the release (a missing one is created as a draft); a failed build reruns by `gh workflow run tarn-release.yml -f tag=<tag>`, never by moving the tag; release notes stay hand-written. `tarn-upstream.yml` runs the same CI weekly on `main` with `upstream/main` merged in, as an early warning. Upstream workflows are disabled in the repository settings; a new one an upstream merge brings starts enabled, disable it. `gh` resolves to `ghostty-org/ghostty` by default: always pass `-R daniil4545/tarn`.
- Linters: upstream gets `typos` and `prettier` from `nix develop`; here they come from brew. `prettier` is not run on our markdown: padded tables push `docs/` over its size limits.

## Critical invariants

- Boundary with Ghostty (user decision 2026-10-25):
  1. The Zig core (`src/`, `include/`, `build.zig`) is never modified.
  2. Ghostty's Swift files change only for identity (names, plist, icons, updater off) and for insertion points: a call into our code with no logic of its own, each listed in `docs/architecture.md`.
  3. Ghostty's behavior is changed by our layer on top (overlay, subclass, delegate, config), never by editing the logic of its file.
  4. When a layer on top cannot do it, the user decides case by case, with the reason the layer fails.
- No network calls, telemetry or accounts in our code.
- `hook.sh` never blocks or fails an agent: for any input it exits 0 within 100 ms and prints nothing. The one exception is `permission.sh` (the `PermissionRequest` hook), which waits for the card while the app holds its connection (`docs/spec.md` 2.3).
- Nothing edits `~/.claude/settings.json`; hooks ship as a Claude Code plugin.
- No agent command moves focus or presses Enter for the user.
- The session registry is the only writer of session state.
