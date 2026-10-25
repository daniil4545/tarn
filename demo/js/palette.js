// Command palette (Shift+Cmd+P): every key row is a command; type to filter, Enter runs.
import { bus } from "./bus.js";
import { currentTab, paneOf } from "./workspace.js";

let box;
let input;
let list;
let rows = [];
let shown = [];
let pick = 0;

const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

export function startPalette(keyRows) {
  rows = keyRows;
  document.getElementById("main").insertAdjacentHTML("beforeend", '<div class="palette" id="palette" hidden><input type="text" placeholder="Type a command" aria-label="Command palette"><div class="list" role="listbox"></div></div>');
  box = document.getElementById("palette");
  input = box.querySelector("input");
  list = box.querySelector(".list");
  input.addEventListener("input", () => { pick = 0; draw(); });
  input.addEventListener("keydown", onKey);
  list.addEventListener("click", (e) => { const item = e.target.closest("[data-row]"); if (item) run(shown[Number(item.dataset.row)]); });
  box.addEventListener("click", (e) => { if (e.target === box) close(); });
  bus.handle("palette.open", () => {
    box.hidden = false;
    input.value = "";
    pick = 0;
    draw();
    input.focus();
  });
}

function draw() {
  const words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
  shown = rows.filter((r) => words.every((w) => `${r.group} ${r.text}`.toLowerCase().includes(w)));
  list.innerHTML = shown.map((r, i) => `<div class="item${i === pick ? " on" : ""}" role="option" data-row="${i}"><span>${esc(r.text)}</span><kbd>${esc(r.chords[0])}</kbd></div>`).join("") || '<div class="item">No command</div>';
}

function onKey(e) {
  if (e.key === "Escape") return close();
  if (e.key === "Enter") return run(shown[pick]);
  const move = { ArrowDown: 1, ArrowUp: -1 }[e.key];
  if (!move || !shown.length) return;
  e.preventDefault();
  pick = (pick + move + shown.length) % shown.length;
  draw();
}

function close() {
  box.hidden = true;
  paneOf(currentTab()?.focus)?.focus();
}

function run(row) {
  if (!row) return;
  close();
  bus.cmd(row.cmd, row.payload);
}
