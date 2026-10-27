// Terminal panes as `tarn ls` lists them (docs/specs/agent-cli.md 4.1): every pane of the caller's
// workspace. Pure over the `workspaces` and `registry` snapshots and the vfs (for the branch).

// Pane ids in a layout tree; the tree shape belongs to workspace.js, a leaf carries `pane`.
function panesOf(node) {
  if (!node || typeof node !== "object") return [];
  return [...(node.pane ? [node.pane] : []), ...Object.values(node).flatMap(panesOf)];
}

// `host` stays empty until SSH sessions (#39); `state` is empty for a pane without a session.
export function paneRows({ workspaces, registry, vfs, home, caller }) {
  const ws = workspaces.wss.find((w) => w.tabs.some((id) => panesOf(workspaces.tabs[id].layout).includes(caller)));
  if (!ws) return [];
  return ws.tabs.flatMap((id) => {
    const tab = workspaces.tabs[id];
    const cwd = tab.cwd.startsWith("~") ? home + tab.cwd.slice(1) : tab.cwd;
    return panesOf(tab.layout).map((pane) => ({
      pane,
      tab: id,
      workspace: ws.id,
      title: tab.title,
      cwd,
      process: registry[pane] ? "claude" : "zsh",
      branch: vfs.gitBranch(cwd) ?? "",
      host: "",
      state: registry[pane]?.state ?? "",
    }));
  });
}
