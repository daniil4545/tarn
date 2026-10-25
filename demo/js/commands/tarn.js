// The tarn CLI as agents and people use it: open, ls, new (docs/spec.md section 11).
// None of these moves focus or presses Enter.
const USAGE = "usage: tarn <open path[:line] | ls [--json] | new>";

function open(ctx) {
  const arg = ctx.args[1];
  if (!arg) return ctx.out(USAGE);
  const match = /^(.*):(\d+)$/.exec(arg);
  const typed = match && ctx.vfs.isFile(ctx.vfs.resolve(ctx.cwd, match[1])) ? match[1] : arg;
  const path = ctx.vfs.resolve(ctx.cwd, typed);
  if (!ctx.vfs.isFile(path)) return ctx.out(`tarn: no such file: ${arg}`);
  ctx.emit("viewer.open", { path, line: typed === arg ? undefined : Number(match[2]) });
  return undefined;
}

function list(ctx) {
  const rows = ctx.sessions();
  if (ctx.args.includes("--json")) {
    return ctx.out(JSON.stringify(rows.map(({ age, ...row }) => row), null, 2));
  }
  if (!rows.length) return ctx.out("no agent sessions");
  const wide = (key) => Math.max(...rows.map((r) => String(r[key]).length));
  const [project, branch, state] = [wide("project"), wide("branch"), wide("state")];
  return ctx.out(rows.map((r) => [
    String(r.tab).padEnd(2),
    r.project.padEnd(project),
    r.branch.padEnd(branch),
    r.state.padEnd(state),
    r.age,
  ].join("  ")).join("\n"));
}

export function tarn(ctx) {
  switch (ctx.args[0]) {
    case "open": return open(ctx);
    case "ls": return list(ctx);
    case "new":
      ctx.emit("tab.new", {});
      return undefined;
    default: return ctx.out(USAGE);
  }
}
