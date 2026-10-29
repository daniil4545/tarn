// The sidebar: workspaces as groups of tab rows, a rail of icons, resize by the edge, menus.
// Counterpart of Sidebar.swift (SidebarLayout, Sidebar). Drag of rows and headers: sidebar-drag.js.
import { bus } from "./bus.js";
import { read } from "./state.js";
import { isObject, load, save } from "./storage.js";
import { flatTabs } from "./workspace.js";
import { terminals } from "./layout.js";
import { tabStatus, workspaceStatus, isAgentTab } from "./tab-status.js";
import { esc } from "./esc.js";
import { clock } from "./clock.js";
import { isOn } from "./modules.js";
import { ask } from "./ask-dialog.js";

export const AGENT = '<svg class="agent" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2l1.8 6.2L20 6l-4.2 4.9L22 12l-6.2 1.1L20 18l-6.2-2.2L12 22l-1.8-6.2L4 18l4.2-4.9L2 12l6.2-1.1L4 6l6.2 2.2z"/></svg>';
const TERM = '<svg class="agent" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9l3 3-3 3M13 15h4"/></svg>';
const VIEWER = '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.3" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="2"/><path d="M10 2.5v11"/></svg>';
const NEWWS = '<svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.3" aria-hidden="true"><path d="M1.5 4.5v8h13v-7H8L6.5 3.5h-5z"/><path d="M8 7.5v4M6 9.5h4"/></svg>';
const FOLDER = '<svg class="kind" viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.3" aria-label="Workspace"><path d="M1.5 4.5v8h13v-7H8L6.5 3.5h-5z"/></svg>';
const TOGGLE = '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.3" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="2"/><path d="M6 2.5v11"/></svg>';

const MIN = 120, MAX = 400;
const ui = { rail: false, width: 200 };
let sb;
let stale = false;

export const dot = (status) => (status ? `<span class="dot" style="background:${status.color}" title="${status.label}"></span>` : "");

export function startSidebar() {
  Object.assign(ui, load("sidebar", {}, isObject));
  sb = document.getElementById("sidebar");
  render();
  bus.on("state:changed", ({ part }) => { if (part === "workspaces" || part === "registry") render(); });
  bus.on("config:changed", render);
  bus.handle("ws.prompt", newWorkspace);
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
  const button = (id, title, glyph) => `<button class="ib" id="${id}" title="${title}" aria-label="${title}">${glyph}</button>`;
  // The viewer button follows File viewer.
  const viewer = isOn("viewer") ? button("sbViewer", "Toggle File Viewer (Cmd+B)", VIEWER) : "";
  const newWs = button("wsNewTop", "New group (Cmd+Shift+T)", NEWWS);
  const top = ui.rail
    ? `<div class="sbtop">${button("sbToggle", label, TOGGLE)}${viewer}${button("sbNew", "New tab", "+")}</div>`
    : `<div class="sbtop">${button("sbToggle", label, TOGGLE)}${newWs}<span class="grow"></span>${viewer}${button("sbNew", "New tab", "+")}</div>`;
  const icon = (t) => (isAgentTab(t, reg) ? AGENT : TERM);
  if (ui.rail) {
    sb.innerHTML = top + s.wss.filter((w) => w.tabs.length).map((w) => w.tabs.map((id) => {
      const t = s.tabs[id];
      return `<div class="tab" role="tab" tabindex="0" aria-selected="${id === s.cur}" data-tabid="${id}" title="${esc(t.title)}">${icon(t)}${dot(tabStatus(t, reg))}</div>`;
    }).join("")).join('<div class="sep"></div>');
    return;
  }
  const key = (id) => { const i = order.indexOf(id); return i < 8 ? `⌘${i + 1}` : i === order.length - 1 ? "⌘9" : ""; };
  const wide = read("config")["tab-rows"] === "wide";
  // Rows of a group stand indented under its header; ungrouped rows have no header and no indent.
  const row = (w) => (id) => {
    const t = s.tabs[id], status = tabStatus(t, reg), cls = w.loose ? "tab loose" : "tab";
    const line = `<span class="t">${esc(t.title)}</span>${dot(status)}<span class="key">${key(id)}</span><button class="x" data-tabclose="${id}" aria-label="Close tab">✕</button>`;
    const attrs = `role="tab" tabindex="0" aria-selected="${id === s.cur}" data-tabid="${id}" title="${esc(t.cwd)}"`;
    if (!wide) return `<div class="${cls}" ${attrs}>${icon(t)}${line}</div>`;
    const l2 = `<div class="l2">${esc(detail(t, reg))}</div>`;
    return `<div class="${cls} wide" ${attrs}>${icon(t)}<div class="lines"><div class="l1">${line}</div>${l2}</div></div>`;
  };
  // Ungrouped blocks keep their workspace identity in a hidden header.
  const lists = s.wss.filter((w) => w.tabs.length);
  sb.innerHTML = top + lists.map((w) => {
    const n = w.tabs.length;
    const folded = w.collapsed ? `<span class="cnt">${n}</span>${dot(workspaceStatus(w, s.tabs, reg))}` : "";
    const head = w.loose ? `<div class="wsh flat" data-wsh="${w.id}" aria-hidden="true"></div>` : `<div class="wsh" data-wsh="${w.id}" draggable="true" role="button" tabindex="0" aria-expanded="${!w.collapsed}" title="${w.folder ? `${esc(w.folder)} · ` : ""}${n} tab${n === 1 ? "" : "s"}"><span class="chev">${w.collapsed ? "▸" : "▾"}</span>${w.folder ? FOLDER : ""}<span class="t">${esc(w.name)}</span>${folded}<button class="ib" data-wsnewtab="${w.id}" title="New tab in ${esc(w.name)}">+</button></div>`;
    return `<div class="wsblock${w.loose ? "" : " group"}" data-block="${w.id}">${head}${w.collapsed ? "" : w.tabs.map(row(w)).join("")}<div class="groupend"></div></div>`;
  }).join("") + '<button class="tab add" id="wsNew">+ New group</button>';
}

