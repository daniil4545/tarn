// The tarn CLI as agents and people use it: open, ls, new (docs/spec.md section 11).
// None of these moves focus or presses Enter. `open` and `ls` (panes of this workspace) are in the app;
// `new` is second wave (R15), so its first run prints PLANNED.
const PLANNED = "planned: not in the app yet";
const USAGE = "usage: tarn <open path[:line] | ls [--json] | new (planned)>";

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

export function tarn(ctx) {
  const sub = ctx.args[0];
  if (sub === "new" && !ctx.planned.has(sub)) {
    ctx.planned.add(sub);
    ctx.out(PLANNED);
  }
  switch (sub) {
    case "open": return open(ctx);
    case "ls": return list(ctx);
    case "new":
      ctx.emit("tab.new", {});
      return undefined;
    default: return ctx.out(USAGE);
  }
}
