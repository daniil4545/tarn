# Plan: S0 core

Status: draft, waiting for the user on the base tag and disk space (section 2).
Canon: `docs/spec.md` (sections 1, 2.1, 7, 13, 14); `HACKING.md`; `macos/AGENTS.md`; `.claude/CLAUDE.md`.
Inputs: research `agent-terminal/docs/research/landscape.md` and `code-sources.md` (merged on 2026-10-22).

## 1. Goal and scope

- Goal: a fork that builds from source, runs next to the installed Ghostty and has numbers to compare against. S1-S3 then add code without guessing where it goes.
- Result: `tarn.app` builds with `macos/build.nu`; `make -f tarn.mk check` is green; `make -f tarn.mk bench` prints tarn against upstream from the same commit; R1, R2, R12 checked by eye; `docs/architecture.md` lists the insertion points for S1-S3.
- In: toolchain, base tag, app identity, `tarn.mk`, benchmark, eye checks, zsh guide (R7), architecture doc.
- Out: any feature code (socket, CLI, panel, sidebar); CI; signing and notarization; Linux.

## 2. Decisions

- Base on the release tag `v1.4.0`, not on `upstream/main`. Why: `main` is a moving target (3164 commits since `v1.3.1`), and agent forks track tags (Tellurion `update-ghostty.sh`). `v1.3.1` is rejected: Zig 0.15.2, AppleScript API that 1.4 changes, 3164 commits back. If `v1.4.0` is not tagged by 2026-10-27, start on `main` at the 1.4 milestone head and move to the tag when it lands. Affects: spec 2.1 rule 2 ("merge `upstream/main` on a schedule" becomes "merge each release tag"); needs the user's yes. Model of the system: yes.
- App identity: bundle id `dev.tarn.app`, product name `tarn`, Debug `dev.tarn.app.debug`. Why: the installed Ghostty (`/Applications/Ghostty.app`, `com.mitchellh.ghostty`) must keep its own notifications, privacy grants and defaults. The Ghostty config file (`~/.config/ghostty/config`) stays shared on purpose. Affects: one insertion point in `macos/Ghostty.xcodeproj/project.pbxproj`. Model: no.
- Zig from Homebrew at the version `build.zig.zon` of the tag names. Why: Tellurion reports that the ziglang.org build fails to link against macOS 26.4+ SDKs. Model: no.
- Disk: at least 30 GB free before the first build (now 13 GB of 460 GB). Two release builds (tarn and upstream) plus Zig and Xcode caches. Not measured yet; S0.2 records the real size. Needs the user.
- Load: every build and bench runs under `nice -n 10` with at most 4 jobs (`zig build -j4`, `xcodebuild -jobs 4`).

## 3. Steps

| Step | Result | Check |
| --- | --- | --- |
| S0.1 Toolchain | zig, nushell, swiftlint from Homebrew; Xcode 27.0 accepted by the build or the gap named | `zig version`, `nu --version`, `swiftlint version`, `xcodebuild -version` |
| S0.2 Base | branch `s0-core` = tag + our docs commits rebased on top | `git log --oneline v1.4.0..s0-core` shows only our commits |
| S0.3 Build | core library and app build in Debug and ReleaseLocal; clean and incremental build times and disk use recorded | app starts, opens a window, runs `zsh` |
| S0.4 Identity | bundle id and product name changed; tarn and Ghostty run at the same time | both apps open; notifications of each come from its own name |
| S0.5 `tarn.mk check` | `swiftlint lint --strict` on `macos/Sources/Features/Tarn/` and `macos/Tests/Tarn/`, `macos/build.nu --action test` | target exits 0 on a clean tree and 1 on a planted lint error |
| S0.6 `tarn.mk bench` | upstream built from the same tag into a scratch folder; four metrics below; report `docs/bench.md` | two runs in a row differ by less than the threshold |
| S0.7 Eye checks | checklist below passed, findings logged in the ticket | user confirms by eye |
| S0.8 zsh guide (R7) | `docs/zsh.md`: completion and history setup that works in tarn | user's zsh gets completion and history |
| S0.9 Architecture | `docs/architecture.md` from `~/.claude/templates/architecture.md` with the insertion point list | every S1-S3 need from spec section 2 maps to a file and symbol of the tag |

### Benchmark metrics (S0.6)

