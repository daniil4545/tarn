// Viewer panes: the app's viewer bundle (demo/viewer/, copied by tools/sync-viewer.sh) in an iframe,
// driven by viewer-model.js. Counterpart of ViewerHost.swift and ViewerWebView.swift.
//
// Commands (single handler here): viewer.open {path?, line?, pane?, tree?, cwd?, background?},
// viewer.cmd {name: save|mode|tree|closeTab, pane?}, viewer.split {dir, pane?}.
// With no visible viewer to take a request, viewer.open emits `viewer:needed` with the same payload:
// the layout creates a viewer pane and sends viewer.open again with `pane`.
import { bus } from "./bus.js";
import { hooks } from "./test-contract.js";
import { createViewerModel } from "./viewer-model.js";
import { resolve } from "./viewer-paths.js";

const panes = new Map(); // id -> { el, frame, model }
let fs = null;
let home = "";
let root = "";
let focused = null;
const isDark = () => document.documentElement.dataset.theme !== "light";

// The viewer named by `id`, else the one last focused, else any on screen (a terminal's `pane` id names no viewer).
function visibleTarget(id) {
  const shown = (key) => panes.has(key) && panes.get(key).el.offsetParent !== null;
  if (panes.has(id)) return panes.get(id);
  if (shown(focused)) return panes.get(focused);
  return [...panes.values()].find((p) => p.el.offsetParent !== null);
}

function open(payload) {
  const entry = visibleTarget(payload.pane);
  if (!entry) return bus.emit("viewer:needed", payload);
  const target = payload.path && resolve(payload.path, { cwd: payload.cwd ?? root, home, exists: fs.exists });
  if (target) entry.model.open({ path: target.path, line: payload.line ?? target.line }, { background: payload.background });
  if (payload.tree && !entry.model.state().treeVisible) entry.model.toggleTree();
}

function command({ name, pane }) {
  const entry = visibleTarget(pane);
  if (!entry) return name === "tree" ? bus.emit("viewer:needed", { tree: true }) : undefined;
  if (name === "save" || name === "mode") entry.frame.contentWindow.tarn.cmd(name);
  else if (name === "tree") entry.model.toggleTree();
  else if (name === "closeTab") entry.model.closeActiveTab();
}

function split({ dir, pane }) {
  const entry = visibleTarget(pane);
  const state = entry?.model.state();
  const path = state?.tabs[state.active]?.path;
  if (path) bus.cmd("pane.split", { id: [...panes].find(([, p]) => p === entry)[0], dir, kind: "viewer", path });
}

// fs: the vfs of vfs.js; root: the folder the tree starts at; home: what `~` means in a path.
export function startViewer({ fs: files, home: homePath, root: projectRoot }) {
  fs = files;
  home = homePath;
  root = projectRoot;
  bus.handle("viewer.open", open);
  bus.handle("viewer.cmd", command);
  bus.handle("viewer.split", split);
  bus.on("vfs:changed", ({ path, by }) => {
    for (const [id, { model }] of panes) if (by !== `viewer:${id}`) model.diskChanged(path);
  });
  new MutationObserver(() => panes.forEach(({ model }) => model.setDark(isDark())))
    .observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  hooks.viewer = () => ({ focused, panes: Object.fromEntries([...panes].map(([id, p]) => [id, p.model.state()])) });
}

// Keys pressed inside the iframe never reach the page: pass them to the dispatcher in the capture phase.
function forwardKeys(frame) {
  frame.contentDocument.addEventListener("keydown", (e) => {
    const copy = new KeyboardEvent("keydown", {
      key: e.key, code: e.code, ctrlKey: e.ctrlKey, altKey: e.altKey, shiftKey: e.shiftKey, metaKey: e.metaKey,
      bubbles: true, cancelable: true,
    });
    document.dispatchEvent(copy);
    if (copy.defaultPrevented) { e.preventDefault(); e.stopPropagation(); }
  }, true);
}

// Same shape as createPane of the terminal: { id, el, focus(), dispose() }.
export function createViewerPane(id) {
  const el = document.createElement("div");
  el.className = "pane viewer-pane";
  el.dataset.pane = id;
  const frame = document.createElement("iframe");
  frame.title = "Viewer";
  el.append(frame);

  const model = createViewerModel({
    fs,
    home,
    root,
    ui: {
      setDoc: (doc) => frame.contentWindow.tarn.setDoc(doc),
      setChrome: (chrome) => frame.contentWindow.tarn.setChrome(chrome),
      toast: (text) => frame.contentWindow.tarn.toast(text),
      write: (path, text) => bus.cmd("vfs.write", { path, text, by: `viewer:${id}` }),
      closePane: () => bus.cmd("pane.close", { id }),
      focus: () => frame.contentWindow.focus(),
      confirm: (text) => window.confirm(text),
      open: (url) => window.open(url, "_blank", "noopener"),
    },
  });
  model.setDark(isDark());
  frame.__host = model.handle;
  frame.addEventListener("load", () => {
    forwardKeys(frame);
    frame.contentWindow.addEventListener("focus", () => { focused = id; bus.emit("pane:focused", { pane: id }); });
  });
  frame.src = new URL("../viewer/tarn-viewer.html", import.meta.url).href;

  panes.set(id, { el, frame, model });
  return {
    id,
    el,
    term: null,
    focus: () => frame.contentWindow.focus(),
    screenText: () => frame.contentDocument.body.innerText,
    dispose() {
      el.remove();
      panes.delete(id);
      bus.emit("pane:disposed", { pane: id });
    },
  };
}
