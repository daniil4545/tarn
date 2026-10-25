// Tab completion: command names, subcommands, paths. Pure over the vfs.
// complete(line before the cursor) -> {from, items: [{insert, label}]}; `from` is where the word starts.
const SUBCOMMANDS = { tarn: ["open", "ls", "new"], git: ["status", "log", "branch"] };
const DIRS_ONLY = new Set(["cd", "mkdir"]);

export function createCompleter({ vfs, cwd, home, commands }) {
  function paths(prefix, dirsOnly) {
    const slash = prefix.lastIndexOf("/") + 1;
    const typedDir = prefix.slice(0, slash);
    const base = prefix.slice(slash);
    const dir = vfs.resolve(cwd(), typedDir.startsWith("~") ? home + typedDir.slice(1) : typedDir || ".");
    if (!vfs.isDir(dir)) return [];
    return vfs.list(dir)
      .filter((e) => e.name.startsWith(base) && (base.startsWith(".") || !e.name.startsWith(".")) && (!dirsOnly || e.dir))
      .map((e) => ({ insert: typedDir + e.name + (e.dir ? "/" : ""), label: e.name + (e.dir ? "/" : "") }));
  }

  const pick = (names, prefix) => names.filter((n) => n.startsWith(prefix)).map((n) => ({ insert: n, label: n }));

  return function complete(line) {
    const from = line.search(/\S*$/);
    const prefix = line.slice(from);
    const words = line.slice(0, from).trim().split(/\s+/).filter(Boolean);
    if (!words.length) {
      const pathLike = prefix.includes("/") || prefix.startsWith(".");
      return { from, items: pathLike ? paths(prefix, false) : pick(commands, prefix) };
    }
    const sub = Object.hasOwn(SUBCOMMANDS, words[0]) ? SUBCOMMANDS[words[0]] : undefined;
    if (sub && words.length === 1) return { from, items: pick(sub, prefix) };
    return { from, items: paths(prefix, DIRS_ONLY.has(words[0])) };
  };
}
