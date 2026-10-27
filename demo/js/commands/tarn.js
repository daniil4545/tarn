// The tarn CLI as agents and people use it: open, ls, new (docs/specs/agent-cli.md 4).
// None of these moves focus or presses Enter. `new` opens a split below the caller, or to its
// right with --right; the demo pane is a shell, it does not run the command.
const USAGE = "usage: tarn <open path[:line] | ls [--json] | new [--right] [--cwd D] -- <cmd...>>";

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

const COLUMNS = ["pane", "tab", "title", "cwd", "process", "branch", "host", "state"];

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
  const pane = ctx.emit("pane.new", { right: options.includes("--right") });
  if (pane) ctx.out(pane);
  return undefined;
}

export function tarn(ctx) {
  const sub = ctx.args[0];
  switch (sub) {
    case "open": return open(ctx);
    case "ls": return list(ctx);
    case "new": return split(ctx);
    default: return ctx.out(USAGE);
  }
}
