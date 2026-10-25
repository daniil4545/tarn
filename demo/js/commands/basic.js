// Small commands: echo clear whoami date sleep help exit.
const HELP = `tarn demo shell. Commands:
  ls cd pwd cat head echo mkdir touch rm clear sleep whoami date exit
  git status | log | branch
  tarn open <path>[:line] | ls [--json] | new
  claude            a scripted Claude Code session
Pipes, redirects and globs are not part of the demo.`;

function echo(ctx) {
  const noNewline = ctx.args[0] === "-n";
  const text = (noNewline ? ctx.args.slice(1) : ctx.args).join(" ");
  if (noNewline) ctx.write(text.replace(/\n/g, "\r\n"));
  else ctx.out(text);
}

function sleep(ctx) {
  const seconds = Number(ctx.args[0]);
  if (!(seconds >= 0)) return ctx.out("usage: sleep seconds");
  const done = ctx.hold({});
  ctx.after(seconds * 1000, () => done(0));
  return undefined;
}

export const BASIC_COMMANDS = {
  echo,
  sleep,
  clear: (ctx) => ctx.clearScreen(),
  whoami: (ctx) => ctx.out(ctx.identity.user),
  date: (ctx) => ctx.out(new Date(ctx.now()).toString().replace(/ GMT.*/, "")),
  help: (ctx) => ctx.out(HELP),
  exit: (ctx) => ctx.exit(),
};
