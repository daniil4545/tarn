// Rows and group blocks share the pointer drag, lifted copy and animated gap.
import { bus } from "./bus.js";

let press = null; // {row, x, y, id, moved} from pointerdown until pointerup
let tab = null; // {id, row, height, ghost, grab, at: {ws, before}, below} once a tab moves

export function startSidebarDrag() {
  const sb = document.getElementById("sidebar");
  sb.addEventListener("pointerdown", (e) => {
    const row = e.target.closest(".tab[data-tabid], .wsh:not(.flat)");
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
      tab = lift(press.row.matches(".wsh") ? press.row.closest(".wsblock") : press.row, press);
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
    if (inside && done.at) bus.cmd(done.workspace ? "ws.move" : "tab.move", { id: done.id, ...done.at });
  });
  document.addEventListener("pointercancel", () => { press = null; endTab(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") endTab(); });

  sb.addEventListener("dragstart", (e) => {
    if (e.target.closest(".wsh")) e.preventDefault();
  });
}

function swallow(e) {
  e.stopPropagation();
}

// The row folds to nothing and the element below it takes the row's slot as a top margin, so
// nothing moves until the pointer does.
function lift(row, at) {
  const owner = row.closest("[data-block]");
  const r = row.getBoundingClientRect();
  const workspace = row.matches(".wsblock");
  const ghost = Object.assign(row.cloneNode(true), { className: `${row.className} dragghost` });
  Object.assign(ghost.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px` });
  ghost.removeAttribute("data-tabid");
  document.body.append(ghost);
  document.body.classList.add("dragging");
  bus.emit("drag:start", {});
  // The slot is the row and the space between rows.
  const t = {
    id: workspace ? row.dataset.block : row.dataset.tabid, workspace, row,
    height: r.height + parseFloat(getComputedStyle(row.parentElement).rowGap || 0) + (workspace ? 8 : 0), ghost,
    grab: { x: at.x - r.left, y: at.y - r.top },
    at: workspace ? { before: nextShown(row)?.dataset.block || null } : { ws: owner.dataset.block, before: nextTab(row) }, below: null,
  };
  row.classList.add("lifted");
  openGap(t, nextShown(row), false);
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

// The gap stands above `below`: a row, a group's end, a block or the New group button.
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
  if (head) return null;
  if (el === sb) {
    const below = [...sb.querySelectorAll(".wsblock")].find((b) => y < b.getBoundingClientRect().top) || end;
    return { ws: "loose", before: below.dataset.block || null, below };
  }
  if (!row || row.classList.contains("lifted")) return null;
  const owner = row.closest("[data-block]");
  const r = row.getBoundingClientRect();
  if (y < r.top + r.height / 2) return { ws: owner.dataset.block, before: row.dataset.tabid, below: row };
  return { ws: owner.dataset.block, before: nextTab(row), below: nextShown(row) };
}

function moveGap(sb, el, y) {
  if (!el || !sb.contains(el)) {
    if (tab.below) tab.below.style.marginTop = "";
    tab.below = tab.at = null;
    return;
  }
  const at = tab.workspace ? slot(sb, el, y) : tabSlot(sb, el, y);
  if (!at) return;
  tab.at = tab.workspace ? { before: at.before, beforeTab: at.beforeTab ?? null } : { ws: at.ws, before: at.before };
  if (at.below !== tab.below) openGap(tab, at.below, true);
}

// Slot i is the gap before block i: a group from its header, an ungrouped block (hidden header)
// from its first row, up to the next block.
function slot(sb, el, y) {
  const end = document.getElementById("wsNew"), block = el.closest(".wsblock");
  let below = end;
  const row = el.closest(".wsblock:not(.group) .tab[data-tabid]");
  if (row) {
    // Ungrouped rows split by their own halves, as for a tab.
    const r = row.getBoundingClientRect();
    below = y < r.top + r.height / 2 ? row : nextShown(row);
    if (below.matches(".tab[data-tabid]")) return { before: null, beforeTab: below.dataset.tabid, below };
    below = nextShown(block);
  } else if (block && !block.classList.contains("lifted")) {
    const r = block.getBoundingClientRect();
    below = y < r.top + r.height / 2 ? block : nextShown(block);
  } else if (el === sb) {
    below = [...sb.querySelectorAll(".wsblock:not(.lifted)")].find((b) => y < b.getBoundingClientRect().top) || end;
  } else if (!el.closest("#wsNew")) return null;
  return { before: below.dataset.block || null, below };
}
