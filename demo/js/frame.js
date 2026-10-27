// The window: title bar, sidebar slot, top tab bar slot and the tab area. Applies the window
// options of config (titlebar style, tab style, drag handle, unfocused opacity).
import { bus } from "./bus.js";
import { read } from "./state.js";
import { currentTab } from "./workspace.js";
import { isOn } from "./modules.js";

const LIGHTS = ["#ff5f57", "#febc2e", "#28c840"].map((c) => `<i style="background:${c}"></i>`).join("");

// Demo only: the app opens Settings by Cmd+, and the menu.
const GEAR = '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.3" aria-hidden="true"><circle cx="8" cy="8" r="2.2"/><path d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M3.4 12.6l1.4-1.4M11.2 4.8l1.4-1.4"/></svg>';

const HTML = `
<div class="titlebar"><span class="lights">${LIGHTS}</span><span class="ttl"></span><span class="sub"></span><span id="titlebar-actions"><button class="ib" id="tbSettings" title="Settings (Cmd+,)" aria-label="Settings (Cmd+,)">${GEAR}</button></span></div>
<div class="body">
  <nav class="sidebar" id="sidebar" aria-label="Tabs"></nav>
  <div class="sbgrip" id="sbGrip" aria-hidden="true"></div>
  <div class="wscol">
    <div class="toptabs" id="topTabs" role="tablist" aria-label="Tabs"></div>
    <main class="ws" id="ws"></main>
  </div>
</div>`;

export function mountFrame(root) {
  root.classList.add("win");
  root.innerHTML = HTML;
  apply();
  showTitle();
  root.querySelector("#tbSettings").addEventListener("click", () => bus.cmd("settings.open"));
  bus.on("config:changed", () => { apply(); showTitle(); });
  bus.on("state:changed", ({ part }) => { if (part === "workspaces") showTitle(); });
  bus.handle("window.fullscreen", () => (document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen()));
}

function apply() {
  const config = read("config"), win = document.getElementById("main"), ws = win.querySelector("#ws");
  win.classList.toggle("top", config["tab-style"] === "top");
  win.className = win.className.replace(/\btb-\S+/g, "").trim();
  win.classList.add(`tb-${config["macos-titlebar-style"]}`);
  ws.className = `ws h-${config["drag-handle"]}`;
  win.style.setProperty("--unfocused", config["unfocused-split-opacity"]);
}

// Ghostty's title of the focused terminal, with the workspace name as the subtitle.
function showTitle() {
  const s = read("workspaces"), tab = currentTab(s);
  const ws = tab && s.wss.find((w) => w.tabs.includes(tab.id));
  const [title, sub] = tab ? [tab.title, isOn("workspaces") ? ws.name : ""] : ["tarn", ""];
  document.querySelector(".titlebar .ttl").textContent = title;
  document.querySelector(".titlebar .sub").textContent = sub;
  document.title = sub ? `${title} · ${sub}` : title;
}
