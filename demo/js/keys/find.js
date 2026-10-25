// Key rows for find and the command palette.
const group = "Terminal";
const row = (id, chords, alt, text, cmd, when) => ({ id, chords, alt, when, group, text, cmd });

export const FIND_KEYS = [
  row("find.open", ["Cmd+F"], ["Ctrl+Alt+F"], "Find", "find.open", "terminal"),
  row("find.next", ["Cmd+G"], ["Ctrl+Alt+G"], "Find next", "find.next", "terminal"),
  row("find.prev", ["Cmd+Shift+G"], ["Ctrl+Alt+Shift+G"], "Find previous", "find.prev", "terminal"),
  row("palette.open", ["Cmd+Shift+P"], ["Ctrl+Alt+Shift+P"], "Command palette", "palette.open", "any"),
];
