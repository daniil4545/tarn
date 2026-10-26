// Drop zones for panes, viewers and files (docs/specs/windows-workspaces.md section 3a).
// A line shows where the dragged thing will stand: the cut between it and what stays. Zones, first match wins: a corner of the
// tab area, a strip at its edge, the tab bar or middle of a viewer, the half of a pane.
// File drags carry JSON in the data-drag attribute: {kind: "file", path, from?: viewerId, idx?}.
import { bus } from "./bus.js";
import * as tree from "./layout.js";
import { currentTab } from "./workspace.js";

const EDGE = 24, CORNER = 48, VIEWER_BAR = 32, MIDDLE = 0.15, LINE = 3;
const HALF = { left: [0, 0, 0.5, 1], right: [0.5, 0, 0.5, 1], top: [0, 0, 1, 0.5], bottom: [0, 0.5, 1, 0.5] };
const NO_SPLIT = "Split terminals stay together: drag them inside the block";

let drag = null; // {term: id} | {viewer: id} | {file: payload}

function onDragStart(e) {
  const grip = e.target.closest?.("[data-grip]"), file = e.target.closest?.("[data-drag]");
  if (grip) drag = grip.dataset.grip.startsWith("v") ? { viewer: grip.dataset.grip } : { term: grip.dataset.grip };
  else if (file) drag = { file: JSON.parse(file.dataset.drag) };
  else return;
  document.body.classList.add("dragging");
  e.dataTransfer.effectAllowed = "move";
  e.dataTransfer.setData("text/plain", "tarn");
}

// A split dropped outside every window opens a new window, as in Ghostty.
function onDragEnd(e) {
  const out = e.screenX < window.screenX || e.screenY < window.screenY
    || e.screenX > window.screenX + outerWidth || e.screenY > window.screenY + outerHeight;
  if (drag && out) bus.emit("toast", { text: drag.term ? "Terminal moves to a new window" : drag.viewer ? "Viewer moves to a new window" : "File opens in a new window" });
  endDrag();
}

// The drag is over, by dragend or by a drop that moved the source out of the document (a moved
// pane or frame never gets its dragend): clear the state either way.
function endDrag() {
  drag = null;
  document.body.classList.remove("dragging");
  clearFrame();
  bus.emit("drag:end", {});
}

// Drags that start in another document (the viewer iframe) feed the same zones.
export function watchDragSource(doc) {
  doc.addEventListener("dragstart", onDragStart);
  doc.addEventListener("dragend", onDragEnd);
}

export function startDnd() {
  watchDragSource(document);
  document.addEventListener("dragover", (e) => {
    if (!drag) return;
    const target = resolve(e);
    if (!target) return clearFrame();
    e.preventDefault();
    showFrame(target);
  });
  document.addEventListener("drop", (e) => {
    if (!drag) return;
    const target = resolve(e);
    clearFrame();
    e.preventDefault();
    if (target && !target.deny) target.run();
    endDrag();
  });
}

const box = (r) => ({ x: r.left, y: r.top, w: r.width, h: r.height });
const draggedId = () => drag.term ?? drag.viewer ?? null;

function edgeZone(r, e) {
  const fx = (e.clientX - r.x) / r.w, fy = (e.clientY - r.y) / r.h, edge = Math.min(fx, 1 - fx, fy, 1 - fy);
  return edge === fx ? "left" : edge === 1 - fx ? "right" : edge === fy ? "top" : "bottom";
}

function resolve(e) {
  const tab = currentTab(), ws = document.getElementById("ws");
  const area = box(ws.getBoundingClientRect());
  return resolveArea(e, tab, area) ?? resolveLeaf(e, tab);
}

// What a drop would do, as {frame: [l, t, w, h] in pixels, deny, run}.
function plan(frame, deny, run, zone) { return { frame, deny, run, zone }; }

function place(zone, target) {
  const id = draggedId();
  if (drag.file) {
    return () => {
      const viewer = bus.cmd("pane.place", { viewer: true, zone, target });
      if (viewer) bus.cmd("viewer.take", { to: viewer, drag: drag.file });
    };
  }
  return () => bus.cmd("pane.place", { id, zone, target });
}

