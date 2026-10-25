// Boot: stores first, then views. Modules of later slices are added here as they land.
import { bus } from "./bus.js";
import { startConfig } from "./config.js";
import { startRegistry } from "./registry.js";
import { clock } from "./clock.js";
import { installKeys, lockKeysInFullscreen } from "./keymap.js";
import { installTestContract } from "./test-contract.js";
import { createPane } from "./pane-stub.js";
import { createViewerPane } from "./viewer.js";
import { startWorkspaces, focusArea } from "./workspace.js";
import { startChrome } from "./chrome.js";
import { TAB_KEYS } from "./keys/tabs.js";
import { SPLIT_KEYS } from "./keys/splits.js";
import { FIND_KEYS } from "./keys/find.js";
import { toast } from "./toast.js";

let focused = null;
bus.on("pane:focused", ({ pane }) => { focused = pane; });

const ROWS = [...TAB_KEYS, ...SPLIT_KEYS, ...FIND_KEYS];

startConfig();
startRegistry({ now: clock.now, isFocused: (pane) => pane === focused });
startWorkspaces({ createPane, createViewer: createViewerPane });
startChrome(document.getElementById("main"), ROWS);
installKeys(ROWS, { focus: focusArea });
lockKeysInFullscreen();
bus.on("toast", ({ text }) => toast(text));
installTestContract();
document.documentElement.dataset.ready = "true";
