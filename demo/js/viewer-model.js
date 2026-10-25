// What one viewer pane shows: tabs, documents and the files tree. The page (the app's viewer
// bundle in an iframe) draws it and reports user actions to `handle`. Port of ViewerModel.swift,
// ViewerTabs.swift, ViewerDocument.swift and FileTree.swift in macos/Sources/Features/Tarn/.
import { basename, dirname, isMarkdown, language, resolve, setTask } from "./viewer-paths.js";

const HIDDEN = new Set([".git", ".DS_Store", "node_modules"]);
const MAX_ROWS = 5000;

// fs is the vfs of vfs.js: isFile, isDir, exists, read(path) -> text, list(dir) -> [{name, dir}]
// ui: { setDoc(obj), setChrome(obj), toast(text), write(path, text), closePane(), focus(), confirm(text), open(url) }
export function createViewerModel({ fs, home, root, ui }) {
  let tabs = [];
  let active = -1;
  let jumps = 0;
  let treeVisible = false;
  let ready = false;
  let dark = true;
  const treeOpen = new Set();
  const docs = new Map();

  const dirty = (path) => docs.get(path)?.text !== docs.get(path)?.savedText;

  function newDoc(path) {
    if (!fs.isFile(path)) return null;
    const text = fs.read(path);
    return { path, text, savedText: text, diskText: null, rev: 1, conflict: false, missing: false };
  }

  // ---- tabs: spec 2.5, a file opens as a preview tab, the next open replaces it ----
  function jumpTo(line, index) {
    tabs[index].line = line;
    tabs[index].jump = ++jumps;
  }

  function openTab(path, { line = null, pin = false, background = false } = {}) {
    if (background && tabs.length) {
      if (tabs.some((t) => t.path === path)) return;
      tabs.push({ path, preview: false, line: null, jump: 0 });
      if (line) jumpTo(line, tabs.length - 1);
      return;
    }
    const found = tabs.findIndex((t) => t.path === path);
    if (found >= 0) {
      active = found;
      if (pin) tabs[found].preview = false;
      if (line) jumpTo(line, found);
      return;
    }
    const tab = { path, preview: !pin, line: null, jump: 0 };
    const preview = pin ? -1 : tabs.findIndex((t) => t.preview);
    let index = active + 1;
    if (preview >= 0) { tabs[preview] = tab; index = preview; } else tabs.splice(index, 0, tab);
    active = index;
    if (line) jumpTo(line, index);
  }

  const pinPath = (path) => { const tab = tabs.find((t) => t.path === path); if (tab) tab.preview = false; };

  // ---- tree ----
  function reveal(path) {
    for (let dir = dirname(path); dir.startsWith(root) && dir !== root; dir = dirname(dir)) treeOpen.add(dir);
  }

  function treeRows() {
    const rows = [];
    const walk = (dir, depth) => {
      const entries = fs.list(dir).filter((e) => !HIDDEN.has(e.name))
        .sort((a, b) => (a.dir !== b.dir ? (a.dir ? -1 : 1) : a.name.localeCompare(b.name, undefined, { numeric: true })));
      for (const e of entries) {
        if (rows.length >= MAX_ROWS) return;
        const path = `${dir}/${e.name}`;
        const open = e.dir && treeOpen.has(path);
        rows.push({ path, name: e.name, depth, kind: e.dir ? "dir" : "file", open, mod: !e.dir && docs.has(path) && dirty(path) });
        if (open) walk(path, depth + 1);
      }
    };
    walk(root, 0);
    return rows;
  }

  // ---- pushing state to the page ----
  const send = (fn) => { if (ready) fn(); };

  function pushDocument(path, reason) {
    const doc = docs.get(path);
    if (!doc) return;
    const tab = tabs.find((t) => t.path === path);
    const object = { path, rev: doc.rev, reason, dir: dirname(path), lang: language(path), kind: isMarkdown(path) ? "md" : "code", text: doc.text };
    if (tab?.line) { object.line = tab.line; object.jump = tab.jump; }
    send(() => ui.setDoc(object));
  }

  function pushChrome() {
    send(() => ui.setChrome({
      tabs: tabs.map((t) => ({ path: t.path, name: basename(t.path), preview: t.preview, dirty: dirty(t.path) })),
      active,
      tree: { visible: treeVisible, root: basename(root), rows: treeVisible ? treeRows() : [] },
      dark,
      conflicts: [...docs.values()].filter((d) => d.conflict).map((d) => d.path),
    }));
  }

  const toast = (text) => send(() => ui.toast(text));

  // ---- actions ----
  function open(target, options) {
    if (!docs.has(target.path)) {
      const doc = newDoc(target.path);
      if (!doc) { toast(`Cannot open ${basename(target.path)}`); return false; }
      docs.set(target.path, doc);
    }
    openTab(target.path, { line: target.line, ...options });
    const kept = new Set(tabs.map((t) => t.path));
    for (const path of docs.keys()) if (!kept.has(path)) docs.delete(path);
    reveal(target.path);
    pushDocument(target.path, "open");
    pushChrome();
    return true;
  }

  function toggleTree() {
    treeVisible = !treeVisible;
    pushChrome();
  }

  function confirmDiscard(path) {
    return !dirty(path) || ui.confirm(`Discard unsaved changes to ${basename(path)}?`);
  }

  function closeTab(index) {
    if (!tabs[index] || !confirmDiscard(tabs[index].path)) return false;
    const [{ path }] = tabs.splice(index, 1);
    if (index < active) active -= 1;
    else if (index === active) active = Math.min(index, tabs.length - 1);
    docs.delete(path);
    if (tabs.length) pushChrome(); else ui.closePane();
    return true;
  }

  const mayClose = () => tabs.every((t) => confirmDiscard(t.path));

  function save(path) {
    const doc = docs.get(path);
    if (!doc || !isMarkdown(path)) return;
    if (!dirty(path) && !doc.conflict && !doc.missing) return toast("No changes");
    // The disk may have changed before the event arrived: never write over the agent's version.
    if (doc.conflict || (fs.isFile(path) && fs.read(path) !== doc.savedText)) {
      diskChanged(path);
      return toast("The file changed on disk: take the agent version or keep yours first");
    }
    ui.write(path, doc.text);
    doc.savedText = doc.text;
    doc.missing = false;
    pushChrome();
    toast("Saved");
  }

  function edit(path, text) {
    const doc = docs.get(path);
    if (!doc || doc.text === text || !isMarkdown(path)) return;
    doc.text = text;
    pinPath(path);
    pushChrome();
  }

  function tickTask(path, line, checked, current) {
    const doc = docs.get(path);
    if (!doc) return;
    if (!current || dirty(path) || doc.conflict) {
      pushDocument(path, "revert");
      return toast("Save or discard your edits before ticking a box");
    }
    const text = setTask(doc.text, line, checked);
    if (text === null) {
      pushDocument(path, "revert");
      return toast("This checkbox no longer matches the file");
    }
    doc.text = text;
    doc.rev += 1;
    save(path);
    pushDocument(path, "task");
  }

  function follow(href, from) {
    if (/^https?:\/\//i.test(href) || href.startsWith("mailto:")) return ui.open(href);
    const bare = decodeURIComponent(href.split("#")[0]);
    const target = resolve(bare, { cwd: from ? dirname(from) : root, home, exists: fs.exists });
    if (!target || !fs.exists(target.path) || fs.isDir(target.path)) return toast(`No such file: ${bare}`);
    open(target);
  }

  // The file changed on disk: reload it, or hold the disk text back while the user decides.
  function diskChanged(path) {
    const doc = docs.get(path);
    if (!doc) return;
    if (!fs.isFile(path)) {
      if (doc.missing) return;
      doc.missing = true;
      return toast(`${basename(path)} was deleted on disk. Save writes it again.`);
    }
    doc.missing = false;
    const disk = fs.read(path);
    if (disk === doc.savedText) return;
    if (!dirty(path)) {
      Object.assign(doc, { text: disk, savedText: disk, rev: doc.rev + 1 });
      pushDocument(path, "external");
      return pushChrome();
    }
    if (doc.conflict && doc.diskText === disk) return;
    doc.diskText = disk;
    doc.conflict = true;
    pushChrome();
  }

  function resolveConflict(path, takeDisk) {
    const doc = docs.get(path);
    if (!doc?.conflict) return;
    if (takeDisk) Object.assign(doc, { text: doc.diskText, savedText: doc.diskText, rev: doc.rev + 1 });
    else doc.savedText = doc.diskText;
    Object.assign(doc, { diskText: null, conflict: false });
    pushDocument(path, "open");
    pushChrome();
  }

  // A message made against an older text than the model holds is dropped: the page has the newer one.
  const isCurrent = (path, body) => docs.get(path)?.rev === body.rev;

  // Messages from the page: the table of ViewerModel.handle.
  function handle(body) {
    const { t: kind, path, index = -1 } = body;
    const pin = body.pin === true;
    switch (kind) {
      case "ready": ready = true; for (const p of docs.keys()) pushDocument(p, "open"); pushChrome(); break;
      case "error": console.warn("tarn-demo: viewer page error", body.message, body.at); break;
      case "tab": if (tabs[index]) { active = index; if (pin) tabs[index].preview = false; } pushChrome(); break;
      case "closeTab": closeTab(index); break;
      case "closePane": if (mayClose()) ui.closePane(); break;
      case "toggleTree": toggleTree(); break;
      case "hideTree": treeVisible = false; pushChrome(); ui.focus(); break;
      case "treeToggle": if (treeOpen.delete(path) === false) treeOpen.add(path); pushChrome(); break;
      case "treeOpen": open({ path, line: null }, { pin }); break;
      case "edit": if (isCurrent(path, body)) edit(path, body.text); break;
      case "save": save(path); break;
      case "task": tickTask(path, body.line, body.checked === true, isCurrent(path, body)); break;
      case "take": resolveConflict(path, true); break;
      case "keep": resolveConflict(path, false); break;
      case "link": follow(body.href, body.from); break;
      case "copy": navigator.clipboard?.writeText(body.text).catch((e) => console.warn("tarn-demo: copy", e)); break;
      default: console.warn("tarn-demo: unknown viewer page message", kind);
    }
  }

  return {
    handle,
    open,
    toggleTree,
    closeActiveTab: () => closeTab(active),
    closeAt: closeTab,
    mayClose,
    diskChanged,
    setDark(value) { if (dark !== value) { dark = value; pushChrome(); } },
    state: () => ({
      tabs: tabs.map((t) => ({ path: t.path, preview: t.preview, dirty: dirty(t.path), line: t.line })),
      active,
      treeVisible,
      conflicts: [...docs.values()].filter((d) => d.conflict).map((d) => d.path),
      dark,
    }),
  };
}
