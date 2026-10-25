// The tarn CLI as agents and people use it: open, ls, new (docs/spec.md section 11).
// None of these moves focus or presses Enter. The app has no `tarn` CLI yet (only the socket command
// that opens a file), so the demo says so: --help and the first run of each subcommand print PLANNED.
const PLANNED = "planned: not in the app yet";
const USAGE = "usage: tarn <open path[:line] | ls [--json] | new>";

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

const HELP = new Set([undefined, "--help", "-h", "help"]);

export function tarn(ctx) {
  const sub = ctx.args[0];
  const key = HELP.has(sub) ? "--help" : sub;
  if (key === "--help" || !ctx.planned.has(key)) {
    ctx.planned.add(key);
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
