// One keydown dispatcher in the capture phase, so app keys win over the terminal.
// Rows are data (keys/*.js); `when` encodes focus, so Cmd+D and Cmd+W resolve by where the user is.
import { bus } from "./bus.js";
import { normalize, checkRows } from "./keys/schema.js";

const PUNCTUATION = {
  BracketLeft: "[", BracketRight: "]", Comma: ",", Period: ".", Slash: "/", Backslash: "\\",
  Equal: "=", Minus: "-", Backquote: "`", Semicolon: ";", Quote: "'",
  ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left", ArrowRight: "Right",
};

// Latin letters by e.key, everything else by physical code: Cyrillic layouts and Option
// (which turns D into a symbol) still give the letter on the key.
function keyToken(e) {
  if (/^[a-z]$/i.test(e.key)) return e.key.toUpperCase();
  const letter = /^Key([A-Z])$/.exec(e.code) ?? /^Digit(\d)$/.exec(e.code);
  if (letter) return letter[1];
  return PUNCTUATION[e.code] ?? e.code;
}

export function eventChord(e) {
  const mods = [e.ctrlKey && "Ctrl", e.altKey && "Alt", e.shiftKey && "Shift", e.metaKey && "Cmd"].filter(Boolean);
  return [...mods, keyToken(e)].join("+");
}

const table = new Map();
let focusArea = () => "any";

// Throws when the rows break the rules of keys/schema.js.
export function installKeys(rows, { focus }) {
  const problems = checkRows(rows);
  if (problems.length) throw new Error(`key rows invalid: ${problems.join("; ")}`);
  focusArea = focus;
  for (const row of rows) {
    for (const chord of [...row.chords, ...(row.alt ?? [])]) {
      const key = normalize(chord);
      table.set(key, [...(table.get(key) ?? []), row]);
    }
  }
  document.addEventListener("keydown", dispatch, true);
}

function dispatch(e) {
  if (e.isComposing) return;
  const area = focusArea();
  const row = table.get(eventChord(e))?.find((r) => r.when === "any" || r.when === area);
  if (!row) return;
  e.preventDefault();
  e.stopPropagation();
  bus.cmd(row.cmd, row.payload);
}

// Full screen plus Keyboard Lock gives the page Cmd+T, Cmd+W and Cmd+N in Chrome and Edge.
export function lockKeysInFullscreen() {
  document.addEventListener("fullscreenchange", () => {
    if (document.fullscreenElement) navigator.keyboard?.lock?.().catch((e) => console.warn("tarn-demo: keyboard lock", e));
    else navigator.keyboard?.unlock?.();
  });
}
