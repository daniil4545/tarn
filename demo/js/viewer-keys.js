// Cmd+B of the app (View menu "Toggle Pane"), by the state of the pane. Counterpart of
// ViewerHost.swift. It never closes (Cmd+W does) and never toggles the tree (the Files button and Esc do).
//   no pane      opens the pane with the tree, the keyboard in the tree
//   pane hidden  shows it as it was hidden, the keyboard in the pane
//   pane shown   hides the whole pane (tabs, unsaved text, tree state kept), the keyboard in the terminal
// `host` is viewer.js: { target(), idOf(entry) }.
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
  const entry = host.target();
  if (!entry && hiddenCount()) {
    bus.cmd("viewer.show");
    return whenShown(host, (shown) => whenReady(shown, () => intoPane(host, shown)));
  }
  if (!entry) {
    if (!bus.cmd("viewer.available")) return toast("File viewer is off (Settings)");
    bus.emit("viewer:needed", { tree: true });
    const opened = host.target();
    if (opened) whenReady(opened, (page) => { intoPane(host, opened); page.focusTree(); });
    return undefined;
  }
  entry.frame.contentWindow?.tarn?.flush?.(); // the page holds an edit back for a moment: send it before it leaves
  bus.cmd("viewer.hide", { id: host.idOf(entry) });
  return toTerminal();
}
