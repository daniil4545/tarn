# tarn

An agent-first terminal for macOS, built on [Ghostty](https://ghostty.org): every tab in a sidebar,
tabs with a coding agent grouped by project, and the state of each Claude Code session at a glance.

tarn is an unofficial fork of Ghostty and is not affiliated with the Ghostty project; see
[NOTICE.md](NOTICE.md).

## Stage

Preview [`tarn-v0.0.1`](https://github.com/daniil4545/tarn/releases/tag/tarn-v0.0.1), built from
source. What works:

- a vertical sidebar in place of the tab bar, resizable, collapsible to icons;
- agent groups: a tab running `claude`, `codex` or `opencode` joins the group of its project;
- Claude Code state as a colored dot: working, needs permission, asks a question, done, error;
- a card on hover that answers a permission request or a question with one click.

Not in yet: `tarn` CLI and notifications.

## Install

Download `tarn-<version>-macos.zip` from the releases page, move `Tarn.app` to `/Applications` and run
`xattr -dr com.apple.quarantine /Applications/Tarn.app` (the build is ad-hoc signed, not notarized).
Tarn installs next to Ghostty and reads the same config. Full steps, the Claude Code plugin, zsh
setup and upgrades: [docs/install.md](docs/install.md).

## Build from source

Requirements: macOS, Xcode and Zig as listed in [HACKING.md](HACKING.md), [Nushell](https://www.nushell.sh)
for the build script, Claude Code for agent state.

`zig build run` is not used on macOS (it looks for `Ghostty.app`).

1. Build the app: `macos/build.nu --configuration Debug --action build`
2. Open `macos/build/Debug/Tarn.app`.
3. Add the plugin: `claude plugin marketplace add <path to this repo>/plugin`, then
   `claude plugin install tarn@tarn`.
4. Start `claude` in a tab of the app: its dot turns blue while it works.

Tests: `macos/build.nu --action test`; hook contract: `python3 -I plugin/test/hook_test.py`.

## Documents

| Question | Where |
|---|---|
| what tarn is for and why it is built this way | [docs/spec.md](docs/spec.md) |
| how it is built and where things live | [docs/architecture.md](docs/architecture.md) |
| what changed in each release | [CHANGELOG.md](CHANGELOG.md) |
| ported code and its licenses | [THIRD_PARTY.md](THIRD_PARTY.md) |
| building and hacking on the Ghostty base | [HACKING.md](HACKING.md) |

## License

MIT, as Ghostty: [LICENSE](LICENSE).
