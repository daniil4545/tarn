// Line editor of the simulated shell: the readline subset zsh users expect.
// Input is the raw byte stream from the terminal; output goes to `write`. No engine inside:
// the editor only needs `cols()` to place the cursor on wrapped lines.
import { ESC, width, stripAnsi, charWidth } from "./ansi.js";

const TOKEN = /^(?:\x1b\[200~|\x1b\[[0-9;]*[~A-Za-z]|\x1bO[A-Za-z]|\x1b[\x00-\x7f]|\x1b|[\x00-\x1f\x7f]|[^\x00-\x1f\x7f\x1b]+)/;
const PASTE_END = `${ESC}[201~`;

const isSpace = (ch) => /\s/.test(ch);

export function createEditor({ write, cols, history = null, complete = null, on }) {
  let prompt = "";
  let chars = [];
  let cursor = 0;
  let rowsUp = 0; // rows between the first row of the line and the cursor row
  let browsing = null; // index into history while the arrows are used
  let draft = "";
  let pasting = null; // text of an open bracketed paste
  let tabbed = false; // the last key was a completion that found nothing more to add

  const text = () => chars.join("");
  const columnsTo = (n) => chars.slice(0, n).reduce((w, ch) => w + charWidth(ch), 0);

  // Redraw the whole line and put the cursor where it belongs, also across wrapped rows.
  function render() {
    const c = cols();
    const start = width(prompt);
    const full = start + columnsTo(chars.length);
    const target = start + columnsTo(cursor);
    let out = rowsUp ? `${ESC}[${rowsUp}A` : "";
    out += `\r${ESC}[J${prompt}${text()}`;
    if (full > 0 && full % c === 0) out += " \r"; // leave the pending-wrap state, as zsh does
    const endRow = Math.floor(full / c);
    const row = Math.floor(target / c);
    if (endRow > row) out += `${ESC}[${endRow - row}A`;
    out += `${ESC}[${(target % c) + 1}G`;
    rowsUp = row;
    write(out);
  }

  function set(next, at = next.length) {
    chars = Array.from(next);
    cursor = Math.min(at, chars.length);
  }

  function insert(s) {
    const add = Array.from(s);
    const atEnd = cursor === chars.length;
    chars.splice(cursor, 0, ...add);
    cursor += add.length;
    const w = width(prompt) + columnsTo(chars.length);
    // Typing at the end of a line that stays inside one row needs no redraw.
    if (atEnd && Math.floor(w / cols()) === rowsUp && w % cols() !== 0) write(s);
    else render();
  }

  function wordStart(from) {
    let i = from;
    while (i > 0 && isSpace(chars[i - 1])) i--;
    while (i > 0 && !isSpace(chars[i - 1])) i--;
    return i;
  }

  function wordEnd(from) {
    let i = from;
    while (i < chars.length && isSpace(chars[i])) i++;
    while (i < chars.length && !isSpace(chars[i])) i++;
    return i;
  }

  function cut(from, to) {
    chars.splice(from, to - from);
    cursor = from;
    render();
  }

  function recall(step) {
    if (!history?.length) return;
    if (browsing === null) {
      if (step > 0) return;
      draft = text();
      browsing = history.length;
    }
    browsing += step;
    if (browsing >= history.length) {
      browsing = null;
      set(draft);
    } else {
      browsing = Math.max(0, browsing);
      set(history[browsing]);
    }
    render();
  }

  function listBelow(items) {
    cursor = chars.length;
    render();
    const wide = Math.max(...items.map((i) => width(i.label))) + 2;
    const perRow = Math.max(1, Math.floor(cols() / wide));
    let out = "\r\n";
    items.forEach((item, i) => {
      out += item.label + " ".repeat(wide - width(item.label));
      if ((i + 1) % perRow === 0 && i + 1 < items.length) out += "\r\n";
    });
    write(`${out}\r\n`);
    rowsUp = 0;
    render();
  }

  function tab() {
    if (!complete) return;
    const { from, items } = complete(chars.slice(0, cursor).join(""));
    if (!items.length) return;
    const typed = cursor - from;
    const common = items.map((i) => i.insert).reduce((a, b) => {
      let n = 0;
      while (n < a.length && n < b.length && a[n] === b[n]) n++;
      return a.slice(0, n);
    });
    let next = null;
    if (items.length === 1) next = items[0].insert + (items[0].insert.endsWith("/") ? "" : " ");
    else if (Array.from(common).length > typed) next = common;
    if (next !== null) {
      chars.splice(from, cursor - from, ...Array.from(next));
      cursor = from + Array.from(next).length;
      render();
      tabbed = false;
    } else if (tabbed) {
      listBelow(items);
    } else {
      tabbed = true; // nothing to add: a second Tab lists the choices
    }
  }

  function accept() {
    cursor = chars.length;
    render();
    write("\r\n");
    const line = text();
    if (line.trim() && history && history.at(-1) !== line) history.push(line);
    chars = [];
    cursor = 0;
    rowsUp = 0;
    browsing = null;
    on.line(line);
  }

  const KEYS = {
    "\r": accept,
    "\n": accept,
    "\x7f": () => cursor > 0 && cut(cursor - 1, cursor),
    "\b": () => cursor > 0 && cut(cursor - 1, cursor),
    "\x03": () => { write("^C\r\n"); chars = []; cursor = 0; rowsUp = 0; browsing = null; on.interrupt(); },
    "\x04": () => (chars.length ? cursor < chars.length && cut(cursor, cursor + 1) : on.eof()),
    "\x0c": () => on.clear(),
    "\x01": () => { cursor = 0; render(); },
    "\x05": () => { cursor = chars.length; render(); },
    "\x02": () => { cursor = Math.max(0, cursor - 1); render(); },
    "\x06": () => { cursor = Math.min(chars.length, cursor + 1); render(); },
    "\x0b": () => cut(cursor, chars.length),
    "\x15": () => cut(0, chars.length),
    "\x17": () => cut(wordStart(cursor), cursor),
    "\x10": () => recall(-1),
    "\x0e": () => recall(1),
    "\t": tab,
    [`${ESC}[A`]: () => recall(-1),
    [`${ESC}OA`]: () => recall(-1),
    [`${ESC}[B`]: () => recall(1),
    [`${ESC}OB`]: () => recall(1),
    [`${ESC}[C`]: () => { cursor = Math.min(chars.length, cursor + 1); render(); },
    [`${ESC}OC`]: () => { cursor = Math.min(chars.length, cursor + 1); render(); },
    [`${ESC}[D`]: () => { cursor = Math.max(0, cursor - 1); render(); },
    [`${ESC}OD`]: () => { cursor = Math.max(0, cursor - 1); render(); },
    [`${ESC}[H`]: () => { cursor = 0; render(); },
    [`${ESC}OH`]: () => { cursor = 0; render(); },
    [`${ESC}[1~`]: () => { cursor = 0; render(); },
    [`${ESC}[F`]: () => { cursor = chars.length; render(); },
    [`${ESC}OF`]: () => { cursor = chars.length; render(); },
    [`${ESC}[4~`]: () => { cursor = chars.length; render(); },
    [`${ESC}[3~`]: () => cursor < chars.length && cut(cursor, cursor + 1),
    [`${ESC}b`]: () => { cursor = wordStart(cursor); render(); },
    [`${ESC}f`]: () => { cursor = wordEnd(cursor); render(); },
    [`${ESC}[1;3D`]: () => { cursor = wordStart(cursor); render(); },
    [`${ESC}[1;3C`]: () => { cursor = wordEnd(cursor); render(); },
    [`${ESC}[1;5D`]: () => { cursor = wordStart(cursor); render(); },
    [`${ESC}[1;5C`]: () => { cursor = wordEnd(cursor); render(); },
    [`${ESC}\x7f`]: () => cut(wordStart(cursor), cursor),
  };

  function handle(token) {
    if (token === `${ESC}[200~`) { pasting = ""; return; }
    const key = KEYS[token];
    if (key) {
      if (token !== "\t") tabbed = false;
      key();
    } else if (!token.startsWith(ESC) && !/^[\x00-\x1f\x7f]/.test(token)) {
      tabbed = false;
      insert(token);
    }
  }

  return {
    // Start a new line: draw the prompt.
    begin(nextPrompt) {
      prompt = nextPrompt;
      chars = [];
      cursor = 0;
      rowsUp = 0;
      browsing = null;
      tabbed = false;
      write(prompt);
    },

    input(data) {
      let rest = data;
      while (rest) {
        if (pasting !== null) {
          const end = rest.indexOf(PASTE_END);
          pasting += end < 0 ? rest : rest.slice(0, end);
          if (end < 0) return;
          rest = rest.slice(end + PASTE_END.length);
          // One line stays one line: a pasted line break becomes a space, nothing runs unasked.
          const paste = pasting.replace(/\s*\r?\n\s*/g, " ");
          pasting = null;
          if (paste) insert(paste);
          continue;
        }
        const token = TOKEN.exec(rest)?.[0] ?? rest[0];
        rest = rest.slice(token.length);
        handle(token);
      }
    },

    // The terminal changed its width: the line wrapped differently, draw it again where it is.
    reflow() {
      rowsUp = Math.floor((width(prompt) + columnsTo(cursor)) / cols());
      render();
    },
    // Draw prompt and text again at the top of a cleared screen.
    redraw() { rowsUp = 0; render(); },
    get text() { return text(); },
    get promptText() { return stripAnsi(prompt); },
  };
}
