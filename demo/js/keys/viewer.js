// Key rows of the viewer pane and the file-tree toggle (Help group "Viewer").
const row = (id, chords, text, cmd, payload, extra = {}) =>
  ({ id, chords, when: "viewer", group: "Viewer", src: "tarn", text, cmd, payload, ...extra });

export const viewerKeys = [
  // Cmd+B also reaches a terminal: with no viewer open it opens one with the tree.
  row("viewer.tree", ["Cmd+B"], "Show or hide the file tree", "viewer.cmd", { name: "tree" }, { when: "any" }),
  row("viewer.mode", ["Cmd+E"], "View or source", "viewer.cmd", { name: "mode" }),
  row("viewer.save", ["Cmd+S"], "Save the file", "viewer.cmd", { name: "save" }),
  row("viewer.split.right", ["Cmd+D"], "The file in a new viewer, right", "viewer.split", { dir: "right" }),
  row("viewer.split.down", ["Cmd+Shift+D"], "The file in a new viewer, below", "viewer.split", { dir: "down" }),
  row("viewer.close", ["Cmd+W"], "Close the file tab", "viewer.cmd", { name: "closeTab" }, { alt: ["Ctrl+Alt+W"] }),
];