| Metric | How | Threshold, tarn against upstream |
| --- | --- | --- |
| Startup | launch to first window, 10 runs, median; AppleScript polls for the window | +5% |
| Idle CPU | 5 tabs, 60 s idle, `ps -o %cpu` every second, mean | +0.5 percentage points |
| Memory | RSS after 60 s with 5 tabs | +5% |
| Output throughput | `cat` of a 100 MB file in one surface, wall time, 5 runs, median | +5% |
| Input latency | no automated tool chosen; S0.6 looks for one (typometer and others); if none fits, a manual run before each release | +1 ms |

S0 has no feature code, so tarn equals upstream within noise; S0 proves that the harness measures, and S1-S3 rerun it.

### Eye checklist (S0.7)

1. R1: new tab, split right and down, close a split, move between splits by keyboard.
2. R2: Claude Code in a split, default mode and with `CLAUDE_CODE_NO_FLICKER=1`: the wheel and the trackpad scroll the transcript and do not type into the prompt; scrollback survives (Claude Code issues 43418, 42297).
3. R2: resize and zoom a split while Claude Code runs: no duplicate lines, the prompt stays in place (Reddit, 2026-06-16).
4. R2: `tix` TUI with mouse clicks and trackpad scroll.
5. R12: Claude Code prompt input: multi-line edit, word jumps with Option and arrows, paste of 200 lines.
6. Notifications: Claude Code's own notification reaches macOS from tarn (Claude Code issue 19979: silent with the ghostty channel).
7. Paste a macOS screenshot from the clipboard into Claude Code (Ghostty discussion 10478).
8. Claude Code in a project under `~/Documents` keeps file access for an hour with the new bundle id (Ghostty discussion 12947).
9. A Claude Code session of an hour with heavy output: no crash, memory stays flat (Ghostty discussion 14392, claude-chill).

### Insertion points to find (S0.9)

Each row needs a file and symbol in the tag; S0.9 reads where agent forks change the Swift app (Tellurion edits `SurfaceView_AppKit.swift` and `Ghostty.App.swift`; reading only, its code is AGPL).

| Need | Stage |
| --- | --- |
| app start and quit: create and remove the control socket | S1 |
| window layout: a side panel next to the terminal | S1 |
| path click in terminal output | S1 |
| per-surface environment: `TARN_SURFACE` | S2 |
| core events per surface: pwd, title, child exited, close, focus | S2 |
| window layout: the sidebar | S2 |
| terminal notifications (OSC 9, 777) before they are shown, to suppress them | S3 |
| keybinding for the jump action | S3 |

## 4. Scenarios

| ID | Scenario | Result |
| --- | --- | --- |
| S1 | Happy path: clean checkout, toolchain installed | `check` green, `bench` report written |
| S2 | Repeat: `bench` twice | the second run reuses the upstream build of the same tag, no rebuild |
| S3 | Temporary error: Xcode 27 rejects the project | stop, record the error, try `xcode-select` per `HACKING.md`; the ask goes to the user if Xcode 26 is needed |
| S4 | Permanent error: disk full during build | build stops, scratch upstream build removed, ask the user |
| S5 | Unexpected: anything else | log in the ticket with command and output; no workaround that touches `src/` |

Limits (never, for any input):

- L1: nothing under `src/` changes.
- L2: no step edits `~/.claude/settings.json` or the installed Ghostty.
- L3: no build runs above 4 jobs or outside `nice -n 10`.

## 5. Acceptance

- Command: `make -f tarn.mk check` exits 0.
- Bench: `make -f tarn.mk bench` writes `docs/bench.md` with both apps, the tag, machine, and the five metrics.
- Not automated: the eye checklist (user), input latency if no tool fits (user, before release).
- Not checked: Intel Macs, macOS below 26.

## 6. Spec edits this plan needs

Waiting for the user; applied in one commit after the yes.

1. 2.1 rule 2 and the Upstream line of `.claude/CLAUDE.md`: merge release tags instead of `upstream/main`.
2. Section 9, Ghostty build row: Zig version per tag; macOS 14 minimum from 1.4; upstream keeps a read-only GitHub mirror after its move (mitchellh.com, 2026-04-28).
3. Section 1, R2 evidence: the checklist rows 2-3 above.
4. `tk` becomes `tix` everywhere (tracker renamed on 2026-10-21).
