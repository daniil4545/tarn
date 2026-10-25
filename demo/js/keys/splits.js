// Key rows for splits, as Ghostty's default keybinds extended to viewer panes.
const group = "Splits";
const row = (id, chords, alt, text, cmd, payload, when = "any") => ({ id, chords, alt, when, group, text, cmd, payload });

const arrows = ["Left", "Right", "Up", "Down"];
const go = arrows.map((a) => row(`pane.go.${a}`, [`Cmd+Alt+${a}`], [`Ctrl+Alt+${a}`], `Focus the split ${a.toLowerCase()}`, "pane.go", { dir: a.toLowerCase() }));
const resize = arrows.map((a) => row(`pane.resize.${a}`, [`Ctrl+Cmd+${a}`], [`Ctrl+Alt+Shift+${a}`], `Resize the split ${a.toLowerCase()}`, "pane.resize", { dir: a.toLowerCase() }));

export const SPLIT_KEYS = [
  row("pane.split.right", ["Cmd+D"], ["Ctrl+Alt+D"], "Split right", "pane.split", { dir: "right" }, "terminal"),
  row("pane.split.down", ["Cmd+Shift+D"], ["Ctrl+Alt+Shift+D"], "Split down", "pane.split", { dir: "down" }, "terminal"),
  row("pane.prev", ["Cmd+["], ["Ctrl+Alt+["], "Previous split", "pane.step", { delta: -1 }),
  row("pane.next", ["Cmd+]"], ["Ctrl+Alt+]"], "Next split", "pane.step", { delta: 1 }),
  ...go,
  ...resize,
  row("pane.equalize", ["Ctrl+Cmd+="], ["Ctrl+Alt+Shift+="], "Equalize splits", "pane.equalize"),
  row("pane.zoom", ["Cmd+Shift+Enter"], ["Ctrl+Alt+Shift+Enter"], "Zoom the split", "pane.zoom"),
];
