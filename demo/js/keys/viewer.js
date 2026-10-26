// Key rows of the viewer pane and the file-tree toggle (Help group "Viewer").
const row = (id, chords, text, cmd, payload, extra = {}) =>
  ({ id, chords, when: "viewer", group: "Viewer", src: "tarn", text, cmd, payload, ...extra });

export const viewerKeys = [
  // Cmd+B also works from a terminal; what it does depends on the pane (viewer-keys.js).
  row("viewer.tree", ["Cmd+B"], "Toggle Pane: open, hide or show the viewer", "viewer.cmd", { name: "tree" }, { when: "any", alt: ["Ctrl+Alt+B"] }),
  row("viewer.mode", ["Cmd+E"], "View or source", "viewer.cmd", { name: "mode" }),
  row("viewer.save", ["Cmd+S"], "Save the file", "viewer.cmd", { name: "save" }),
  row("viewer.split.right", ["Cmd+D"], "The file in a new viewer, right", "viewer.split", { dir: "right" }),
  row("viewer.split.down", ["Cmd+Shift+D"], "The file in a new viewer, below", "viewer.split", { dir: "down" }),
  row("viewer.close", ["Cmd+W"], "Close the file tab", "viewer.cmd", { name: "closeTab" }, { alt: ["Ctrl+Alt+W"] }),
  // Ghostty's Find items of the menu, aimed at the page while it has the keyboard.
  row("viewer.find", ["Cmd+F"], "Find in the file", "viewer.cmd", { name: "find", arg: "open" }, { alt: ["Ctrl+Alt+F"] }),
  row("viewer.find.next", ["Cmd+G"], "Find next", "viewer.cmd", { name: "find", arg: "next" }, { alt: ["Ctrl+Alt+G"] }),
  row("viewer.find.prev", ["Cmd+Shift+G"], "Find previous", "viewer.cmd", { name: "find", arg: "prev" }, { alt: ["Ctrl+Alt+Shift+G"] }),
];
