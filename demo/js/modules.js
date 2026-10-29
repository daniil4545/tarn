// The five modules of Settings > Modules and their effective state. Counterpart of TarnModule and
// TarnModules in TarnSettings.swift. Storage stays in `config`: the Sidebar switch is `tab-style`
// (on = sidebar, off = top), File viewer is `file-viewer`, the others have a key of their own.
// A module whose needed module is off keeps its stored value and behaves as off.
import { read } from "./state.js";

export const MODULES = [
  { id: "sidebar", title: "Sidebar", detail: "Tabs in workspaces with agent state, on the left. Off: the native tab bar at the top.", needs: null },
  { id: "viewer", title: "File viewer", detail: "Cmd+B, path clicks and agents open files in a pane beside the terminal. When off, path clicks open files in their default app; open panes are hidden and come back when you switch it on.", key: "file-viewer", needs: null },
  { id: "permissionCard", title: "Permission card", detail: "Allow or deny from the sidebar card.", key: "module-permission-card", needs: "sidebar" },
  { id: "notifications", title: "Notifications", detail: "A banner when an agent needs you; Cmd+U jumps to it.", key: "module-notifications", needs: null },
];

const find = (id) => MODULES.find((m) => m.id === id);

// The switch as the user left it, whatever the needed module says.
export function stored(id, config = read("config")) {
  return id === "sidebar" ? config["tab-style"] === "sidebar" : config[find(id).key];
}

// The state the UI follows: stored on and the needed module effectively on.
export function isOn(id, config = read("config")) {
  const { needs } = find(id);
  return stored(id, config) && (needs === null || isOn(needs, config));
}