// The second line of a wide row: the folder and how long the agent is in its state. The icon
// already names the agent, and its title often does too.
function detail(tab, registry) {
  const session = terminals(tab.layout).map((t) => registry[t.pane]).find((x) => x && x.state !== "idle");
  const folder = tab.cwd.replace(/^\/Users\/[^/]+/, "~");
  if (!session) return folder;
  const minutes = Math.floor((clock.now() - session.since) / 60000);
  return `${folder} · ${minutes < 1 ? "now" : `${minutes}m`}`;
}

function setUi(patch) {
  Object.assign(ui, patch);
  save("sidebar", ui);
  render();
}

function onClick(e) {
  const hit = e.target.closest("[data-tabclose], [data-wsnewtab], .wsh[data-wsh], #wsNew, #wsNewTop, #sbViewer, #sbToggle, #sbNew, .tab[data-tabid]");
  if (!hit) return;
  const { dataset } = hit;
  if (dataset.tabclose) return bus.cmd("tab.close", { id: dataset.tabclose });
  if (dataset.wsnewtab) return bus.cmd("tab.new", { ws: dataset.wsnewtab, header: true });
  if (dataset.wsh) return bus.cmd("ws.fold", { id: dataset.wsh });
  if (hit.id === "wsNew" || hit.id === "wsNewTop") return newWorkspace();
  if (hit.id === "sbViewer") return bus.cmd("viewer.cmd", { name: "tree" });
  if (hit.id === "sbToggle") return setUi({ rail: !ui.rail });
  if (hit.id === "sbNew") return bus.cmd("tab.new");
  bus.cmd("tab.go", { id: dataset.tabid });
}

