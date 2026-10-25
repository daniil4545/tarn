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

// A field of the page itself (Find, Settings), not the terminal's own input.
const inPageField = (t) => t instanceof Element && t.closest("input, textarea") !== null && !t.closest(".pane");
const TEXT_CHORDS = new Set(["Cmd+Z", "Cmd+Shift+Z"]);

// While a modal window is open ("modal" area) only its own rows work.
const applies = (row, area) => (area === "modal" ? row.cmd.startsWith("settings.") : row.when === "any" || row.when === area);

function dispatch(e) {
  if (e.isComposing) return;
  // AltGr types a character on many layouts; it reports as Ctrl+Alt and must reach the field.
  if (e.getModifierState?.("AltGraph") && e.key.length === 1) return;
  const chord = eventChord(e);
  const area = focusArea();
  const row = table.get(chord)?.find((r) => applies(r, area));
  if (!row) return;
  // In a text field the terminal's keys and the text edit keys belong to the field. Find keeps its own.
  if (inPageField(e.target) && !row.cmd.startsWith("find.") && (row.when !== "any" || TEXT_CHORDS.has(chord))) return;
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
