// Boots slice B alone: stub terminals and a stub viewer that takes files by drag.
import { bus } from "../js/bus.js";
import { startConfig } from "../js/config.js";
import { startRegistry } from "../js/registry.js";
import { clock } from "../js/clock.js";
import { installKeys } from "../js/keymap.js";
import { installTestContract } from "../js/test-contract.js";
import { createPane } from "../js/pane-stub.js";
import { startWorkspaces, focusArea } from "../js/workspace.js";
import { startChrome } from "../js/chrome.js";
import { TAB_KEYS } from "../js/keys/tabs.js";
import { SPLIT_KEYS } from "../js/keys/splits.js";
import { FIND_KEYS } from "../js/keys/find.js";
import { toast } from "../js/toast.js";
import { createViewer, startViewerStub } from "./b-viewer.js";

let focused = null;
bus.on("pane:focused", ({ pane }) => { focused = pane; });
const ROWS = [...TAB_KEYS, ...SPLIT_KEYS, ...FIND_KEYS];

startConfig();
startRegistry({ now: clock.now, isFocused: (pane) => pane === focused });
startWorkspaces({ createPane, createViewer });
startViewerStub();
startChrome(document.getElementById("main"), ROWS);
installKeys(ROWS, { focus: focusArea });
bus.on("toast", ({ text }) => toast(text));
installTestContract();
document.documentElement.dataset.ready = "true";