function resolveArea(e, tab, a) {
  const x = e.clientX - a.x, y = e.clientY - a.y;
  if (x < 0 || y < 0 || x > a.w || y > a.h) return null;
  const v = y < CORNER ? "top" : y > a.h - CORNER ? "bottom" : null;
  const h = x < CORNER ? "left" : x > a.w - CORNER ? "right" : null;
  const corner = v && h;
  const strip = x < EDGE ? "left" : x > a.w - EDGE ? "right" : y < EDGE ? "top" : y > a.h - EDGE ? "bottom" : null;
  if (!corner && !strip) return null;

  const id = draggedId(), rest = id ? tree.remove(tab.layout, id) : tab.layout;
  const frameOf = (f) => [a.x + f[0] * a.w, a.y + f[1] * a.h, f[2] * a.w, f[3] * a.h];
  let deny = null;
  if (drag.term && tree.blockPath(tab.layout) !== "" && tree.terminals(tab.layout).length > 1) deny = NO_SPLIT;
  if (!rest) deny = "Nothing to drop beside";

  if (corner && rest && tree.isSplit(rest)) {
    const row = rest.dir === "row", side = row ? (h === "left" ? "a" : "b") : (v === "top" ? "a" : "b");
    const start = side === "a" ? 0 : rest.ratio, size = side === "a" ? rest.ratio : 1 - rest.ratio;
    const f = row ? [start, v === "top" ? 0 : 0.5, size, 0.5] : [h === "left" ? 0 : 0.5, start, 0.5, size];
    const zone = row ? v : h;
    return plan(frameOf(f), deny, place(zone, { child: side }), zone);
  }
  const zone = strip ?? (Math.min(x, a.w - x) < Math.min(y, a.h - y) ? h : v);
  return plan(frameOf(HALF[zone]), deny, place(zone, "root"), zone);
}

function blockBox(leafEl) {
  const rects = [...leafEl.closest(".tabview").querySelectorAll('.leaf[data-kind="term"]')].map((l) => l.getBoundingClientRect());
  const left = Math.min(...rects.map((r) => r.left)), top = Math.min(...rects.map((r) => r.top));
  return { x: left, y: top, w: Math.max(...rects.map((r) => r.right)) - left, h: Math.max(...rects.map((r) => r.bottom)) - top };
}

function resolveLeaf(e, tab) {
  const el = e.target.closest?.(".leaf");
  if (!el) return null;
  const id = el.dataset.leaf, r = box(el.getBoundingClientRect());
  const frameOf = (b, zone) => [b.x + HALF[zone][0] * b.w, b.y + HALF[zone][1] * b.h, HALF[zone][2] * b.w, HALF[zone][3] * b.h];
  const lone = tree.terminals(tab.layout).length === 1;

  if (drag.term) {
    const zone = edgeZone(r, e);
    const deny = el.dataset.kind === "viewer" ? (lone ? null : "Split terminals stay together: drag the viewer to the block edge") : (id === drag.term ? "Drop on another terminal" : null);
    return plan(frameOf(r, zone), deny, place(zone, { leaf: id }), zone);
  }
  if (el.dataset.kind === "term") {
    const b = blockBox(el), zone = edgeZone(b, e);
    return plan(frameOf(b, zone), null, place(zone, "block"), zone);
  }
  // A viewer: its tab bar or middle box means "into this viewer", the rest the half of it.
  const fx = (e.clientX - r.x) / r.w, fy = (e.clientY - r.y) / r.h;
  const into = e.clientY - r.y < VIEWER_BAR || (Math.abs(fx - 0.5) < MIDDLE && Math.abs(fy - 0.5) < MIDDLE);
  const below = { ...r, y: r.y + VIEWER_BAR, h: r.h - VIEWER_BAR };
  const own = drag.viewer === id || (into && drag.file?.from === id);
  const deny = own ? "Drop on another pane" : null;
  if (into) {
    const run = drag.file ? () => bus.cmd("viewer.take", { to: id, drag: drag.file }) : () => bus.cmd("viewer.merge", { from: drag.viewer, to: id });
    return plan([below.x, below.y, below.w, below.h], deny, run, "into");
  }
  const zone = edgeZone(r, e);
  return plan(frameOf(below, zone), deny, place(zone, { leaf: id }), zone);
}

// The cut between the new window and the rest, as a LINE-wide bar centred on it. `frame` is the
// space the new window takes; a drop into a viewer's tabs marks the top edge of its content.
function lineOf([x, y, w, h], zone) {
  const half = LINE / 2;
  if (zone === "left") return [x + w - half, y, LINE, h];
  if (zone === "top") return [x, y + h - half, w, LINE];
  if (zone === "right") return [x - half, y, LINE, h];
  return [x, y - half, w, LINE];
}

function showFrame({ frame, deny, zone }) {
  const ws = document.getElementById("ws"), origin = ws.getBoundingClientRect();
  let el = ws.querySelector(":scope > .drop");
  if (!el) { el = Object.assign(document.createElement("div"), { className: "drop" }); ws.append(el); }
  el.classList.toggle("deny", Boolean(deny));
  el.innerHTML = deny ? `<span>${deny}</span>` : "";
  const [x, y, w, h] = deny ? frame : lineOf(frame, zone);
  Object.assign(el.style, { left: `${x - origin.left}px`, top: `${y - origin.top}px`, width: `${w}px`, height: `${h}px` });
}

const clearFrame = () => document.querySelectorAll("#ws > .drop").forEach((d) => d.remove());
