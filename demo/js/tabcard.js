// Tab card: hover an agent row for 0.5 s and a card opens to its right; while it is open it moves
// at once to the next agent row and stays while the pointer is on it. Counterpart of TabCardPopover.swift.
import { bus } from "./bus.js";
import { read } from "./state.js";
import { clock } from "./clock.js";
import { AGENT, dot } from "./sidebar.js";
import { tabStatus, isAgentTab } from "./tab-status.js";
import { esc } from "./esc.js";

const OPEN_AFTER = 500, CLOSE_AFTER = 200;
let shown = null;
let openTimer = 0;
let closeTimer = 0;


// Same text as the app card: "Tool: detail" for a tool request, the detail alone for a question.
const requestText = (r) => (r.kind === "tool" ? `${r.tool}: ${r.detail}` : r.detail);

function elapsed(since) {
  const s = Math.max(0, Math.floor((clock.now() - since) / 1000));
  return s < 60 ? `${s}s` : s < 3600 ? `${Math.floor(s / 60)}m` : `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
}

function show(id) {
  const s = read("workspaces"), tab = s.tabs[id], row = document.querySelector(`#sidebar .tab[data-tabid="${id}"]`);
  if (!tab || !row) return hide();
  const status = tabStatus(tab, read("registry")), session = status?.session;
  const ask = status?.kind === "permission" && session.answerable && session.request
    ? `<div class="req"><code>${esc(requestText(session.request))}</code><div class="btns"><button data-answer="${status.pane}" data-allow="true">Allow</button><button data-answer="${status.pane}" data-allow="false">Deny</button></div></div>`
    : "";
  let card = document.getElementById("tabcard");
  if (!card) {
    card = Object.assign(document.createElement("div"), { id: "tabcard", className: "card" });
    document.body.append(card);
  }
  const ws = s.wss.find((w) => w.tabs.includes(id));
  card.innerHTML = `<b>${esc(tab.title)}</b><div class="dim">${esc(ws.name)}</div><div class="dim mono"><bdi>${esc(tab.cwd)}</bdi></div><div class="st">${AGENT}${dot(status)}<span>${status ? status.label : "No activity"}</span>${status ? `<span class="dim">${elapsed(session.since)}</span>` : ""}</div>${ask}`;
  const r = row.getBoundingClientRect();
  card.style.left = `${r.right + 8}px`;
  card.style.top = `${Math.max(8, Math.min(r.top - 6, innerHeight - card.offsetHeight - 8))}px`;
  shown = id;
}

function hide() {
  clearTimeout(openTimer);
  shown = null;
  document.getElementById("tabcard")?.remove();
}

export function startTabCard() {
  document.addEventListener("mouseover", (e) => {
    if (document.body.classList.contains("dragging")) return;
    if (e.target.closest("#tabcard")) return clearTimeout(closeTimer);
    const row = e.target.closest("#sidebar .tab[data-tabid]");
    if (!row || !isAgentTab(read("workspaces").tabs[row.dataset.tabid], read("registry"))) return;
    const id = row.dataset.tabid;
    clearTimeout(closeTimer);
    clearTimeout(openTimer);
    if (shown && shown !== id) show(id);
    else if (!shown) openTimer = setTimeout(() => show(id), OPEN_AFTER);
  });
  document.addEventListener("mouseout", (e) => {
    const from = e.target.closest("#sidebar .tab[data-tabid], #tabcard");
    if (!from || from.contains(e.relatedTarget)) return;
    clearTimeout(openTimer);
    closeTimer = setTimeout(hide, CLOSE_AFTER);
  });
  document.addEventListener("click", (e) => {
    const button = e.target.closest("[data-answer]");
    if (!button) return;
    const allow = button.dataset.allow === "true";
    bus.cmd("card.answer", { pane: button.dataset.answer, allow });
    bus.emit("toast", { text: `${allow ? "Allow" : "Deny"}: answer sent to the agent` });
    hide();
  });
  document.addEventListener("dragstart", hide, true);
  bus.on("config:changed", hide);
  bus.on("state:changed", ({ part }) => { if (shown && part === "registry") show(shown); });
}
