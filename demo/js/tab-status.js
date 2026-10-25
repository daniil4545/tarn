// Agent status of a tab or a workspace, read from the registry. Order follows the jump order of
// docs/spec.md section 8; "waiting" and not seen is shown as "done, not seen".
import { terminals } from "./layout.js";

const KINDS = {
  failed: { rank: 4, color: "var(--deny)", label: "Failed" },
  permission: { rank: 3, color: "var(--orange)", label: "Needs permission" },
  done: { rank: 2, color: "var(--green)", label: "Done, not seen" },
  working: { rank: 1, color: "var(--blue)", label: "Working" },
};

function kindOf(session) {
  if (!session) return null;
  if (session.state === "waiting" && session.failed) return "failed";
  if (session.state === "permission") return "permission";
  if (session.state === "waiting" && !session.seen) return "done";
  return session.state === "working" ? "working" : null;
}

const best = (kinds) => kinds.filter(Boolean).sort((a, b) => KINDS[b].rank - KINDS[a].rank)[0] ?? null;

// The most urgent status of the sessions in a tab: {kind, session, pane, ...KINDS[kind]} or null.
export function tabStatus(tab, registry) {
  const found = terminals(tab.layout).map((t) => ({ pane: t.pane, session: registry[t.pane], kind: kindOf(registry[t.pane]) }));
  const kind = best(found.map((f) => f.kind));
  return kind && { ...found.find((f) => f.kind === kind), ...KINDS[kind] };
}

// A tab is an agent tab while a terminal of it has a session that is not idle.
export const isAgentTab = (tab, registry) => terminals(tab.layout).some((t) => registry[t.pane] && registry[t.pane].state !== "idle");

export function workspaceStatus(ws, tabs, registry) {
  const all = ws.tabs.map((id) => tabStatus(tabs[id], registry));
  const kind = best(all.map((s) => s?.kind));
  return kind && all.find((s) => s?.kind === kind);
}
