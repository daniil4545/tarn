// Draws the layout trees into the tab area. Every tab has its own container (hidden when not
// current); a pane element is moved into the new structure, never rebuilt. Dividers, the grab
// handle band and focus by direction live here too.
import { bus } from "./bus.js";
import { read } from "./state.js";
import * as tree from "./layout.js";
import { paneOf, currentTab } from "./workspace.js";

const DOTS = '<svg width="22" height="6" viewBox="0 0 22 6" fill="currentColor" aria-hidden="true"><circle cx="3" cy="3" r="2.2"/><circle cx="11" cy="3" r="2.2"/><circle cx="19" cy="3" r="2.2"/></svg>';
const div = (cls) => Object.assign(document.createElement("div"), { className: cls });

const views = new Map(); // tab id -> {el, key}
let host;
let focusKey;

export function startView() {
  host = document.getElementById("ws");
  host.insertAdjacentHTML("beforeend", '<div class="empty" id="wsEmpty" hidden>The window closed with its last tab<br><button class="act" id="emptyNew">New window (⌘N)</button></div>');
  render();
  bus.on("state:changed", ({ part }) => { if (part === "workspaces") render(); });
  bus.handle("pane.go", ({ dir }) => goTo(dir));
  host.addEventListener("pointerdown", onPointerDown, true);
  host.addEventListener("click", (e) => { if (e.target.closest("#emptyNew")) bus.cmd("window.new"); });
  document.addEventListener("pointermove", markNear);
}

function render() {
  const s = read("workspaces");
  for (const [id, view] of views) if (!s.tabs[id]) { view.el.remove(); views.delete(id); }
  for (const tab of Object.values(s.tabs)) {
    if (!views.has(tab.id)) {
      const el = div("tabview");
      host.append(el);
      views.set(tab.id, { el, key: null });
    }
    const view = views.get(tab.id), key = JSON.stringify([tree.shape(tab.layout), tab.zoom]);
    if (view.key !== key) { view.el.replaceChildren(build(tab)); view.key = key; } else setRatios(view.el, tab);
    view.el.hidden = tab.id !== s.cur;
  }
  host.querySelector("#wsEmpty").hidden = Boolean(s.cur);
  applyFocus(currentTab(s));
}

function build(tab) {
  const walk = (n, path) => {
    if (!tree.isSplit(n)) return leaf(n);
    const el = div(`split ${n.dir}`), a = div("cell"), b = div("cell");
    el.dataset.path = path;
    a.append(walk(n.a, `${path}a`));
    b.append(walk(n.b, `${path}b`));
    const bar = div(`sdiv ${n.dir}`);
    bar.setAttribute("role", "separator");
    el.append(a, bar, b);
    return el;
  };
  const zoomed = tab.zoom && tree.at(tab.layout, tree.pathOf(tab.layout, tab.zoom));
  const root = walk(zoomed ?? tab.layout, "");
  setRatios(root, tab);
  return root;
}

function leaf(n) {
  const id = tree.leafId(n), term = tree.isTerm(n);
  const el = document.createElement("section");
  el.className = "leaf";
  el.dataset.leaf = id;
  el.dataset.kind = term ? "term" : "viewer";
  const grip = div("grip");
  grip.draggable = true;
  grip.dataset.grip = id;
  grip.title = term ? "Drag to move the terminal" : "Drag the viewer with its files";
  grip.innerHTML = DOTS;
  const body = div("leaf-body");
  body.append(paneOf(id).el);
  el.append(grip, body);
  return el;
}

function setRatios(root, tab) {
  const splits = root.matches?.(".split") ? [root] : [];
  for (const el of [...splits, ...root.querySelectorAll(".split")]) {
    const { ratio } = tree.at(tab.layout, el.dataset.path);
    el.children[0].style.flexGrow = ratio;
    el.children[2].style.flexGrow = 1 - ratio;
  }
}

function applyFocus(tab) {
  for (const [id, view] of views) {
    view.el.querySelectorAll(".leaf").forEach((l) => l.classList.toggle("focus", l.dataset.leaf === read("workspaces").tabs[id].focus));
  }
  const key = tab ? `${tab.id}:${tab.focus}` : null;
  const first = focusKey === undefined;
  const changed = key !== focusKey;
  focusKey = key;
  // The first draw keeps the focus off, so the seed session stays "done, not seen".
  if (!tab || first || !changed) return;
  paneOf(tab.focus)?.focus();
}

function onPointerDown(e) {
  const bar = e.target.closest(".sdiv");
  if (bar) return dragDivider(e, bar);
  const el = e.target.closest(".leaf");
  if (el && currentTab().focus !== el.dataset.leaf) bus.cmd("pane.focus", { id: el.dataset.leaf });
}

function dragDivider(e, bar) {
  e.preventDefault();
  bar.classList.add("drag");
  bar.setPointerCapture(e.pointerId);
  const split = bar.parentElement, box = split.getBoundingClientRect(), row = bar.classList.contains("row");
  let ratio = null;
  const move = (ev) => {
    ratio = Math.min(0.85, Math.max(0.15, row ? (ev.clientX - box.left) / box.width : (ev.clientY - box.top) / box.height));
    split.children[0].style.flexGrow = ratio;
    split.children[2].style.flexGrow = 1 - ratio;
  };
  const up = () => {
    bar.classList.remove("drag");
    bar.removeEventListener("pointermove", move);
    bar.removeEventListener("pointerup", up);
    if (ratio !== null) bus.cmd("pane.ratio", { path: split.dataset.path, ratio });
  };
  bar.addEventListener("pointermove", move);
  bar.addEventListener("pointerup", up);
}

// The grab handle shows while the pointer is in the top band of a pane (drag-handle auto).
function markNear(e) {
  for (const el of host.querySelectorAll(".tabview:not([hidden]) .leaf")) {
    const r = el.getBoundingClientRect();
    el.classList.toggle("near", e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.top + Math.max(12, r.height * 0.2));
  }
}

// Focus the nearest leaf whose centre lies in that direction.
function goTo(dir) {
  const tab = currentTab(), centre = (el) => { const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; };
  const view = views.get(tab.id).el, from = centre(view.querySelector(`[data-leaf="${tab.focus}"]`));
  const ahead = { left: (p) => p.x < from.x - 1, right: (p) => p.x > from.x + 1, up: (p) => p.y < from.y - 1, down: (p) => p.y > from.y + 1 }[dir];
  let best = null, nearest = Infinity;
  for (const el of view.querySelectorAll(".leaf")) {
    const p = centre(el), d = Math.hypot(p.x - from.x, p.y - from.y);
    if (el.dataset.leaf !== tab.focus && ahead(p) && d < nearest) { best = el.dataset.leaf; nearest = d; }
  }
  if (best) bus.cmd("pane.focus", { id: best });
}
