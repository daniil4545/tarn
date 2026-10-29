// The tarn CLI as agents and people use it: open, ls, new, run, wait, read, close
// (docs/specs/agent-cli.md 4). None of these moves focus or presses Enter. `new` and `run` open a
// split below the caller, or to its right with --right; the demo pane is a shell: `new` does not
// run the command, `run` types it at the prompt and leaves Enter to the user.
const USAGE =
  "usage: tarn <open path[:line] | ls [--json] | new [--right] [--cwd D] -- <cmd...> | run [--right] [--cwd D] -- <cmd...> | wait <pane> [--timeout S] | read <pane> [--lines N] | close <pane>>";

function open(ctx) {
  const arg = ctx.args[1];
  if (!arg) return ctx.out(USAGE);
  const match = /^(.*):(\d+)$/.exec(arg);
  const typed = match && ctx.vfs.isFile(ctx.vfs.resolve(ctx.cwd, match[1])) ? match[1] : arg;
  const path = ctx.vfs.resolve(ctx.cwd, typed);
  if (!ctx.vfs.isFile(path)) return ctx.out(`tarn: no such file: ${arg}`);
  if (!ctx.viewerOn()) return ctx.out("tarn: the file viewer is off");
  ctx.emit("viewer.open", { path, line: typed === arg ? undefined : Number(match[2]) });
  return undefined;
}

const COLUMNS = ["pane", "tab", "group", "title", "cwd", "process", "branch", "state"];

// The form of WezTerm `cli list`: a header, columns padded to the widest cell, `-` for empty.
function list(ctx) {
  const rows = ctx.panes();
  if (ctx.args.includes("--json")) return ctx.out(JSON.stringify({ ok: true, panes: rows }, null, 2));
  const table = [COLUMNS.map((c) => c.toUpperCase()), ...rows.map((r) => COLUMNS.map((c) => r[c] || "-"))];
  const wide = COLUMNS.map((_, i) => Math.max(...table.map((cells) => cells[i].length)));
  const line = (cells) => cells.map((c, i) => (i < cells.length - 1 ? c.padEnd(wide[i]) : c)).join("  ");
  return ctx.out(table.map(line).join("\n"));
}

function split(ctx) {
  const args = ctx.args.slice(1);
  const end = args.indexOf("--");
  const options = end < 0 ? args : args.slice(0, end);
  const command = end < 0 ? [] : args.slice(end + 1);
  const known = options.every((o, i) => o === "--right" || o === "--cwd" || options[i - 1] === "--cwd");
  if (!command.length || !known) return ctx.out(USAGE);
  const data = { right: options.includes("--right") };
  if (ctx.args[0] === "run") data.typed = command.join(" ");
  const pane = ctx.emit("pane.new", data);
  if (pane) ctx.out(pane);
  return undefined;
}

// A demo pane runs no command and is always idle: the wait answers at once, as on an idle shell pane.
function wait(ctx) {
  const id = ctx.args.slice(1).find((a, i, all) => !a.startsWith("--") && all[i - 1] !== "--timeout");
  if (!id) return ctx.out(USAGE);
  if (!ctx.panes().some((r) => r.pane === id)) return ctx.out(`tarn: no pane matched: ${id}`);
  return ctx.out("succeed  exit 0  0.0s");
}

// A pane of the caller's workspace, or the refusal the app gives (exit 4, never a fallback).
function target(ctx, id) {
  if (ctx.panes().some((r) => r.pane === id)) return id;
  ctx.out(`tarn: no pane matched: ${id}`);
  return undefined;
}

// herdr `pane read --lines N`: the last lines, default 80, the empty rows below the output cut.
function read(ctx) {
  const args = ctx.args.slice(1);
  const at = args.indexOf("--lines");
  const count = at < 0 ? "80" : args[at + 1];
  const rest = at < 0 ? args : args.filter((_, i) => i !== at && i !== at + 1);
  if (rest.length !== 1 || count === undefined) return ctx.out(USAGE);
  if (!/^[1-9][0-9]*$/.test(count)) return ctx.out("tarn: bad lines");
  if (!target(ctx, rest[0])) return undefined;
  const lines = String(ctx.emit("pane.read", { id: rest[0] })).split("\n").map((l) => l.trimEnd());
  while (lines.length && !lines[lines.length - 1]) lines.pop();
  if (lines.length) ctx.out(lines.slice(-Number(count)).join("\n"));
  return undefined;
}

function close(ctx) {
  if (ctx.args.length !== 2) return ctx.out(USAGE);
  if (target(ctx, ctx.args[1])) ctx.emit("pane.close", { id: ctx.args[1] });
  return undefined;
}

export function tarn(ctx) {
  const sub = ctx.args[0];
  switch (sub) {
    case "open": return open(ctx);
    case "ls": return list(ctx);
    case "new":
    case "run": return split(ctx);
    case "wait": return wait(ctx);
    case "read": return read(ctx);
    case "close": return close(ctx);
    default: return ctx.out(USAGE);
  }
}
