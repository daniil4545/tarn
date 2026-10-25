// Boot: stores first, then views. Modules of later slices are added here as they land.
import { bus } from "./bus.js";
import { register } from "./state.js";
import { startConfig } from "./config.js";
import { startRegistry } from "./registry.js";
import { WORKSPACES } from "./seed.js";
import { clock } from "./clock.js";
import { installKeys, lockKeysInFullscreen } from "./keymap.js";
import { installTestContract } from "./test-contract.js";
import { createPane } from "./pane-stub.js";
import { toast } from "./toast.js";

let focused = null;
bus.on("pane:focused", ({ pane }) => { focused = pane; });

// workspace.js takes over this part when it lands.
register("workspaces", WORKSPACES);
startConfig();
startRegistry({ now: clock.now, isFocused: (pane) => pane === focused });
installKeys([], { focus: () => "terminal" });
lockKeysInFullscreen();
bus.on("toast", ({ text }) => toast(text));
installTestContract();

const host = document.getElementById("main");
for (const tab of Object.values(WORKSPACES.tabs)) {
  const pane = createPane(tab.layout.pane, { cwd: tab.cwd });
  pane.el.hidden = tab.id !== WORKSPACES.cur;
  host.append(pane.el);
}
document.documentElement.dataset.ready = "true";
