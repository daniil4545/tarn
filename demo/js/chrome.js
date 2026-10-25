// Starts the views of the window once the stores exist: frame, layouts, sidebar, top tabs, card,
// drop zones, find and palette. `rows` are all key rows, for the palette.
import { mountFrame } from "./frame.js";
import { startView } from "./view.js";
import { startSidebar } from "./sidebar.js";
import { startSidebarDrag } from "./sidebar-drag.js";
import { startTopTabs } from "./tabs.js";
import { startTabCard } from "./tabcard.js";
import { startDnd } from "./dnd.js";
import { startFind } from "./find.js";
import { startPalette } from "./palette.js";

export function startChrome(root, rows) {
  mountFrame(root);
  startView();
  startSidebarDrag();
  startSidebar();
  startTopTabs();
  startTabCard();
  startDnd();
  startFind();
  startPalette(rows);
}
