// Shape of a key row and the checks every row set must pass (docs/plans/s5-demo.md section 6).
// Row: { id, chords: ["Cmd+D"], alt: ["Ctrl+Alt+D"], when: "terminal" | "viewer" | "any",
//        group, text, cmd, payload }. One chord per array entry: "Cmd+1 ... 8" is eight rows.
const MODS = ["Ctrl", "Alt", "Shift", "Cmd"];
const WHEN = ["terminal", "viewer", "any"];

// Canonical chord: modifiers in fixed order, then the key.
export function normalize(chord) {
  const parts = chord.split("+");
  const key = parts.pop() || "+";
  const mods = parts.filter((m) => MODS.includes(m));
  if (mods.length !== parts.length) throw new Error(`bad chord: ${chord}`);
  return [...MODS.filter((m) => mods.includes(m)), key.length === 1 ? key.toUpperCase() : key].join("+");
}

const overlaps = (a, b) => a === "any" || b === "any" || a === b;

// A chord a shell or editor in the pane would receive as input: Ctrl+letter or Alt+letter alone.
const isShellInput = (chord) => /^(Ctrl|Alt)\+[A-Z]$/.test(chord);

export function checkRows(rows) {
  const problems = [];
  const seen = new Map();
  const ids = new Set();

  for (const row of rows) {
    if (ids.has(row.id)) problems.push(`duplicate id: ${row.id}`);
    ids.add(row.id);
    if (!WHEN.includes(row.when)) problems.push(`${row.id}: bad when`);
    if (!row.group || !row.text || !row.cmd) problems.push(`${row.id}: group, text and cmd are required`);
    if (!row.chords?.length) problems.push(`${row.id}: no chords`);

    for (const raw of [...(row.chords ?? []), ...(row.alt ?? [])]) {
      let chord;
      try { chord = normalize(raw); } catch (e) { problems.push(`${row.id}: ${e.message}`); continue; }
      if (isShellInput(chord)) problems.push(`${row.id}: ${chord} is shell input`);
      for (const other of seen.get(chord) ?? []) {
        if (overlaps(row.when, other.when)) problems.push(`${row.id} and ${other.id} share ${chord}`);
      }
      seen.set(chord, [...(seen.get(chord) ?? []), row]);
    }

    for (const raw of row.alt ?? []) {
      if (!/^Ctrl\+Alt\+/.test(raw)) problems.push(`${row.id}: fallback ${raw} must be Ctrl+Alt+key`);
    }
  }
  return problems;
}
