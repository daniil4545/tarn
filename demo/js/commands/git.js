// git status | log | branch, answered from the vfs: dirty files follow the edits, history is canned.
import { red, yellow } from "../shell/ansi.js";

const NOT_A_REPO = "fatal: not a git repository (or any of the parent directories): .git";
const LABEL = { " M": "modified:   ", " D": "deleted:    " };

function status(ctx, branch, entries, short) {
  if (short) return entries.length ? ctx.out(entries.map((e) => `${e.code} ${e.path}`).join("\n")) : undefined;
  const lines = [`On branch ${branch}`];
  const changed = entries.filter((e) => e.code !== "??");
  const untracked = entries.filter((e) => e.code === "??");
  if (changed.length) {
    lines.push("Changes not staged for commit:", '  (use "git add <file>..." to update what will be committed)');
    lines.push(...changed.map((e) => red(`\t${LABEL[e.code]}${e.path}`)), "");
  }
  if (untracked.length) {
    lines.push("Untracked files:", ...untracked.map((e) => red(`\t${e.path}`)), "");
  }
  lines.push(entries.length ? 'no changes added to commit (use "git add" and/or "git commit -a")' : "nothing to commit, working tree clean");
  return ctx.out(lines.join("\n"));
}

function log(ctx, root, oneline) {
  const commits = ctx.vfs.read(`${root}/.git/log`).trim().split("\n").map((l) => [l.slice(0, 7), l.slice(8)]);
  const text = commits.map(([hash, subject]) => (oneline
    ? `${yellow(hash)} ${subject}`
    : `${yellow(`commit ${hash}`)}\nAuthor: ${ctx.identity.user}\nDate:   Sun Oct 25 12:34:00 2026\n\n    ${subject}\n`));
  ctx.out(text.join("\n"));
}

export function git(ctx) {
  const root = ctx.vfs.gitRoot(ctx.cwd);
  const [sub, ...flags] = ctx.args;
  if (!["status", "log", "branch"].includes(sub)) return ctx.out("usage: git <status|log|branch>");
  if (!root) return ctx.out(NOT_A_REPO);
  const branch = ctx.vfs.gitBranch(ctx.cwd);
  if (sub === "branch") return ctx.out(`* ${branch}`);
  if (sub === "log") return log(ctx, root, flags.includes("--oneline"));
  return status(ctx, branch, ctx.vfs.gitStatus(ctx.cwd), flags.includes("-s") || flags.includes("--short"));
}
