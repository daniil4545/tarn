// Tab style "top": Ghostty's native tab bar of the window's tabs. No agent state here; the
// sidebar keeps it. With two or more workspaces a title starts with its workspace, dimmed
// (docs/specs/workspace-folder.md D25). Close on hover at the left, title centred, goto_tab key at the right.
import { bus } from "./bus.js";
import { read } from "./state.js";
import { flatTabs } from "./workspace.js";
import { esc } from "./esc.js";


export function startTopTabs() {
  const bar = document.getElementById("topTabs");
  render(bar);
  bus.on("state:changed", ({ part }) => { if (part === "workspaces") render(bar); });
  bar.addEventListener("click", (e) => {
    const close = e.target.closest("[data-tabclose]"), tab = e.target.closest("[data-toptab]");
    if (close) return bus.cmd("tab.close", { id: close.dataset.tabclose });
    if (tab) return bus.cmd("tab.go", { id: tab.dataset.toptab });
    if (e.target.closest("#topNew")) bus.cmd("tab.new");
  });
}

function render(bar) {
  const s = read("workspaces"), order = flatTabs(s);
  const key = (i) => (i < 8 ? `⌘${i + 1}` : i === order.length - 1 ? "⌘9" : "");
  const prefix = (id) => {
    if (s.wss.length < 2) return "";
    const ws = s.wss.find((w) => w.tabs.includes(id));
    return ws ? `<span class="tw">${esc(ws.name)} · </span>` : "";
  };
  bar.innerHTML = order.map((id, i) => {
    const t = s.tabs[id];
    return `<div class="ttab" role="tab" aria-selected="${id === s.cur}" data-toptab="${id}" title="${esc(t.cwd)}"><button class="tx" data-tabclose="${id}" aria-label="Close tab">✕</button><span class="tt">${prefix(id)}${esc(t.title)}</span><span class="tk">${key(i)}</span></div>`;
  }).join("") + '<button class="tplus" id="topNew" aria-label="New tab" title="New tab">+</button>';
}
