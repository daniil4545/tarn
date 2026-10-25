// The only writer of `workspaces`: workspaces, tabs, layouts, focus and the undo stack.
// Counterpart of SidebarModel (Sidebar.swift); splits, zoom and undo follow Ghostty (SplitTree,
// ExpiringUndoManager). Views read snapshots and send the commands registered here.
import { bus } from "./bus.js";
import { register, read } from "./state.js";
import { isObject, load, save } from "./storage.js";
import { clock } from "./clock.js";
import { WORKSPACES } from "./seed.js";
import { ask } from "./ask-dialog.js";
import * as tree from "./layout.js";

const CAP = 8; // panes per tab
const cfg = (key) => read("config")[key];
const toast = (text) => bus.emit("toast", { text });

const panes = new Map(); // id -> pane; a pane is created once and lives until its undo window ends
const undoStack = [];
const ids = { p: 0, t: 0, v: 0, w: 0 };
let makePane;
let makeViewer;
let write;

export const paneOf = (id) => panes.get(id);
// Ids of every pane of a tab, shown or hidden (a viewer hidden with Toggle Pane stays alive).
export const leafIdsOf = (tab) => [...tree.leaves(tab.layout).map(tree.leafId), ...(tab.hidden ?? []).map((h) => tree.leafId(h.node))];
export const flatTabs = (s) => s.wss.flatMap((w) => w.tabs);
export const currentTab = (s = read("workspaces")) => s.tabs[s.cur] ?? null;
const wsOf = (s, tabId) => s.wss.find((w) => w.tabs.includes(tabId));
const tabOfLeaf = (s, id) => Object.values(s.tabs).find((t) => tree.pathOf(t.layout, id) !== null);
const nextId = (prefix) => `${prefix}${++ids[prefix]}`;

// Which key rows apply: the kind of the focused leaf.
export function focusArea() {
  const tab = currentTab();
  if (!tab) return "terminal"; // no window: only Cmd+Z (bring it back) and the new-window keys apply
  return tree.isTerm(tree.at(tab.layout, tree.pathOf(tab.layout, tab.focus))) ? "terminal" : "viewer";
}

// Shape of saved workspaces: anything else (hand-edited storage) is dropped before it can throw.
const isNode = (n) => isObject(n) && (typeof n.pane === "string" || typeof n.viewer === "string"
  || (["row", "col"].includes(n.dir) && typeof n.ratio === "number" && isNode(n.a) && isNode(n.b)));
const hasTerminal = (n) => typeof n.pane === "string" || (n.a !== undefined && (hasTerminal(n.a) || hasTerminal(n.b)));
const isTab = (t) => isObject(t) && typeof t.id === "string" && typeof t.title === "string" && typeof t.cwd === "string"
  && isNode(t.layout) && hasTerminal(t.layout);
const isWs = (w) => isObject(w) && typeof w.id === "string" && typeof w.name === "string"
  && Array.isArray(w.tabs) && w.tabs.every((id) => typeof id === "string");
const hasShape = (s) => isObject(s) && isObject(s.tabs) && Object.values(s.tabs).every(isTab)
  && Array.isArray(s.wss) && s.wss.every(isWs) && (s.cur === null || typeof s.cur === "string");

function usable(state) {
  const ok = state?.tabs && Array.isArray(state.wss)
    && (state.cur === null ? state.wss.length === 0 : state.tabs[state.cur] !== undefined)
    && state.wss.every((w) => w.tabs.every((id) => state.tabs[id]));
  if (!ok) toast("Saved workspaces could not be used, starting fresh");
  return ok;
}

function scanIds(state) {
  const bump = (id) => { ids[id[0]] = Math.max(ids[id[0]], Number(id.slice(1)) || 0); };
  state.wss.forEach((w) => bump(w.id));
  Object.values(state.tabs).forEach((t) => {
    bump(t.id);
    tree.leaves(t.layout).forEach((l) => bump(tree.leafId(l)));
  });
}

