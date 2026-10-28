// Tab style "top": Ghostty's native tab bar of the window's tabs. Each tab reads its title, then its workspace
// name (Workspaces on and the tab in a group, our tab mark), then the agent state dot. Close on hover at the left, goto_tab key at the right.
import { bus } from "./bus.js";
import { read } from "./state.js";
import { flatTabs } from "./workspace.js";
import { esc } from "./esc.js";
import { dot } from "./sidebar.js";
import { tabStatus } from "./tab-status.js";
import { isOn } from "./modules.js";


export function startTopTabs() {
  const bar = document.getElementById("topTabs");
  render(bar);
  bus.on("state:changed", ({ part }) => { if (part === "workspaces" || part === "registry") render(bar); });
  bus.on("config:changed", () => render(bar));
  bar.addEventListener("click", (e) => {
    const close = e.target.closest("[data-tabclose]"), tab = e.target.closest("[data-toptab]");
    if (close) return bus.cmd("tab.close", { id: close.dataset.tabclose });
    if (tab) return bus.cmd("tab.go", { id: tab.dataset.toptab });
    if (e.target.closest("#topNew")) bus.cmd("tab.new");
  });
}

function render(bar) {
  const s = read("workspaces"), reg = read("registry"), order = flatTabs(s), grouped = isOn("workspaces");
  const key = (i) => (i < 8 ? `⌘${i + 1}` : i === order.length - 1 ? "⌘9" : "");
  bar.innerHTML = order.map((id, i) => {
    const t = s.tabs[id];
    const ws = s.wss.find((w) => w.tabs.includes(id));
    const mark = grouped && !ws.loose ? `<span class="tw">${esc(ws.name)}</span>` : "";
    return `<div class="ttab" role="tab" aria-selected="${id === s.cur}" data-toptab="${id}" title="${esc(t.cwd)}"><button class="tx" data-tabclose="${id}" aria-label="Close tab">✕</button><span class="tt">${esc(t.title)}</span>${mark}${dot(tabStatus(t, reg))}<span class="tk">${key(i)}</span></div>`;
  }).join("") + '<button class="tplus" id="topNew" aria-label="New tab" title="New tab">+</button>';
}
