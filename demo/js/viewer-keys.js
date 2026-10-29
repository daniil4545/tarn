// Cmd+B as ViewerHost.toggleFromKey: opens a pane with the tree, shows a hidden one, toggles the
// tree when files are open, closes a pane with no file. `host` is viewer.js: { target(), idOf(entry) }.
import { bus } from "./bus.js";
import { toast } from "./toast.js";
import * as tree from "./layout.js";
import { currentTab, paneOf } from "./workspace.js";

const hiddenCount = () => (currentTab()?.hidden ?? []).length;

function toTerminal() {
  const tab = currentTab();
  if (!tab) return;
  const terminals = tree.terminals(tab.layout);
  paneOf((terminals.find((t) => t.pane === tab.focus) ?? terminals[0]).pane)?.focus();
}

// A frame that was just created or moved has no `tarn` until its page says ready: run `fn` when it does.
function whenReady(entry, fn, tries = 120) {
  const page = entry.frame.contentWindow;
  if (page?.tarn?.focusTree) return fn(page.tarn);
  if (tries > 0) requestAnimationFrame(() => whenReady(entry, fn, tries - 1));
  return undefined;
}

// After a hidden pane returned the frame reloads: wait for the entry to be on screen again.
function whenShown(host, fn, tries = 120) {
  const entry = host.target();
  if (entry) return fn(entry);
  if (tries > 0) requestAnimationFrame(() => whenShown(host, fn, tries - 1));
  return undefined;
}

// The keyboard goes into the frame; say so, because a frame that already had the focus sends no event.
function intoPane(host, entry) {
  entry.frame.contentWindow.focus();
  bus.emit("pane:focused", { pane: host.idOf(entry) });
}

export function viewerKey(name, host) {
  if (!bus.cmd("viewer.available")) return toast("File viewer is off (Settings)");
  const entry = host.target();
  if (!entry && hiddenCount()) {
    bus.cmd("viewer.show");
    return whenShown(host, (shown) => whenReady(shown, () => intoPane(host, shown)));
  }
  if (!entry) {
    bus.emit("viewer:needed", { tree: true });
    const opened = host.target();
    if (opened) whenReady(opened, (page) => { intoPane(host, opened); page.focusTree(); });
    return undefined;
  }
  if (entry.model.state().tabs.length) return entry.model.toggleTree();
  entry.model.closeActiveTab();
  return toTerminal();
}