export function startWorkspaces({ createPane, createViewer }) {
  makePane = createPane;
  makeViewer = createViewer;
  const stored = cfg("window-save-state") === "never" ? WORKSPACES : load("workspaces", WORKSPACES, hasShape);
  const initial = structuredClone(usable(stored) ? stored : WORKSPACES);
  scanIds(initial);
  for (const tab of Object.values(initial.tabs)) {
    // A viewer's files are not stored, so after a reload its leaf would be empty: drop it.
    for (const v of tree.viewers(tab.layout)) tab.layout = tree.remove(tab.layout, v.viewer);
    tab.hidden = [];
    if (!tree.pathOf(tab.layout, tab.focus)) tab.focus = null;
    tab.focus ??= tree.terminals(tab.layout)[0].pane;
    tab.zoom ??= null;
    tree.leaves(tab.layout).forEach((l) => ensurePane(tree.leafId(l), tab.cwd));
  }
  write = register("workspaces", initial);

  bus.on("pane:focused", ({ pane }) => {
    const tab = currentTab();
    if (tab && tab.focus !== pane && tree.pathOf(tab.layout, pane) !== null) bus.cmd("pane.focus", { id: pane });
  });
  // The tab follows the folder of its shell: a new tab or split starts there.
  bus.on("pane:cwd", ({ pane, cwd }) => update((s) => {
    const tab = tabOfLeaf(s, pane);
    if (!tab) return;
    tab.cwd = cwd;
    if (tab.title.startsWith("zsh · ")) tab.title = `zsh · ${short(cwd)}`;
  }));
  // A viewer command found no viewer on screen: open one right of the terminal block and repeat it.
  bus.on("viewer:needed", (request) => {
    const pane = bus.cmd("pane.place", { viewer: true, zone: "right", target: "block", focus: false });
    if (pane) bus.cmd("viewer.open", { ...request, pane });
  });
  Object.entries(COMMANDS).forEach(([name, fn]) => bus.handle(name, (payload = {}) => (NEEDS_TAB.test(name) && !currentTab() ? undefined : fn(payload))));
}

function update(fn) {
  const draft = structuredClone(read("workspaces"));
  const result = fn(draft);
  write(draft);
  if (cfg("window-save-state") !== "never") save("workspaces", draft);
  return result;
}

function ensurePane(id, cwd) {
  if (!panes.has(id)) panes.set(id, id.startsWith("v") ? makeViewer(id) : makePane(id, { cwd }));
  return panes.get(id);
}

const short = (cwd) => cwd.replace("~/code/", "~/c/");
const inheritedCwd = (s) => (cfg("window-inherit-working-directory") && s.tabs[s.cur] ? s.tabs[s.cur].cwd : "~");

function addTab(s, ws, { cwd = inheritedCwd(s), title = `zsh · ${short(cwd)}` } = {}) {
  const id = nextId("t"), pane = nextId("p");
  s.tabs[id] = { id, title, cwd, layout: { pane }, focus: pane, zoom: null };
  ws.tabs.push(id);
  ensurePane(pane, cwd);
  return id;
}

// A new window starts with Default and one tab.
function openWindow(s) {
  const ws = { id: nextId("w"), name: "Default", tabs: [] };
  s.wss = [ws];
  s.cur = addTab(s, ws, { cwd: "~" });
}

// Undo: a closed pane or tab stays alive until the undo window ends, then it is freed.
let exiting = false; // a shell that exited on its own is gone for good: nothing to undo
function keepUndo(rec) {
  const ms = parseInt(cfg("undo-timeout"), 10) * 1000; // "5s"
  if (ms === 0 || exiting) { expire(rec); return false; }
  rec.timer = clock.after(ms, () => expire(rec));
  undoStack.push(rec);
  return true;
}

function expire(rec) {
  const at = undoStack.indexOf(rec);
  if (at >= 0) undoStack.splice(at, 1);
  for (const id of rec.leafIds) {
    panes.get(id)?.dispose();
    panes.delete(id);
  }
}

function allowClose(leafIds) {
  const mode = cfg("confirm-close-surface");
  if (mode === "false") return true;
  const busy = mode === "always" || leafIds.some((id) => panes.get(id)?.busy);
  return !busy || confirm("Close and stop the running program?");
}

