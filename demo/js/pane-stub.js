// Stand-in for term-pane.js until the terminal slice lands. Same shape:
// createPane(id, { cwd }) -> { id, el, focus(), screenText(), term: null, dispose() }.
import { bus } from "./bus.js";
import { hooks } from "./test-contract.js";

const panes = new Map();

export function createPane(id, { cwd }) {
  const el = document.createElement("div");
  el.className = "pane pane-stub";
  el.dataset.pane = id;
  el.tabIndex = 0;
  el.textContent = `pane ${id} (${cwd})`;
  el.addEventListener("focus", () => bus.emit("pane:focused", { pane: id }));

  const pane = {
    id,
    el,
    term: null,
    focus: () => el.focus(),
    screenText: () => el.textContent,
    dispose() {
      el.remove();
      panes.delete(id);
      bus.emit("pane:disposed", { pane: id });
    },
  };
  panes.set(id, pane);
  hooks.screen = (paneId) => panes.get(paneId).screenText();
  return pane;
}
