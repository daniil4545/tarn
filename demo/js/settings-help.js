// The Help table, built from the key rows (keys/*.js): one source, so a row added to the keymap
// shows up here with its fallback chord.
const SYMBOLS = { Ctrl: "⌃", Alt: "⌥", Shift: "⇧", Cmd: "⌘" };
const MODS = Object.keys(SYMBOLS);
const KEYS = { Enter: "↩", Up: "↑", Down: "↓", Left: "←", Right: "→", Escape: "⎋", Backspace: "⌫", Tab: "⇥" };
const FIRST_GROUPS = ["Tabs and windows", "Splits", "Terminal", "Viewer"];

// "Cmd+Shift+D" -> "⇧⌘D": modifiers in the order of the Mac menus.
export function symbols(chord) {
  const parts = chord.split("+");
  const key = parts.pop() || "+";
  return MODS.filter((m) => parts.includes(m)).map((m) => SYMBOLS[m]).join("") + (KEYS[key] ?? key);
}

// Groups of { chords, alt, text, src }; rows with the same text share one line.
export function helpGroups(rows) {
  const groups = new Map();
  for (const row of rows) {
    const lines = groups.get(row.group) ?? [];
    const same = lines.find((l) => l.text === row.text);
    const line = same ?? { text: row.text, chords: [], alt: [], src: row.src ?? "Ghostty" };
    line.chords.push(...row.chords);
    line.alt.push(...(row.alt ?? []));
    if (!same) lines.push(line);
    groups.set(row.group, lines);
  }
  const names = [...groups.keys()].sort((a, b) => rank(a) - rank(b));
  return names.map((name) => ({ name, lines: groups.get(name) }));
}

function rank(name) {
  const i = FIRST_GROUPS.indexOf(name);
  return i < 0 ? FIRST_GROUPS.length : i;
}
