// Drag inside the sidebar. A tab row follows the pointer as in Warp: after a 4 px move the row
// folds out of the list, a solid copy follows the pointer, and the rows slide apart to a gap where
// it lands: before a row in its upper half, after it in its lower half, at the end of a workspace
// over its header, among the ungrouped tabs below the rows. Tab rows use pointer events,
// not HTML5 drag: browsers lose the drop or cancel the drag when the list moves under it. A
// workspace header goes into the gap nearest the pointer (HTML5 drag, a line). Slots follow
// SidebarModel.dropSlot in the app.
import { bus } from "./bus.js";

let drag = null; // {ws: id} during a workspace drag
let press = null; // {row, x, y, id, moved} from pointerdown until pointerup
let tab = null; // {id, row, height, ghost, grab, at: {ws, before}, below} once a tab moves

export function startSidebarDrag() {
  const sb = document.getElementById("sidebar");
  sb.addEventListener("pointerdown", (e) => {
    const row = e.target.closest(".tab[data-tabid]");
    if (e.button !== 0 || !row || e.target.closest("button") || sb.classList.contains("rail")) return;
    press = { row, x: e.clientX, y: e.clientY, id: e.pointerId, moved: false };
  });
  document.addEventListener("pointermove", (e) => {
    if (!press || e.pointerId !== press.id) return;
    if (!tab) {
      // A drag ended by Esc waits for the release; a row rebuilt under the press is gone.
      if (press.moved || Math.hypot(e.clientX - press.x, e.clientY - press.y) < 4) return;
      if (!press.row.isConnected) return void (press = null);
      press.moved = true;
      tab = lift(press.row, press);
    }
    tab.ghost.style.left = `${e.clientX - tab.grab.x}px`;
    tab.ghost.style.top = `${e.clientY - tab.grab.y}px`;
    moveGap(sb, document.elementFromPoint(e.clientX, e.clientY), e.clientY);
  });
  document.addEventListener("pointerup", (e) => {
    if (!press || e.pointerId !== press.id) return;
    const { moved } = press;
    press = null;
    if (!moved) return;
    // The click that ends a drag, dispatched before any timer, does not select the row under it.
    document.addEventListener("click", swallow, true);
    setTimeout(() => document.removeEventListener("click", swallow, true));
    if (!tab) return;
    const inside = sb.contains(document.elementFromPoint(e.clientX, e.clientY));
    const done = tab;
    endTab();
    if (inside) bus.cmd("tab.move", { id: done.id, ...done.at });
  });
  document.addEventListener("pointercancel", () => { press = null; endTab(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") endTab(); });

  sb.addEventListener("dragstart", (e) => {
    const head = e.target.closest(".wsh[data-wsh]");
    if (!head) return;
    drag = { ws: head.dataset.wsh };
    document.body.classList.add("dragging");
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", "tarn-workspace");
  });
  sb.addEventListener("dragover", (e) => {
    if (!drag) return;
    e.preventDefault();
    drawLine(e);
  });
  sb.addEventListener("drop", (e) => {
    if (!drag) return;
    e.preventDefault();
    dropWorkspace(e);
  });
  document.addEventListener("dragend", () => {
    if (!drag) return;
    drag = null;
    document.body.classList.remove("dragging");
    document.querySelectorAll(".wsline").forEach((x) => x.remove());
  });
}

function swallow(e) {
  e.stopPropagation();
}

// The row folds to nothing and the element below it takes the row's slot as a top margin, so
// nothing moves until the pointer does.
function lift(row, at) {
  let owner = row;
  while (!owner.dataset.wsh) owner = owner.previousElementSibling;
  const r = row.getBoundingClientRect();
  const ghost = Object.assign(row.cloneNode(true), { className: `${row.className} dragghost` });
  Object.assign(ghost.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px` });
  ghost.removeAttribute("data-tabid");
  document.body.append(ghost);
  document.body.classList.add("dragging");
  bus.emit("drag:start", {});
  // The slot is the row and the space between rows.
  const t = {
    id: row.dataset.tabid, row, height: r.height + parseFloat(getComputedStyle(row.parentElement).rowGap || 0), ghost,
    grab: { x: at.x - r.left, y: at.y - r.top }, at: { ws: owner.dataset.wsh, before: nextTab(row) }, below: null,
  };
  row.classList.add("lifted");
  openGap(t, nextShown(row), false);
  t.home = { at: { ...t.at }, below: t.below };
  return t;
}

function endTab() {
  if (!tab) return;
  tab.row.classList.remove("lifted");
  if (tab.below) tab.below.style.marginTop = "";
  tab.ghost.remove();
  tab = null;
  document.body.classList.remove("dragging");
  bus.emit("drag:end", {});
}

// The gap stands above `below`: a tab row, the next group header or the New group button.
// Its own margin is read with the slide off, so a margin still sliding back does not count.
function openGap(t, below, slide) {
  if (t.below) t.below.style.marginTop = "";
  t.below = below;
  below.style.transition = "none";
  below.style.marginTop = "";
  const base = parseFloat(getComputedStyle(below).marginTop);
  below.style.transition = slide ? "" : "none";
  below.style.marginTop = `${base + t.height}px`;
  if (!slide) requestAnimationFrame(() => { below.style.transition = ""; });
}

function nextShown(el) {
  let n = el.nextElementSibling;
  while (n?.classList.contains("lifted")) n = n.nextElementSibling;
  return n;
}

// The next shown tab row of the same workspace, or null at its end.
function nextTab(el) {
  const n = nextShown(el);
  return n?.matches(".tab[data-tabid]") ? n.dataset.tabid : null;
}

// Where a tab over `el` at height `y` lands and the element the gap goes above. Null between the
// rows, the gap included: the gap stays where it is.
function tabSlot(sb, el, y) {
  if (!el || !sb.contains(el)) return null;
  const end = document.getElementById("wsNew");
  if (el.closest("#wsNew") || (el === sb && y >= end.getBoundingClientRect().top)) {
    return { ws: "loose", before: null, below: end };
  }
  const head = el.closest(".wsh[data-wsh]"), row = el.closest(".tab[data-tabid]");
  if (head) {
    let below = nextShown(head);
    while (below.matches(".tab[data-tabid]")) below = nextShown(below);
    return { ws: head.dataset.wsh, before: null, below };
  }
  if (!row || row.classList.contains("lifted")) return null;
  let owner = row;
  while (!owner.dataset.wsh) owner = owner.previousElementSibling;
  const r = row.getBoundingClientRect();
  if (y < r.top + r.height / 2) return { ws: owner.dataset.wsh, before: row.dataset.tabid, below: row };
  return { ws: owner.dataset.wsh, before: nextTab(row), below: nextShown(row) };
}

// Outside the sidebar the gap goes back to the row's own slot: a release there moves nothing.
function moveGap(sb, el, y) {
  if (!el || !sb.contains(el)) {
    if (tab.below !== tab.home.below) openGap(tab, tab.home.below, true);
    tab.at = { ...tab.home.at };
    return;
  }
  const at = tabSlot(sb, el, y);
  if (!at || at.below === tab.below) return;
  tab.at = { ws: at.ws, before: at.before };
  openGap(tab, at.below, true);
}

// Slot i is the gap before group i; a group spans from its header to the next header.
function slot(y) {
  const sb = document.getElementById("sidebar"), heads = [...sb.querySelectorAll(".wsh[data-wsh]:not(.flat)")];
  const end = sb.querySelector(".wsh.flat + .tab") ?? document.getElementById("wsNew");
  const tops = [...heads.map((h) => h.getBoundingClientRect().top), end.getBoundingClientRect().top];
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
