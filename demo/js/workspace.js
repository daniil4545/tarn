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
import { isOn } from "./modules.js";

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
// `stashed` holds the viewers of a tab while File viewer is off; `hidden` is the user's Cmd+B hide.
export const leafIdsOf = (tab) => [...tree.leaves(tab.layout).map(tree.leafId), ...(tab.hidden ?? []).map((h) => tree.leafId(h.node)), ...(tab.stashed ?? []).map((h) => tree.leafId(h.node))];
// The tab order down the list. Workspaces off: `s.order` (set by a drag) wins over the frozen groups; membership never changes.
export const flatTabs = (s) => {
  const grouped = s.wss.flatMap((w) => w.tabs);
  if (isOn("workspaces") || !s.order) return grouped;
  return [...s.order.filter((id) => grouped.includes(id)), ...grouped.filter((id) => !s.order.includes(id))];
};
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

// A store from before groups has a workspace "~" without a folder: its tabs become ungrouped
// tabs where they stand.
function migrateHome(state) {
  if (state.wss.some((w) => w.loose)) return;
  state.wss = state.wss.map((w) => (w.name === "~" && !w.folder ? { id: w.id, name: "", loose: true, tabs: w.tabs } : w));
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
  migrateHome(initial);
  for (const tab of Object.values(initial.tabs)) {
    // A viewer's files are not stored, so after a reload its leaf would be empty: drop it.
    for (const v of tree.viewers(tab.layout)) tab.layout = tree.remove(tab.layout, v.viewer);
    tab.hidden = [];
    tab.stashed = [];
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
  // File viewer off: the panes leave the layout but stay alive with their tabs and unsaved text;
  // on again they return to their seats. Cmd+B's own hide (`hidden`) is a separate list.
  bus.on("config:changed", ({ key }) => {
    if (key === "file-viewer") update(syncViewers);
    if (key === "module-workspaces" && isOn("workspaces")) update((s) => { delete s.order; }); // regroup into the frozen groups
  });
  if (!isOn("viewer")) update(syncViewers);
  Object.entries(COMMANDS).forEach(([name, fn]) => bus.handle(name, (payload = {}) => (NEEDS_TAB.test(name) && !currentTab() ? undefined : fn(payload))));
}

function syncViewers(s) {
  const on = isOn("viewer");
  for (const tab of Object.values(s.tabs)) {
    if (!on) {
      for (const v of tree.viewers(tab.layout)) {
        (tab.stashed ??= []).push({ node: tree.at(tab.layout, tree.pathOf(tab.layout, v.viewer)), seat: tree.seatOf(tab.layout, v.viewer) });
        dropLeaf(tab, v.viewer);
      }
    } else {
      for (const { node, seat } of tab.stashed ?? []) tab.layout = tree.reseat(tab.layout, node, seat);
      tab.stashed = [];
    }
  }
}

function update(fn) {
  const draft = structuredClone(read("workspaces"));
  const result = fn(draft);
  mergeLoose(draft);
  write(draft);
  if (cfg("window-save-state") !== "never") save("workspaces", draft);
  return result;
}

function ensurePane(id, cwd) {
  if (!panes.has(id)) panes.set(id, id.startsWith("v") ? makeViewer(id) : makePane(id, { cwd }));
  return panes.get(id);
}

const short = (cwd) => cwd.replace("~/code/", "~/c/");
// Workspaces off (or Sidebar off): the registry stops grouping. New tabs are ungrouped; the frozen
// groups stay untouched.
const flat = () => !isOn("workspaces");
// Ungrouped tabs sit in headerless blocks anywhere between the groups (docs/specs/workspace-folder.md
// G5). The block at list index `at` (the tail by default), or the one just above it, else a new one there.
const looseAt = (s, at = s.wss.length) => {
  if (s.wss[at]?.loose) return s.wss[at];
  if (s.wss[at - 1]?.loose) return s.wss[at - 1];
  const ws = { id: nextId("w"), name: "", loose: true, tabs: [] };
  s.wss.splice(at, 0, ws);
  return ws;
};
// Two ungrouped blocks that meet are one; an empty one goes.
function mergeLoose(s) {
  s.wss = s.wss.reduce((out, w) => {
    if (w.loose && !w.tabs.length) return out;
    if (w.loose && out.at(-1)?.loose) out.at(-1).tabs.push(...w.tabs);
    else out.push(w);
    return out;
  }, []);
}
const inheritedCwd = (s) => (cfg("window-inherit-working-directory") && s.tabs[s.cur] ? s.tabs[s.cur].cwd : "~");

function addTab(s, ws, { cwd = inheritedCwd(s), title = `zsh · ${short(cwd)}` } = {}) {
  const id = nextId("t"), pane = nextId("p");
  s.tabs[id] = { id, title, cwd, layout: { pane }, focus: pane, zoom: null };
  ws.tabs.push(id);
  ensurePane(pane, cwd);
  return id;
}

// A new window starts with one ungrouped tab in the home folder.
function openWindow(s) {
  s.wss = [];
  s.cur = addTab(s, looseAt(s), { cwd: "~" });
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
  const kept = keepUndo({ kind: "tab", what: tab.title, tab, ws: { ...ws, tabs: [] }, wsAt: s.wss.indexOf(ws), index: ws.tabs.indexOf(id), leafIds: leafIdsOf(tab) });
  ws.tabs = ws.tabs.filter((x) => x !== id);
  delete s.tabs[id];
  if (!ws.tabs.length) s.wss = s.wss.filter((w) => w !== ws);
  if (s.cur === id) select(s, order[at + 1] ?? order[at - 1] ?? null);
  const undo = kept ? " · ⌘Z restores" : "";
  toast(!s.wss.length ? `Last tab closed: the window closes${undo}`
    : !ws.tabs.length && !ws.loose ? `Group ${ws.name} closed with its last tab${undo}` : `Tab closed${undo}`);
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
    let ws = s.wss.find((w) => w.id === rec.ws.id);
    if (!ws) {
      const at = Math.min(rec.wsAt, s.wss.length);
      ws = rec.ws.loose ? looseAt(s, at) : structuredClone(rec.ws);
      if (!rec.ws.loose) s.wss.splice(at, 0, ws);
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
  // Cmd+T takes the group of the tab it opens from, right after it, in its folder (Ghostty). A
  // group's "+" (`header`) adds at the end of the group, in the workspace folder or, for a plain
  // group, in the current tab's folder.
  "tab.new": ({ ws, pane, cwd, title, header = false, select = true }) => update((s) => {
    if (!s.wss.length) return openWindow(s);
    const target = flat() ? looseAt(s) : (pane && wsOf(s, tabOfLeaf(s, pane)?.id)) || s.wss.find((w) => w.id === ws) || wsOf(s, s.cur) || looseAt(s);
    const id = addTab(s, target, { cwd: cwd ?? ((header && target.folder) || undefined), title });
    const at = target.tabs.indexOf(s.cur);
    if (!header && !ws && at >= 0) target.tabs.splice(at + 1, 0, target.tabs.pop()); // Cmd+T: next to the current tab
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

  // Before another tab or at the end of a group or ungrouped block. `ws: "loose"` ungroups: with
  // `after` (Remove from group) the tab stands right below that group, else at the tail.
  "tab.move": ({ id, ws, before = null, after = null }) => update((s) => {
    if (flat()) { // a drag only changes the order of the flat list; the frozen groups stay
      const rest = flatTabs(s).filter((x) => x !== id), at = before ? rest.indexOf(before) : -1;
      rest.splice(at >= 0 ? at : rest.length, 0, id);
      s.order = rest;
      return;
    }
    const below = after ? s.wss.findIndex((w) => w.id === after) + 1 : 0;
    const to = ws === "loose" ? looseAt(s, below || s.wss.length) : s.wss.find((w) => w.id === ws), from = wsOf(s, id);
    if (!to) return;
    from.tabs = from.tabs.filter((x) => x !== id);
    const at = before ? to.tabs.indexOf(before) : below ? 0 : -1;
    if (at >= 0) to.tabs.splice(at, 0, id); else to.tabs.push(id);
    if (from !== to) {
      to.collapsed = false;
      toast(to.loose ? "Moved out of the group" : `Moved to ${to.name}`);
    }
    if (!from.tabs.length) s.wss = s.wss.filter((w) => w !== from);
  }),

  // A terminal splits into a terminal; a viewer into another viewer that opens `path`.
  // `focus: false` (`tarn new`) leaves the focus where it was. Returns the new id.
  "pane.split": ({ id, dir, kind = "terminal", path, focus = true }) => {
    const created = update((s) => {
      const tab = (id && tabOfLeaf(s, id)) || currentTab(s), target = id ?? tab.focus;
      if (leafCount(tab) >= CAP) return toast(`At most ${CAP} panes in a tab`);
      const at = tree.pathOf(tab.layout, target), viewer = kind === "viewer";
      const fresh = nextId(viewer ? "v" : "p");
      tab.layout = tree.setAt(tab.layout, at, tree.join(tree.at(tab.layout, at), viewer ? { viewer: fresh } : { pane: fresh }, ZONE[dir]));
      if (focus) tab.focus = fresh;
      tab.zoom = null;
      ensurePane(fresh, cfg("window-inherit-working-directory") ? tab.cwd : "~");
      return fresh;
    });
    if (created && path) bus.cmd("viewer.open", { pane: created, path });
    return created;
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

  // A group with one new tab, at the bottom of the list. With a folder it is a workspace: the tab
  // starts in the folder; a plain group's tab starts where Cmd+T would.
  "ws.new": ({ name, folder }) => update((s) => {
    if (flat()) return;
    const ws = { id: nextId("w"), name, tabs: [], ...(folder ? { folder } : {}) };
    s.wss.push(ws);
    s.cur = addTab(s, ws, { cwd: folder ?? inheritedCwd(s) });
  }),

  "ws.rename": ({ id, name }) => update((s) => {
    const w = s.wss.find((x) => x.id === id);
    if (!flat() && !w.loose) w.name = name;
  }),
  "ws.fold": ({ id }) => update((s) => {
    const w = s.wss.find((x) => x.id === id);
    if (!flat() && !w.loose) w.collapsed = !w.collapsed;
  }),

  // Ungroup, as Warp does: the tabs stay where they are, ungrouped. With `closeTabs` the tabs
  // close too, each with its own undo.
  "ws.delete": ({ id, closeTabs = false }) => {
    const ws = read("workspaces").wss.find((w) => w.id === id);
    if (flat() || !ws || ws.loose) return;
    if (!closeTabs) {
      update((s) => {
        const at = s.wss.findIndex((w) => w.id === id);
        s.wss[at] = { id, name: "", loose: true, tabs: s.wss[at].tabs };
      });
      return;
    }
    const tabs = ws.tabs.map((t) => read("workspaces").tabs[t]);
    if (tabs.every((t) => allowClose(tree.terminals(t.layout).map((x) => x.pane)))) settleViewers(tabs, () => update((s) => tabs.forEach((t) => closeTab(s, t.id))));
  },

  // Before another group or ungrouped block, or at the bottom.
  "ws.move": ({ id, before = null }) => update((s) => {
    if (flat()) return;
    const ws = s.wss.find((w) => w.id === id);
    if (ws.loose) return;
    s.wss = s.wss.filter((w) => w !== ws);
    const at = before ? s.wss.findIndex((w) => w.id === before) : -1;
    s.wss.splice(at >= 0 ? at : s.wss.length, 0, ws);
  }),

  "window.new": () => {
    if (read("workspaces").wss.length) return toast("⌘N opens another window");
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