// A group takes a name; a workspace is a group with a project folder, named after it. The app
// shows the macOS folder panel; the browser has none, so the demo takes a typed path. A folder
// another workspace already has selects that workspace (docs/specs/workspace-folder.md Q1).
async function newWorkspace() {
  const form = document.createElement("div");
  form.className = "newgroup";
  form.innerHTML = `<label><input type="radio" name="kind" value="group" checked> Group <input id="ngName" placeholder="Name" aria-label="Group name"></label>
    <label><input type="radio" name="kind" value="workspace"> Workspace <input id="ngFolder" placeholder="~/code/project" aria-label="Project folder"></label>`;
  const pick = (kind) => { form.querySelector(`[value=${kind}]`).checked = true; };
  form.querySelector("#ngName").addEventListener("focus", () => pick("group"));
  form.querySelector("#ngFolder").addEventListener("focus", () => pick("workspace"));
  if (await ask("New group", ["Create", "Cancel"], form) !== "Create") return;
  const folderKind = form.querySelector("[value=workspace]").checked;
  const name = form.querySelector("#ngName").value.trim();
  const folder = form.querySelector("#ngFolder").value.trim().replace(/\/+$/, "");
  if (!folderKind) return bus.cmd("ws.new", { name: name || "Group" });
  if (!folder) return;
  const { wss } = read("workspaces"), open = wss.find((w) => w.folder === folder && w.tabs.length);
  if (open) return bus.cmd("tab.go", { id: open.tabs[0] });
  bus.cmd("ws.new", { name: folder.slice(folder.lastIndexOf("/") + 1) || folder, folder });
}

function renameWorkspace(id) {
  const ws = read("workspaces").wss.find((w) => w.id === id), name = prompt("Group name", ws.name)?.trim();
  if (name) bus.cmd("ws.rename", { id, name });
}

// Unchecked, the tabs stay as ungrouped tabs; checked, they close with the group.
async function deleteWorkspace(id) {
  const ws = read("workspaces").wss.find((w) => w.id === id), n = ws.tabs.length;
  const box = document.createElement("label");
  box.className = "closetabs";
  box.innerHTML = `<input type="checkbox" id="dgClose"> Also close its ${n} tab${n === 1 ? "" : "s"}`;
  if (await ask(`Delete group ${ws.name}?`, ["Delete", "Cancel"], box) !== "Delete") return;
  bus.cmd("ws.delete", { id, closeTabs: box.querySelector("input").checked });
}

function onContextMenu(e) {
  const row = e.target.closest(".tab[data-tabid]"), head = e.target.closest(".wsh[data-wsh]");
  if (!row && !head) return;
  e.preventDefault();
  const { wss } = read("workspaces");
  if (row) {
    const id = row.dataset.tabid, here = wss.find((w) => w.tabs.includes(id));
    const moves = [
      ...wss.filter((w) => w !== here && !w.loose && w.tabs.length).map((w) => ({ label: `Move to ${w.name}`, attrs: `data-mmove="${id}" data-to="${w.id}"`, run: () => bus.cmd("tab.move", { id, ws: w.id }) })),
      ...(here.loose ? [] : [{ label: "Remove from group", attrs: `data-mmove="${id}" data-to="loose"`, run: () => bus.cmd("tab.move", { id, ws: "loose", after: here.id }) }]),
    ];
    showMenu([...moves, { label: "Close tab", attrs: `data-tabclose="${id}"`, run: () => bus.cmd("tab.close", { id }) }], e);
  } else {
    const id = head.dataset.wsh;
    showMenu([
      { label: "New tab", attrs: `data-wsnewtab="${id}"`, run: () => bus.cmd("tab.new", { ws: id, header: true }) },
      { label: "Rename…", attrs: `data-wsren="${id}"`, run: () => renameWorkspace(id) },
      { label: "Delete group…", attrs: `data-wsdel="${id}"`, run: () => deleteWorkspace(id) },
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

// The edge strip resizes between MIN and MAX and stops there: only the toggle button folds the
// sidebar to the rail. In the rail the strip does nothing.
function dragEdge(e) {
  if (ui.rail) return;
  const grip = e.currentTarget, x0 = e.clientX, w0 = ui.width;
  e.preventDefault();
  grip.classList.add("drag");
  grip.setPointerCapture(e.pointerId);
  const move = (ev) => {
    ui.width = Math.round(Math.min(MAX, Math.max(MIN, w0 + ev.clientX - x0)));
    sb.style.width = `${ui.width}px`;
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