// Make a tab current; a folded workspace unfolds to show it.
function select(s, id) {
  s.cur = id;
  const ws = id && wsOf(s, id);
  if (ws) ws.collapsed = false;
}

// Viewers with unsaved text ask first, as the app does: Save, Don't Save or Cancel. Then `go` runs.
function settleViewers(tabs, go) {
  const dirty = tabs.flatMap((t) => leafIdsOf(t).filter((id) => id.startsWith("v"))).map((id) => panes.get(id)).filter((p) => p?.dirtyFiles().length);
  if (!dirty.length) return go();
  const names = dirty.flatMap((p) => p.dirtyFiles()).join(", ");
  return ask(`Save changes to ${names} before closing?`, ["Save", "Don't Save", "Cancel"]).then((choice) => {
    if (choice === "Cancel") return;
    dirty.forEach((p) => (choice === "Save" ? p.saveAll() : p.discardAll()));
    go();
  });
}

function closeTab(s, id) {
  const tab = s.tabs[id], ws = wsOf(s, id), order = flatTabs(s), at = order.indexOf(id);
  const kept = keepUndo({ kind: "tab", what: tab.title, tab, wsId: ws.id, wsAt: s.wss.indexOf(ws), wsName: ws.name, wsFolded: !!ws.collapsed, index: ws.tabs.indexOf(id), leafIds: leafIdsOf(tab) });
  ws.tabs = ws.tabs.filter((x) => x !== id);
  delete s.tabs[id];
  if (!ws.tabs.length) s.wss = s.wss.filter((w) => w !== ws);
  if (s.cur === id) select(s, order[at + 1] ?? order[at - 1] ?? null);
  const undo = kept ? " · ⌘Z restores" : "";
  toast(!s.wss.length ? `Last tab closed: the window closes${undo}`
    : !ws.tabs.length ? `Workspace ${ws.name} closed with its last tab${undo}` : `Tab closed${undo}`);
}

function closeLeaf(s, id) {
  const tab = tabOfLeaf(s, id);
  if (tree.terminals(tab.layout).length === 1 && tree.isTerm(tree.at(tab.layout, tree.pathOf(tab.layout, id)))) return closeTab(s, tab.id);
  const node = tree.at(tab.layout, tree.pathOf(tab.layout, id));
  keepUndo({ kind: "layout", what: id.startsWith("v") ? "viewer" : "pane", tabId: tab.id, node, seat: tree.seatOf(tab.layout, id), leafIds: [id] });
  dropLeaf(tab, id);
}

function dropLeaf(tab, id) {
  tab.layout = tree.remove(tab.layout, id);
  tab.zoom = null;
  // Focus goes back to the terminal block, so cmd+Z (a terminal key) can bring the pane back.
  if (tab.focus === id) tab.focus = tree.terminals(tab.layout)[0].pane;
}

function restore(s, rec) {
  if (rec.kind === "tab") {
    let ws = s.wss.find((w) => w.id === rec.wsId);
    if (!ws) {
      ws = { id: rec.wsId, name: rec.wsName, collapsed: rec.wsFolded, tabs: [] };
      s.wss.splice(Math.min(rec.wsAt, s.wss.length), 0, ws);
    }
    ws.tabs.splice(Math.min(rec.index, ws.tabs.length), 0, rec.tab.id);
    ws.collapsed = false;
    s.tabs[rec.tab.id] = rec.tab;
    s.cur = rec.tab.id;
  } else {
    const tab = s.tabs[rec.tabId];
    tab.layout = tree.reseat(tab.layout, rec.node, rec.seat);
    Object.assign(tab, { focus: tree.leafId(rec.node), zoom: null });
  }
}

const leafCount = (tab) => tree.leaves(tab.layout).length;
const ZONE = { right: "right", down: "bottom" };

const NEEDS_TAB = /^(pane\.(?!undo)|tab\.(close|step)|viewer\.(hide|show))/;

