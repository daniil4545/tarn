// File commands over the vfs: ls cd pwd cat mkdir touch rm head.
import { blue, bold, width } from "../shell/ansi.js";

const MESSAGES = {
  ENOENT: "No such file or directory",
  EISDIR: "Is a directory",
  ENOTDIR: "Not a directory",
  EEXIST: "File exists",
};

// Runs `fn`; a vfs error becomes the one-line message of a real tool.
function guarded(ctx, label, arg, fn) {
  try {
    return fn();
  } catch (e) {
    if (!MESSAGES[e.code]) throw e;
    ctx.out(`${label}: ${arg}: ${MESSAGES[e.code]}`);
    return undefined;
  }
}

// Splits flags and operands: `ls -la docs` -> flags "la", operands ["docs"].
function options(args) {
  const flags = args.filter((a) => /^-[A-Za-z]+$/.test(a)).join("").replace(/-/g, "");
  return { flags, operands: args.filter((a) => !/^-[A-Za-z]+$/.test(a)) };
}

const DATE = new Intl.DateTimeFormat("en-US", { month: "short", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false });
const stamp = (ms) => DATE.formatToParts(ms).reduce((o, p) => ({ ...o, [p.type]: p.value }), {});

function longRow(ctx, dir, entry) {
  const path = `${dir}/${entry.name}`;
  const size = entry.dir ? 96 : ctx.vfs.read(path).length;
  const t = stamp(ctx.vfs.mtime(path));
  const label = entry.dir ? bold(blue(entry.name)) : entry.name;
  return `${entry.dir ? "drwxr-xr-x" : "-rw-r--r--"}  1 ${ctx.identity.user}  staff  ${String(size).padStart(6)} ${t.month} ${t.day} ${t.hour}:${t.minute} ${label}`;
}

// Entries in columns, filled down the column as BSD ls does.
function columns(entries, total) {
  const labels = entries.map((e) => ({ raw: e.name, shown: e.dir ? bold(blue(e.name)) : e.name }));
  const cell = Math.max(...labels.map((l) => width(l.raw))) + 2;
  const perRow = Math.max(1, Math.floor(total / cell));
  const rows = Math.ceil(labels.length / perRow);
  const lines = [];
  for (let r = 0; r < rows; r++) {
    let line = "";
    for (let c = r; c < labels.length; c += rows) line += labels[c].shown + " ".repeat(cell - width(labels[c].raw));
    lines.push(line.trimEnd());
  }
  return lines.join("\n");
}

function ls(ctx) {
  const { flags, operands } = options(ctx.args);
  const targets = operands.length ? operands : ["."];
  targets.forEach((arg, i) => guarded(ctx, "ls", arg, () => {
    const path = ctx.vfs.resolve(ctx.cwd, arg);
    if (targets.length > 1 && ctx.vfs.isDir(path)) ctx.out(`${i ? "\n" : ""}${arg}:`);
    const dir = ctx.vfs.isDir(path);
    if (!dir && !ctx.vfs.isFile(path)) throw Object.assign(new Error(path), { code: "ENOENT" });
    const parentDir = path.slice(0, path.lastIndexOf("/")) || "/";
    let entries = dir ? ctx.vfs.list(path) : [{ name: arg, dir: false }];
    if (!flags.includes("a")) entries = entries.filter((e) => !e.name.startsWith("."));
    if (!entries.length) return;
    const base = dir ? path : parentDir;
    if (flags.includes("l")) ctx.out(entries.map((e) => longRow(ctx, base, dir ? e : { ...e, name: path.slice(base.length + 1) })).join("\n"));
    else if (flags.includes("1")) ctx.out(entries.map((e) => e.name).join("\n"));
    else ctx.out(columns(entries, ctx.cols()));
  }));
}

function cd(ctx) {
  const arg = ctx.args[0] ?? "~";
  const target = arg === "-" ? ctx.previous : ctx.vfs.resolve(ctx.cwd, arg === "~" ? ctx.identity.home : arg);
  if (ctx.vfs.isDir(target)) return ctx.cd(target);
  ctx.out(`cd: ${ctx.vfs.isFile(target) ? "not a directory" : "no such file or directory"}: ${arg}`);
  return undefined;
}

function cat(ctx) {
  for (const arg of ctx.args) {
    guarded(ctx, "cat", arg, () => ctx.out(ctx.vfs.read(ctx.vfs.resolve(ctx.cwd, arg)).replace(/\n$/, "")));
  }
}

function head(ctx) {
  const n = ctx.args[0] === "-n" ? Number(ctx.args[1]) : 10;
  const files = ctx.args[0] === "-n" ? ctx.args.slice(2) : ctx.args;
  for (const arg of files) {
    guarded(ctx, "head", arg, () => ctx.out(ctx.vfs.read(ctx.vfs.resolve(ctx.cwd, arg)).split("\n").slice(0, n).join("\n")));
  }
}

function mkdir(ctx) {
  const { flags, operands } = options(ctx.args);
  for (const arg of operands) guarded(ctx, "mkdir", arg, () => ctx.vfs.mkdir(ctx.vfs.resolve(ctx.cwd, arg), { parents: flags.includes("p") }));
}

function touch(ctx) {
  for (const arg of ctx.args) {
    guarded(ctx, "touch", arg, () => {
      const path = ctx.vfs.resolve(ctx.cwd, arg);
      ctx.vfs.write(path, ctx.vfs.isFile(path) ? ctx.vfs.read(path) : "");
    });
  }
}

function rm(ctx) {
  const { flags, operands } = options(ctx.args);
  for (const arg of operands) {
    const path = ctx.vfs.resolve(ctx.cwd, arg);
    if (path === "/" || path === ctx.identity.home) ctx.out(`rm: it is dangerous to operate recursively on '${arg}'`);
    else if (ctx.vfs.isDir(path) && !/[rR]/.test(flags)) ctx.out(`rm: ${arg}: is a directory`);
    else if (!ctx.vfs.exists(path) && !flags.includes("f")) ctx.out(`rm: ${arg}: ${MESSAGES.ENOENT}`);
    else if (ctx.vfs.exists(path)) ctx.vfs.remove(path, { recursive: true });
  }
}

export const FS_COMMANDS = {
  ls,
  cd,
  cat,
  head,
  mkdir,
  touch,
  rm,
  pwd: (ctx) => ctx.out(ctx.cwd),
};
