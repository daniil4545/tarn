// In-memory disk shared by the shell, the agent script and the viewer. Counterpart of the real
// disk and FileWatcher.swift. Single writer of the `vfs` part; every change emits `vfs:changed`.
import { bus } from "./bus.js";
import { register } from "./state.js";
import { isObject, load, save } from "./storage.js";
import { clock } from "./clock.js";
import { HOME, REPO, SITE, REPO_FILES, SITE_FILES, DIRTY, EXTRA_DIRS } from "./vfs-seed.js";

const SEED_TIME = Date.UTC(2026, 9, 25, 12, 34);

export class VfsError extends Error {
  constructor(code, path) {
    super(`${code}: ${path}`);
    this.code = code;
  }
}

const parent = (path) => path.slice(0, path.lastIndexOf("/")) || "/";
const name = (path) => path.slice(path.lastIndexOf("/") + 1);

// Disk as plain data: files {path: {text, mtime}}, dirs [path], committed {path: text} for git.
export function seedDisk() {
  const files = {};
  const committed = {};
  const dirs = new Set(["/", "/Users", HOME, ...EXTRA_DIRS]);
  const add = (root, set, tracked) => {
    for (const [rel, text] of Object.entries(set)) {
      const path = `${root}/${rel}`;
      files[path] = { text, mtime: SEED_TIME };
      if (tracked && !rel.startsWith(".git/")) committed[path] = DIRTY.includes(rel) ? "" : text;
      for (let dir = parent(path); dir !== "/" && !dirs.has(dir); dir = parent(dir)) dirs.add(dir);
    }
    for (let dir = root; dir !== "/" && !dirs.has(dir); dir = parent(dir)) dirs.add(dir);
  };
  add(REPO, REPO_FILES, true);
  add(SITE, SITE_FILES, true);
  return { files, dirs: [...dirs], committed };
}

export function createVfs(disk, { now = Date.now } = {}) {
  const files = new Map(Object.entries(disk.files));
  const dirs = new Set(disk.dirs);
  const committed = new Map(Object.entries(disk.committed));
  const listeners = new Set();
  const changed = (path, by) => listeners.forEach((fn) => fn(path, by));

  const isDir = (path) => dirs.has(path);
  const isFile = (path) => files.has(path);
  const exists = (path) => isDir(path) || isFile(path);

  function resolve(cwd, input) {
    const out = [];
    for (const part of (input.startsWith("/") ? input : `${cwd}/${input}`).split("/")) {
      if (part === "..") out.pop();
      else if (part && part !== ".") out.push(part);
    }
    return `/${out.join("/")}`;
  }

  function checkParent(path) {
    if (!isDir(parent(path))) throw new VfsError("ENOENT", path);
  }

  function repoRoot(path) {
    for (let dir = path; ; dir = parent(dir)) {
      if (isDir(`${dir}/.git`)) return dir;
      if (dir === "/") return null;
    }
  }

  return {
    resolve,
    isDir,
    isFile,
    exists,
    snapshot: () => ({
      files: Object.fromEntries(files),
      dirs: [...dirs],
      committed: Object.fromEntries(committed),
    }),
    onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },

    read(path) {
      if (isDir(path)) throw new VfsError("EISDIR", path);
      if (!isFile(path)) throw new VfsError("ENOENT", path);
      return files.get(path).text;
    },

    mtime: (path) => files.get(path)?.mtime ?? SEED_TIME,

    // Children of a directory, sorted: [{name, dir}].
    list(path) {
      if (!isDir(path)) throw new VfsError(isFile(path) ? "ENOTDIR" : "ENOENT", path);
      const prefix = path === "/" ? "/" : `${path}/`;
      const entries = [];
      for (const p of [...dirs, ...files.keys()]) {
        if (p !== path && p.startsWith(prefix) && !p.slice(prefix.length).includes("/")) entries.push({ name: name(p), dir: isDir(p) });
      }
      return entries.sort((a, b) => a.name.localeCompare(b.name));
    },

    write(path, text, by = "shell") {
      if (isDir(path)) throw new VfsError("EISDIR", path);
      checkParent(path);
      files.set(path, { text, mtime: now() });
      changed(path, by);
    },

    mkdir(path, { parents = false } = {}) {
      if (exists(path)) {
        if (parents && isDir(path)) return;
        throw new VfsError("EEXIST", path);
      }
      if (!parents) checkParent(path);
      for (let dir = path; !isDir(dir); dir = parent(dir)) dirs.add(dir);
      changed(path, "shell");
    },

    remove(path, { recursive = false } = {}) {
      if (isFile(path)) files.delete(path);
      else if (isDir(path)) {
        if (!recursive) throw new VfsError("EISDIR", path);
        const prefix = `${path}/`;
        for (const p of [...files.keys()]) if (p.startsWith(prefix)) files.delete(p);
        for (const d of [...dirs]) if (d === path || d.startsWith(prefix)) dirs.delete(d);
      } else throw new VfsError("ENOENT", path);
      changed(path, "shell");
    },

    gitRoot: repoRoot,
    gitBranch(path) {
      const root = repoRoot(path);
      const head = root && files.get(`${root}/.git/HEAD`)?.text;
      return head ? head.trim().replace("ref: refs/heads/", "") : null;
    },

    // Short-format status entries of the repo that holds `path`: [{code, path}] relative to the root.
    gitStatus(path) {
      const root = repoRoot(path);
      if (!root) return null;
      const rel = (p) => p.slice(root.length + 1);
      const inside = (p) => p.startsWith(`${root}/`) && !rel(p).startsWith(".git/");
      const entries = [];
      for (const [p, { text }] of files) {
        if (!inside(p)) continue;
        if (!committed.has(p)) entries.push({ code: "??", path: rel(p) });
        else if (committed.get(p) !== text) entries.push({ code: " M", path: rel(p) });
      }
      for (const p of committed.keys()) if (inside(p) && !files.has(p)) entries.push({ code: " D", path: rel(p) });
      return entries.sort((a, b) => a.path.localeCompare(b.path));
    },
  };

}

// Boots the disk from storage and wires the `vfs.write` command; returns the vfs.
export function startVfs() {
  const isDisk = (v) => isObject(v) && isObject(v.files) && Array.isArray(v.dirs) && isObject(v.committed);
  const vfs = createVfs(load("vfs", seedDisk(), isDisk), { now: clock.now });
  const write = register("vfs", vfs.snapshot());
  vfs.onChange((path, by) => {
    const disk = vfs.snapshot();
    write(disk);
    save("vfs", disk);
    bus.emit("vfs:changed", { path, by });
  });
  bus.handle("vfs.write", ({ path, text, by }) => vfs.write(path, text, by));
  return vfs;
}
