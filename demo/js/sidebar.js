// The sidebar: workspaces as groups of tab rows, a rail of icons, resize by the edge, menus.
// Counterpart of Sidebar.swift (SidebarLayout, Sidebar). Drag of rows and headers: sidebar-drag.js.
import { bus } from "./bus.js";
import { read } from "./state.js";
import { load, save } from "./storage.js";
import { flatTabs } from "./workspace.js";
import { tabStatus, workspaceStatus, isAgentTab } from "./tab-status.js";

export const AGENT = '<svg class="agent" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2l1.8 6.2L20 6l-4.2 4.9L22 12l-6.2 1.1L20 18l-6.2-2.2L12 22l-1.8-6.2L4 18l4.2-4.9L2 12l6.2-1.1L4 6l6.2 2.2z"/></svg>';
const TERM = '<svg class="agent" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9l3 3-3 3M13 15h4"/></svg>';
const TOGGLE = '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.3" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="2"/><path d="M6 2.5v11"/></svg>';

const RAIL_WIDTH = 44, MIN = 120, MAX = 400, FOLD_BELOW = 80;
const ui = { rail: false, width: 200, ...load("sidebar", {}) };
let sb;
let stale = false;

const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
export const dot = (status) => (status ? `<span class="dot" style="background:${status.color}" title="${status.label}"></span>` : "");

