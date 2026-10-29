// Boot: stores first, then views. Every module starts here, in dependency order.
import { bus } from "./bus.js";
import { startConfig } from "./config.js";
import { startRegistry } from "./registry.js";
import { clock } from "./clock.js";
import { installKeys, lockKeysInFullscreen } from "./keymap.js";
import { installTestContract } from "./test-contract.js";
import { startVfs } from "./vfs.js";
import { HOME, REPO } from "./vfs-seed.js";
import { createPane, startPanes, panesReady } from "./term-pane.js";
import { startViewer, createViewerPane } from "./viewer.js";
import { startWorkspaces, focusArea } from "./workspace.js";
import { startChrome } from "./chrome.js";
import { startSettings, settingsOpen } from "./settings.js";
import { startEffects } from "./settings-effects.js";
import { TAB_KEYS } from "./keys/tabs.js";
import { SPLIT_KEYS } from "./keys/splits.js";
import { FIND_KEYS } from "./keys/find.js";
import { TERMINAL_KEYS } from "./keys/terminal.js";
import { viewerKeys } from "./keys/viewer.js";
import { helpKeys } from "./keys/help.js";
import { startDemoReset, RESET_ROW } from "./demo-reset.js";
import { startAttention } from "./attention.js";
import { toast } from "./toast.js";

let focused = null;
bus.on("pane:focused", ({ pane }) => { focused = pane; });

const ROWS = [...TAB_KEYS, ...SPLIT_KEYS, ...FIND_KEYS, ...TERMINAL_KEYS, ...viewerKeys, ...helpKeys];

bus.on("toast", ({ text }) => toast(text)); // first: boot code may report a failed load
startConfig();
startEffects();
startRegistry({ now: clock.now, isFocused: (pane) => pane === focused });
const vfs = startVfs();
startPanes({ vfs });
startViewer({ fs: vfs, home: HOME, root: REPO });
startWorkspaces({ createPane, createViewer: createViewerPane });
startAttention();
startDemoReset();
startChrome(document.getElementById("main"), [...ROWS, RESET_ROW]);
startSettings(ROWS);
installKeys(ROWS, { focus: () => (settingsOpen() ? "modal" : focusArea()) });
lockKeysInFullscreen();
installTestContract();
await panesReady();
document.documentElement.dataset.ready = "true";