const COMMANDS = {
  "tab.new": ({ ws, pane, cwd, title, select = true }) => update((s) => {
    const target = (pane && wsOf(s, tabOfLeaf(s, pane)?.id)) || s.wss.find((w) => w.id === ws) || wsOf(s, s.cur) || s.wss[0];
    if (!target) return openWindow(s);
    const id = addTab(s, target, { cwd, title });
    if (select) { s.cur = id; target.collapsed = false; }
  }),

  "tab.close": ({ id }) => {
    const s = read("workspaces"), tab = s.tabs[id ?? s.cur];
    if (tab && allowClose(tree.terminals(tab.layout).map((t) => t.pane))) settleViewers([tab], () => update((d) => closeTab(d, tab.id)));
  },

  "tab.go": ({ id, n }) => update((s) => {
    const order = flatTabs(s), target = id ?? (n === 9 ? order.at(-1) : order[n - 1]);
    if (s.tabs[target]) select(s, target);
  }),

  "tab.step": ({ delta }) => update((s) => {
    const order = flatTabs(s);
    select(s, order[(order.indexOf(s.cur) + delta + order.length) % order.length]);
  }),

  // Before another tab or at the end of a workspace.
  "tab.move": ({ id, ws, before = null }) => update((s) => {
    const to = s.wss.find((w) => w.id === ws), from = wsOf(s, id);
    if (!to) return;
    from.tabs = from.tabs.filter((x) => x !== id);
    const at = before ? to.tabs.indexOf(before) : -1;
    if (at >= 0) to.tabs.splice(at, 0, id); else to.tabs.push(id);
    if (from !== to) { to.collapsed = false; toast(`Moved to ${to.name}`); }
    if (!from.tabs.length) s.wss = s.wss.filter((w) => w !== from);
  }),

  // A terminal splits into a terminal; a viewer into another viewer that opens `path`.
  "pane.split": ({ id, dir, kind = "terminal", path }) => {
    const created = update((s) => {
      const tab = currentTab(s), target = id ?? tab.focus;
      if (leafCount(tab) >= CAP) return toast(`At most ${CAP} panes in a tab`);
      const at = tree.pathOf(tab.layout, target), viewer = kind === "viewer";
      const fresh = nextId(viewer ? "v" : "p");
      tab.layout = tree.setAt(tab.layout, at, tree.join(tree.at(tab.layout, at), viewer ? { viewer: fresh } : { pane: fresh }, ZONE[dir]));
      tab.focus = fresh;
      tab.zoom = null;
      ensurePane(fresh, inheritedCwd(s));
      return fresh;
    });
    if (created && path) bus.cmd("viewer.open", { pane: created, path });
  },

  "pane.close": ({ id, exited = false }) => {
    const s = read("workspaces"), tab = currentTab(s), target = id ?? tab.focus;
    if (exited) {
      exiting = true;
      try { update((d) => closeLeaf(d, target)); } finally { exiting = false; }
      return;
    }
    const viewer = target.startsWith("v");
    if (viewer) return update((d) => closeLeaf(d, target));
    if (!allowClose([target])) return;
    // The last terminal takes the tab with it, so unsaved viewer text is asked about first.
    const lastTerminal = tree.terminals(tab.layout).length === 1;
    if (lastTerminal) settleViewers([tab], () => update((d) => closeLeaf(d, target)));
    else update((d) => closeLeaf(d, target));
  },

  // Toggle Pane: a viewer leaves the layout but stays alive with its tabs and unsaved text.
  "viewer.hide": ({ id }) => update((s) => {
    const tab = tabOfLeaf(s, id);
    if (!tab || !id.startsWith("v")) return;
    (tab.hidden ??= []).push({ node: tree.at(tab.layout, tree.pathOf(tab.layout, id)), seat: tree.seatOf(tab.layout, id) });
    dropLeaf(tab, id);
  }),

  "viewer.show": () => update((s) => {
    const tab = currentTab(s);
    for (const { node, seat } of tab.hidden ?? []) tab.layout = tree.reseat(tab.layout, node, seat);
    tab.hidden = [];
  }),

  "pane.focus": ({ id }) => {
    const tab = currentTab();
    if (tab.focus === id) return;
    update((s) => { currentTab(s).focus = id; });
  },

  "pane.step": ({ delta }) => update((s) => {
    const tab = currentTab(s), order = tree.leaves(tab.layout).map(tree.leafId);
    tab.focus = order[(order.indexOf(tab.focus) + delta + order.length) % order.length];
  }),

  "pane.zoom": () => update((s) => { const t = currentTab(s); t.zoom = t.zoom ? null : t.focus; }),
  "pane.resize": ({ dir }) => update((s) => { const t = currentTab(s); t.layout = tree.resize(t.layout, t.focus, dir, 0.05); }),
  "pane.equalize": () => update((s) => { const t = currentTab(s); t.layout = tree.equalize(t.layout); }),
  "pane.ratio": ({ path, ratio }) => update((s) => { const t = currentTab(s); t.layout = tree.setRatio(t.layout, path, ratio); }),

  // Move a leaf, or add a new viewer when `viewer` is true, beside a target (layout.js place).
  // The moved or new pane takes the focus unless `focus` is false (an agent command opens a viewer).
  "pane.place": ({ id, viewer = false, zone, target, focus = true }) => update((s) => {
    const tab = currentTab(s), vid = viewer ? nextId("v") : null;
    if (viewer && leafCount(tab) >= CAP) return toast(`At most ${CAP} panes in a tab`);
    const node = viewer ? { viewer: vid } : tree.at(tab.layout, tree.pathOf(tab.layout, id));
    tab.layout = tree.place(tab.layout, node, zone, target);
    tab.zoom = null;
    if (focus) tab.focus = vid ?? id;
    if (vid) ensurePane(vid);
    return vid;
  }),

  "pane.undo": () => {
    const rec = undoStack.pop();
    if (!rec) return toast("Nothing to undo");
    clock.cancel(rec.timer);
    const alive = rec.kind === "tab" || read("workspaces").tabs[rec.tabId];
    if (!alive) return expire(rec);
    update((s) => restore(s, rec));
    toast(`Restored: ${rec.what}`);
  },

  "ws.new": ({ name }) => update((s) => {
    const ws = { id: nextId("w"), name, tabs: [] };
    s.wss.push(ws);
    s.cur = addTab(s, ws, { cwd: "~" });
  }),

  "ws.rename": ({ id, name }) => update((s) => { s.wss.find((w) => w.id === id).name = name; }),
  "ws.fold": ({ id }) => update((s) => { const w = s.wss.find((x) => x.id === id); w.collapsed = !w.collapsed; }),

  // Its tabs go to the workspace above, or below if it is the first (D13). The last one cannot go.
  "ws.delete": ({ id }) => update((s) => {
    const at = s.wss.findIndex((w) => w.id === id);
    if (s.wss.length < 2) return;
    const into = s.wss[at > 0 ? at - 1 : 1];
    if (at > 0) into.tabs.push(...s.wss[at].tabs); else into.tabs.unshift(...s.wss[at].tabs);
    into.collapsed = false;
    s.wss.splice(at, 1);
  }),

  // Before another workspace, or at the end.
  "ws.move": ({ id, before = null }) => update((s) => {
    const ws = s.wss.find((w) => w.id === id);
    s.wss = s.wss.filter((w) => w !== ws);
    const at = before ? s.wss.findIndex((w) => w.id === before) : -1;
    s.wss.splice(at >= 0 ? at : s.wss.length, 0, ws);
  }),

  "window.new": () => {
    if (read("workspaces").wss.length) return toast("⌘N opens another window with its own Default");
    update(openWindow);
  },

  "window.close": () => {
    const tabs = Object.values(read("workspaces").tabs);
    if (!tabs.every((t) => allowClose(tree.terminals(t.layout).map((x) => x.pane)))) return;
    settleViewers(tabs, () => {
      for (const tab of tabs) expire({ leafIds: leafIdsOf(tab) });
      update((s) => { s.tabs = {}; s.wss = []; s.cur = null; });
      toast("Window closed · ⌘N opens a new one");
    });
  },
};
