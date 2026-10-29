# tarn @VERSION@: the terminal you run in

You run inside a tarn terminal, so the `tarn` command is on `PATH`. It works on the panes of your
own group, or only your own tab when it is ungrouped; your pane is `$TARN_SURFACE`. Pane ids come from `tarn ls`
and from the output of `tarn new` and `tarn run`. An error prints `tarn: <text>` on stderr; exit 1,
or 4 when a pane id matches no pane.

## Rules

- You never move focus and never press Enter for the user; no command does.
- Asking the user to open a file is wrong: run `tarn open <path>`.
- Watch long work in `tarn new`. A command the user must approve goes into `tarn run`, then
  `tarn wait` as a background task; tell the user which pane waits.
- A server never ends: do not `wait` on it, `read` it.
- `tarn wait` exit 6: tell the user the message verbatim, read the pane, do not sleep and retry.
- Close only panes you opened, never your own, after you have read the result. Leave the pane of a
  failed command and of a server open until the user says.
- To talk to another agent use `SendMessage`, never a pane.

## Commands

`tarn open <path>` opens a text file in the viewer next to the terminal; prints nothing.

`tarn notify <text>` marks your session and notifies the user.

`tarn ls [--json]` lists the terminal panes of your group (only your own tab when ungrouped): `PANE TAB GROUP TITLE CWD PROCESS BRANCH
STATE`; `GROUP` is the group name or `-` when ungrouped. JSON adds `group` (name or null) and
`folder` (workspace folder path or null; a plain group has no folder).
`STATE` is the agent state of a pane that runs an agent, else `-`.

`tarn new [--right] [--cwd D] -- <cmd...>` opens a split below your pane (`--right`: to the right)
that runs the command, and prints its pane id. After the command exits the last screen stays.
Arguments after `--` are the program and its arguments; several commands need `sh -c "a && b"`.
`--cwd` defaults to your pane's directory.
`--tab` on `new` or `run` opens an unselected tab right below yours in its group; ungrouped: `tarn: put this tab in a group first`.
`--title NAME` on `new` or `run` names the tab and requires `--tab`.

`tarn run [--right] [--cwd D] -- <cmd...>` opens the same split with a shell and the command typed
but not submitted, and prints its pane id. The user reads it and presses Enter. A command with a
newline or another control character is refused.

`tarn wait <pane> [--timeout S] [--json]` blocks until the command in the pane ends and prints
`<state>  exit <code>  <duration>`; the state is `succeed`, `error` or `closed` (the user closed the
pane: do not retry). Run it as a background task. Exit 6: the pane cannot report the code (a
`tarn new` pane: `exit code unknown`; a shell without integration: `no shell integration`); exit 9:
timeout. The output is not in the reply: `tarn read` it.

`tarn read <pane> [--lines N]` prints the last N lines (default 80) of the pane's screen and
scrollback as plain text.

`tarn close <pane>` closes the pane at once, whatever runs in it.

`tarn module ls [--json]` lists the tarn modules (sidebar, viewer, permission card,
notifications) and their state: `on`, `off`, or `unavailable` when a module it needs is off.

`tarn skill` prints this text.

## Examples

```sh
tarn open docs/report.md
id=$(tarn new -- npm test)          # then: tarn read "$id" --lines 40
id=$(tarn run -- sudo make install) # then, as a background task: tarn wait "$id"
```
