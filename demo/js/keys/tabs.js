// Key rows for tabs and windows. `alt` is the Ctrl+Alt fallback for browsers that keep the chord.
const group = "Tabs and windows";
const row = (id, chords, alt, text, cmd, payload, when = "any") => ({ id, chords, alt, when, group, text, cmd, payload });

const digits = Array.from({ length: 8 }, (_, i) => row(`tab.go.${i + 1}`, [`Cmd+${i + 1}`], [`Ctrl+Alt+${i + 1}`], `Go to tab ${i + 1} down the sidebar`, "tab.go", { n: i + 1 }));

export const TAB_KEYS = [
  row("tab.new", ["Cmd+T"], ["Ctrl+Alt+T"], "New tab in the current workspace", "tab.new"),
  row("ws.new", ["Cmd+Shift+T"], ["Ctrl+Alt+Shift+T"], "New workspace with one new tab", "ws.prompt"),
  row("window.new", ["Cmd+N"], ["Ctrl+Alt+N"], "New window with No project", "window.new"),
  row("pane.close", ["Cmd+W"], ["Ctrl+Alt+W"], "Close the pane; the last one closes the tab", "pane.close", undefined, "terminal"),
  // Ctrl+Alt+W is taken by pane.close, so this chord (it has Alt already) has no fallback.
  row("tab.close", ["Cmd+Alt+W"], [], "Close the tab", "tab.close"),
  row("window.close", ["Cmd+Shift+W"], ["Ctrl+Alt+Shift+W"], "Close the window", "window.close"),
  row("pane.undo", ["Cmd+Z"], ["Ctrl+Alt+Z"], "Bring back what was closed (5 s)", "pane.undo", undefined, "terminal"),
  row("attention.jump", ["Cmd+U"], ["Ctrl+Alt+U"], "Jump to the session that waits for you", "attention.jump"),
  ...digits,
  row("tab.go.9", ["Cmd+9"], ["Ctrl+Alt+9"], "Go to the last tab", "tab.go", { n: 9 }),
  row("tab.prev", ["Cmd+Shift+["], ["Ctrl+Alt+Shift+["], "Previous tab", "tab.step", { delta: -1 }),
  row("tab.next", ["Cmd+Shift+]"], ["Ctrl+Alt+Shift+]"], "Next tab", "tab.step", { delta: 1 }),
  row("window.fullscreen", ["Cmd+Enter"], ["Ctrl+Alt+Enter"], "Full screen", "window.fullscreen"),
];
