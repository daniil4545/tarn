// Drag inside the sidebar: a tab row onto a header (end of that workspace) or onto a row (before
// it in the upper half, after it in the lower), a workspace header into the gap nearest the
// pointer. Both are marked by a line where the row will land, as SidebarModel.dropSlot in the app.
import { bus } from "./bus.js";

let drag = null; // {tab: id} | {ws: id}

export function startSidebarDrag() {
  const sb = document.getElementById("sidebar");
  sb.addEventListener("dragstart", (e) => {
    const row = e.target.closest(".tab[data-tabid]"), head = e.target.closest(".wsh[data-wsh]");
    if (!row && !head) return;
    drag = row ? { tab: row.dataset.tabid } : { ws: head.dataset.wsh };
    document.body.classList.add("dragging");
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", "tarn-tab");
  });
  sb.addEventListener("dragover", (e) => {
    if (!drag) return;
    clearMarks();
    if (drag.tab) markTab(e); else drawLine(e);
  });
  sb.addEventListener("drop", (e) => {
    if (!drag) return;
    e.preventDefault();
    if (drag.tab) dropTab(e); else dropWorkspace(e);
  });
  document.addEventListener("dragend", () => {
    drag = null;
    document.body.classList.remove("dragging");
    clearMarks();
  });
}

function clearMarks() {
  document.querySelectorAll(".wsline").forEach((x) => x.remove());
}

// Where a dragged tab lands: {ws, before (a tab id or null for the end), edge (the element whose
// top or bottom the line takes), bottom}. Null off the rows.
function tabSlot(e) {
  const head = e.target.closest(".wsh[data-wsh]"), row = e.target.closest(".tab[data-tabid]");
  const rowsOf = (h) => {
    const rows = [];
    for (let x = h.nextElementSibling; x?.matches(".tab[data-tabid]"); x = x.nextElementSibling) rows.push(x);
    return rows;
  };
  if (head) {
    const rows = rowsOf(head);
    return { ws: head.dataset.wsh, before: null, edge: rows.at(-1) ?? head, bottom: true };
  }
  if (!row) return null;
  let owner = row;
  while (!owner.dataset.wsh) owner = owner.previousElementSibling;
  const r = row.getBoundingClientRect();
  if (e.clientY < r.top + r.height / 2) return { ws: owner.dataset.wsh, before: row.dataset.tabid, edge: row, bottom: false };
  const next = row.nextElementSibling?.matches(".tab[data-tabid]") ? row.nextElementSibling : null;
  return { ws: owner.dataset.wsh, before: next?.dataset.tabid ?? null, edge: row, bottom: true };
}

function markTab(e) {
  const at = tabSlot(e);
  if (!at) return;
  e.preventDefault();
  const sb = document.getElementById("sidebar"), r = at.edge.getBoundingClientRect();
  const line = Object.assign(document.createElement("div"), { className: "wsline" });
  line.style.top = `${(at.bottom ? r.bottom : r.top) - sb.getBoundingClientRect().top + sb.scrollTop - 1}px`;
  sb.append(line);
}

function dropTab(e) {
  const at = tabSlot(e);
  if (!at || at.before === drag.tab) return;
  bus.cmd("tab.move", { id: drag.tab, ws: at.ws, before: at.before });
}

// Slot i is the gap before group i; a group spans from its header to the next header.
function slot(y) {
  const sb = document.getElementById("sidebar"), heads = [...sb.querySelectorAll(".wsh[data-wsh]")];
  const tops = [...heads.map((h) => h.getBoundingClientRect().top), document.getElementById("wsNew").getBoundingClientRect().top];
  const i = heads.filter((_, n) => (tops[n] + tops[n + 1]) / 2 < y).length;
  return { before: heads[i]?.dataset.wsh ?? null, y: tops[i] - sb.getBoundingClientRect().top + sb.scrollTop };
}

function drawLine(e) {
  e.preventDefault();
  const sb = document.getElementById("sidebar"), line = Object.assign(document.createElement("div"), { className: "wsline" });
  line.style.top = `${slot(e.clientY).y - 4}px`;
  sb.append(line);
}

function dropWorkspace(e) {
  const id = drag.ws, { before } = slot(e.clientY);
  if (before !== id) bus.cmd("ws.move", { id, before });
}
