// Agent sessions as `tarn ls` lists them: one row per tab that has a registry record.
// Pure over the `workspaces` and `registry` snapshots and the vfs (for the branch).

// Pane ids in a layout tree; the tree shape belongs to workspace.js, a leaf carries `pane`.
function panesOf(node) {
  if (!node || typeof node !== "object") return [];
  return [...(node.pane ? [node.pane] : []), ...Object.values(node).flatMap(panesOf)];
}

export function sessionRows({ workspaces, registry, vfs, home, now }) {
  const rows = [];
  let n = 0;
  for (const ws of workspaces.wss) {
    for (const id of ws.tabs) {
      n++;
      const tab = workspaces.tabs[id];
      const pane = panesOf(tab.layout).find((p) => registry[p]);
      if (!pane) continue;
      const session = registry[pane];
      const cwd = tab.cwd.startsWith("~") ? home + tab.cwd.slice(1) : tab.cwd;
      rows.push({
        tab: n,
        pane,
        project: cwd.slice(cwd.lastIndexOf("/") + 1),
        branch: vfs.gitBranch(cwd) ?? "-",
        state: session.state,
        since: new Date(session.since).toISOString(),
        age: age(now() - session.since),
        seen: session.seen,
        failed: session.failed,
        request: session.request,
      });
    }
  }
  return rows;
}

function age(ms) {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 60) return `${s}s`;
  return s < 3600 ? `${Math.floor(s / 60)}m` : `${Math.floor(s / 3600)}h`;
}
