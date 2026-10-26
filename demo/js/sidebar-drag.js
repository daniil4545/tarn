// Drag inside the sidebar. A tab row lifts out of the list and the rows slide apart to open a
// gap where it lands, as in Warp: before a row in its upper half, after it in its lower half, at
// the end of a workspace over its header. A workspace header goes into the gap nearest the
// pointer (a line). Slots follow SidebarModel.dropSlot in the app.
import { bus } from "./bus.js";

let drag = null; // {tab: id, row, height, at: {ws, before}} | {ws: id}

export function startSidebarDrag() {
  const sb = document.getElementById("sidebar");
  sb.addEventListener("dragstart", (e) => {
    const row = e.target.closest(".tab[data-tabid]"), head = e.target.closest(".wsh[data-wsh]");
    if (!row && !head) return;
    drag = row ? lift(row, e) : { ws: head.dataset.wsh };
    document.body.classList.add("dragging");
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", "tarn-tab");
  });
  // The browser draws its drag picture faded; the lifted row is drawn by the page instead, solid.
  document.addEventListener("dragover", (e) => {
    if (!drag?.ghost) return;
    drag.ghost.style.left = `${e.clientX - drag.grab.x}px`;
    drag.ghost.style.top = `${e.clientY - drag.grab.y}px`;
  });
  sb.addEventListener("dragover", (e) => {
    if (!drag) return;
    e.preventDefault();
    if (drag.tab) moveGap(e);
    else drawLine(e);
  });
  sb.addEventListener("drop", (e) => {
    if (!drag) return;
    e.preventDefault();
    if (drag.tab) dropTab();
    else dropWorkspace(e);
  });
  document.addEventListener("dragend", () => {
    if (drag?.row) drag.row.classList.remove("lifted");
    drag = null;
    document.body.classList.remove("dragging");
    document.querySelectorAll(".wsline, .dropgap, .dragghost").forEach((x) => x.remove());
  });
}

// The row leaves the list after the browser has taken its picture; a gap of its height stays in
// its place, so nothing moves until the pointer does.
function lift(row, e) {
  let owner = row;
  while (!owner.dataset.wsh) owner = owner.previousElementSibling;
  const r = row.getBoundingClientRect();
  const ghost = Object.assign(row.cloneNode(true), { className: `${row.className} dragghost` });
  Object.assign(ghost.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px` });
  ghost.removeAttribute("data-tabid");
  document.body.append(ghost);
  e.dataTransfer.setDragImage(new Image(), 0, 0);
  const d = {
    tab: row.dataset.tabid, row, height: row.offsetHeight, ghost, grab: { x: e.clientX - r.left, y: e.clientY - r.top },
    at: { ws: owner.dataset.wsh, before: nextTab(row) },
  };
  setTimeout(() => {
    if (drag !== d) return;
    row.after(gap(d.height, false));
    row.classList.add("lifted");
  });
  return d;
}

function gap(height, grow) {
  const g = Object.assign(document.createElement("div"), { className: "dropgap" });
  g.style.height = grow ? "0px" : `${height}px`;
  if (grow) requestAnimationFrame(() => requestAnimationFrame(() => { g.style.height = `${height}px`; }));
  return g;
}

// The next visible tab row of the same workspace, or null at its end.
function nextTab(el) {
  let n = el.nextElementSibling;
  while (n && (n.classList.contains("dropgap") || n.classList.contains("lifted"))) n = n.nextElementSibling;
  return n?.matches(".tab[data-tabid]") ? n.dataset.tabid : null;
}

// Where a dragged tab lands and the element the gap goes after. Null over the gap itself and off
// the rows: the gap stays where it is.
function tabSlot(e) {
  const head = e.target.closest(".wsh[data-wsh]"), row = e.target.closest(".tab[data-tabid]");
  if (head) {
    let last = head;
    while (last.nextElementSibling?.matches(".tab[data-tabid], .dropgap")) last = last.nextElementSibling;
    return { ws: head.dataset.wsh, before: null, after: last };
  }
  if (!row || row.classList.contains("lifted")) return null;
  let owner = row;
  while (!owner.dataset.wsh) owner = owner.previousElementSibling;
  const r = row.getBoundingClientRect();
  if (e.clientY < r.top + r.height / 2) return { ws: owner.dataset.wsh, before: row.dataset.tabid, after: row.previousElementSibling };
  return { ws: owner.dataset.wsh, before: nextTab(row), after: row };
}

function moveGap(e) {
  const at = tabSlot(e);
  if (!at || (at.ws === drag.at.ws && at.before === drag.at.before)) return;
  drag.at = { ws: at.ws, before: at.before };
  document.querySelectorAll(".dropgap:not(.closing)").forEach((g) => {
    g.classList.add("closing");
    g.style.height = "0px";
    setTimeout(() => g.remove(), 200);
  });
  at.after.after(gap(drag.height, true));
}

function dropTab() {
  bus.cmd("tab.move", { id: drag.tab, ...drag.at });
}

// Slot i is the gap before group i; a group spans from its header to the next header.
function slot(y) {
  const sb = document.getElementById("sidebar"), heads = [...sb.querySelectorAll(".wsh[data-wsh]")];
  const tops = [...heads.map((h) => h.getBoundingClientRect().top), document.getElementById("wsNew").getBoundingClientRect().top];
  const i = heads.filter((_, n) => (tops[n] + tops[n + 1]) / 2 < y).length;
  return { before: heads[i]?.dataset.wsh ?? null, y: tops[i] - sb.getBoundingClientRect().top + sb.scrollTop };
}

function drawLine(e) {
  document.querySelectorAll(".wsline").forEach((x) => x.remove());
  const sb = document.getElementById("sidebar"), line = Object.assign(document.createElement("div"), { className: "wsline" });
  line.style.top = `${slot(e.clientY).y - 4}px`;
  sb.append(line);
}

function dropWorkspace(e) {
  const id = drag.ws, { before } = slot(e.clientY);
  if (before !== id) bus.cmd("ws.move", { id, before });
}