export function startSidebar() {
  sb = document.getElementById("sidebar");
  render();
  bus.on("state:changed", ({ part }) => { if (part === "workspaces" || part === "registry") render(); });
  sb.addEventListener("click", onClick);
  sb.addEventListener("contextmenu", onContextMenu);
  document.addEventListener("click", (e) => { if (!e.target.closest("#ctx")) closeMenu(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeMenu(); });
  document.addEventListener("dragend", () => { if (stale) setTimeout(render); });
  bus.on("drag:end", () => { if (stale) setTimeout(render); });
  document.getElementById("sbGrip").addEventListener("pointerdown", dragEdge);
}

function render() {
  // A rebuild during a drag would drop the dragged row; it waits for dragend.
  stale = document.body.classList.contains("dragging");
  if (stale) return;
  const s = read("workspaces"), reg = read("registry"), order = flatTabs(s);
  sb.classList.toggle("rail", ui.rail);
  sb.style.width = ui.rail ? "" : `${ui.width}px`;
  const label = ui.rail ? "Show Sidebar" : "Hide Sidebar";
  const top = `<div class="sbtop"><button class="ib" id="sbToggle" title="${label}" aria-label="${label}">${TOGGLE}</button><button class="ib" id="sbNew" title="New tab" aria-label="New tab">+</button></div>`;
  const icon = (t) => (isAgentTab(t, reg) ? AGENT : TERM);
  if (ui.rail) {
    sb.innerHTML = top + s.wss.map((w) => w.tabs.map((id) => {
      const t = s.tabs[id];
      return `<div class="tab" role="tab" tabindex="0" aria-selected="${id === s.cur}" data-tabid="${id}" title="${esc(t.title)}">${icon(t)}${dot(tabStatus(t, reg))}</div>`;
    }).join("")).join('<div class="sep"></div>');
    return;
  }
  const key = (id) => { const i = order.indexOf(id); return i < 8 ? `⌘${i + 1}` : i === order.length - 1 ? "⌘9" : ""; };
  const row = (id) => {
    const t = s.tabs[id];
    return `<div class="tab" role="tab" draggable="true" tabindex="0" aria-selected="${id === s.cur}" data-tabid="${id}" title="${esc(t.cwd)}">${icon(t)}<span class="t">${esc(t.title)}</span>${dot(tabStatus(t, reg))}<span class="key">${key(id)}</span><button class="x" data-tabclose="${id}" aria-label="Close tab">✕</button></div>`;
  };
  sb.innerHTML = top + s.wss.map((w) => {
    const n = w.tabs.length;
    const folded = w.collapsed ? `<span class="cnt">${n}</span>${dot(workspaceStatus(w, s.tabs, reg))}` : "";
    const head = `<div class="wsh" data-wsh="${w.id}" draggable="true" role="button" tabindex="0" aria-expanded="${!w.collapsed}" title="${n} tab${n === 1 ? "" : "s"}"><span class="chev">${w.collapsed ? "▸" : "▾"}</span><span class="t">${esc(w.name)}</span>${folded}<button class="ib" data-wsnewtab="${w.id}" title="New tab in ${esc(w.name)}">+</button></div>`;
    return head + (w.collapsed ? "" : w.tabs.map(row).join(""));
  }).join("") + '<button class="tab add" id="wsNew">+ New workspace</button>';
}

function setUi(patch) {
  Object.assign(ui, patch);
  save("sidebar", ui);
  render();
}

function onClick(e) {
  const hit = e.target.closest("[data-tabclose], [data-wsnewtab], .wsh[data-wsh], #wsNew, #sbToggle, #sbNew, .tab[data-tabid]");
  if (!hit) return;
  const { dataset } = hit;
  if (dataset.tabclose) return bus.cmd("tab.close", { id: dataset.tabclose });
  if (dataset.wsnewtab) return bus.cmd("tab.new", { ws: dataset.wsnewtab });
  if (dataset.wsh) return bus.cmd("ws.fold", { id: dataset.wsh });
  if (hit.id === "wsNew") return newWorkspace();
  if (hit.id === "sbToggle") return setUi({ rail: !ui.rail });
  if (hit.id === "sbNew") return bus.cmd("tab.new");
  bus.cmd("tab.go", { id: dataset.tabid });
}

function newWorkspace() {
  const name = prompt("Workspace name")?.trim();
  if (name) bus.cmd("ws.new", { name });
}

function renameWorkspace(id) {
  const ws = read("workspaces").wss.find((w) => w.id === id), name = prompt("Workspace name", ws.name)?.trim();
  if (name) bus.cmd("ws.rename", { id, name });
}

function deleteWorkspace(id) {
  const { wss } = read("workspaces"), at = wss.findIndex((w) => w.id === id), into = wss[at > 0 ? at - 1 : 1];
  if (confirm(`Delete workspace ${wss[at].name}? Its ${wss[at].tabs.length} tab(s) move to ${into.name}.`)) bus.cmd("ws.delete", { id });
}

function onContextMenu(e) {
  const row = e.target.closest(".tab[data-tabid]"), head = e.target.closest(".wsh[data-wsh]");
  if (!row && !head) return;
  e.preventDefault();
  const { wss } = read("workspaces");
  if (row) {
    const id = row.dataset.tabid, here = wss.find((w) => w.tabs.includes(id));
    const moves = wss.filter((w) => w !== here).map((w) => ({ label: `Move to ${w.name}`, attrs: `data-mmove="${id}" data-to="${w.id}"`, run: () => bus.cmd("tab.move", { id, ws: w.id }) }));
    showMenu([...moves, { label: "Close tab", attrs: `data-tabclose="${id}"`, run: () => bus.cmd("tab.close", { id }) }], e);
  } else {
    const id = head.dataset.wsh;
    showMenu([
      { label: "New tab", attrs: `data-wsnewtab="${id}"`, run: () => bus.cmd("tab.new", { ws: id }) },
      { label: "Rename…", attrs: `data-wsren="${id}"`, run: () => renameWorkspace(id) },
      ...(wss.length < 2 ? [] : [{ label: "Delete workspace", attrs: `data-wsdel="${id}"`, run: () => deleteWorkspace(id) }]),
    ], e);
  }
}

const closeMenu = () => document.getElementById("ctx")?.remove();

function showMenu(items, { clientX, clientY }) {
  closeMenu();
  const menu = document.createElement("div");
  menu.className = "ctx";
  menu.id = "ctx";
  for (const item of items) {
    menu.insertAdjacentHTML("beforeend", `<button ${item.attrs}>${esc(item.label)}</button>`);
    menu.lastElementChild.addEventListener("click", () => { closeMenu(); item.run(); });
  }
  document.body.append(menu);
  menu.style.left = `${Math.min(clientX, innerWidth - 230)}px`;
  menu.style.top = `${Math.min(clientY, innerHeight - 34 * items.length)}px`;
}

// The edge strip resizes (120-400), folds to the rail when dragged below 80 and opens it again.
function dragEdge(e) {
  const grip = e.currentTarget, x0 = e.clientX, w0 = ui.rail ? RAIL_WIDTH : ui.width;
  e.preventDefault();
  grip.classList.add("drag");
  grip.setPointerCapture(e.pointerId);
  const move = (ev) => {
    const raw = w0 + ev.clientX - x0;
    if (raw < FOLD_BELOW) return ui.rail || setUi({ rail: true });
    if (ui.rail && raw < MIN) return;
    const width = Math.round(Math.min(MAX, Math.max(MIN, raw)));
    if (ui.rail) setUi({ rail: false, width });
    else { ui.width = width; sb.style.width = `${width}px`; }
  };
  const up = () => {
    grip.classList.remove("drag");
    grip.removeEventListener("pointermove", move);
    grip.removeEventListener("pointerup", up);
    save("sidebar", ui);
  };
  grip.addEventListener("pointermove", move);
  grip.addEventListener("pointerup", up);
}
