// Drag inside the sidebar: a tab row onto a header (end of that workspace) or onto a row (before
// it), a workspace header into the gap nearest the pointer, marked by a line.
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
    if (drag.tab) markRow(e); else drawLine(e);
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
  document.querySelectorAll(".dropmark").forEach((x) => x.classList.remove("dropmark"));
}

function markRow(e) {
  const target = e.target.closest(".wsh[data-wsh], .tab[data-tabid]");
  if (!target) return;
  e.preventDefault();
  target.classList.add("dropmark");
}

function dropTab(e) {
  const id = drag.tab, head = e.target.closest(".wsh[data-wsh]"), row = e.target.closest(".tab[data-tabid]");
  if (head) return bus.cmd("tab.move", { id, ws: head.dataset.wsh });
  if (!row || row.dataset.tabid === id) return;
  let owner = row;
  while (!owner.dataset.wsh) owner = owner.previousElementSibling;
  bus.cmd("tab.move", { id, ws: owner.dataset.wsh, before: row.dataset.tabid });
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
