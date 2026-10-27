// Attention: a banner when an agent starts to need the user, and Cmd+U to jump to the most
// urgent waiting session. Counterpart of Attention.swift (banner, AttentionJump). The Notifications
// module off: no banner, Cmd+U does nothing.
import { bus } from "./bus.js";
import { read } from "./state.js";
import { flatTabs, currentTab } from "./workspace.js";
import { tabStatus } from "./tab-status.js";
import { isOn } from "./modules.js";
import { esc } from "./esc.js";

const SHOW_FOR = 4000;
let timer = 0;

function banner(title, text) {
  let el = document.getElementById("banner");
  if (!el) {
    el = Object.assign(document.createElement("div"), { id: "banner", className: "banner", role: "status" });
    document.body.append(el);
  }
  el.innerHTML = `<b>${esc(title)}</b><span>${esc(text)}</span>`;
  clearTimeout(timer);
  timer = setTimeout(() => el.remove(), SHOW_FOR);
}

const needs = (session) => session && (session.state === "permission" || (session.state === "waiting" && !session.seen));

function jump() {
  if (!isOn("notifications")) return;
  const s = read("workspaces"), reg = read("registry");
  const waiting = flatTabs(s)
    .map((id) => ({ id, status: tabStatus(s.tabs[id], reg) }))
    .filter((t) => t.status && t.status.kind !== "working" && t.id !== currentTab(s)?.id)
    .sort((a, b) => b.status.rank - a.status.rank);
  if (!waiting.length) return bus.emit("toast", { text: "No session is waiting" });
  bus.cmd("tab.go", { id: waiting[0].id });
  bus.cmd("pane.focus", { id: waiting[0].status.pane });
}

export function startAttention() {
  let before = read("registry");
  bus.on("state:changed", ({ part }) => {
    if (part !== "registry") return;
    const after = read("registry");
    if (isOn("notifications")) {
      for (const [pane, session] of Object.entries(after)) {
        if (!needs(session) || needs(before[pane])) continue;
        const tab = Object.values(read("workspaces").tabs).find((t) => JSON.stringify(t.layout).includes(`"${pane}"`));
        banner("Claude Code needs you", `${tab?.title ?? "A session"}: ${session.state === "permission" ? "permission request" : "done"}`);
      }
    }
    before = after;
  });
  bus.handle("attention.jump", jump);
}
