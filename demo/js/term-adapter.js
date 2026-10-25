// The only module that imports the terminal engine (ghostty-web). Everything else
// talks to the Term object below, so the xterm.js fallback is a swap of this file.
import { init, Terminal, FitAddon } from "../vendor/ghostty-web/ghostty-web.js";

const ESC = "\x1b";
let engine;

// Engine bugs worked around here, found by the slice 0 spike (docs/plans/s5-demo-contracts.md section 2):
//  - Alt+key sends no ESC prefix and Cmd+key leaks its letter to the shell: own keydown handler.
//  - Shift+Tab sends a plain Tab: own encoding.
//  - cell metrics are whole CSS pixels, so at fractional DPR cell edges blur into seams:
//    round metrics up to whole device pixels.
//  - the render loop redraws the cursor every frame even when nothing changed: skip idle frames.

function keyData(e, optionAsAlt) {
  if (e.metaKey && e.code !== "KeyC" && e.code !== "KeyV") return "";
  if (e.shiftKey && e.key === "Tab") return `${ESC}[Z`;
  if (optionAsAlt && e.altKey && !e.ctrlKey && !e.metaKey) {
    const letter = /^Key([A-Z])$/.exec(e.code);
    const digit = /^Digit(\d)$/.exec(e.code);
    const base = letter ? (e.shiftKey ? letter[1] : letter[1].toLowerCase()) : digit ? digit[1] : e.key;
    if (base.length === 1) return ESC + base;
  }
  return null;
}

function alignMetricsToDevicePixels(renderer) {
  const measure = renderer.measureFont.bind(renderer);
  renderer.measureFont = () => {
    const m = measure();
    const dpr = window.devicePixelRatio;
    return { ...m, width: Math.ceil(m.width * dpr) / dpr, height: Math.ceil(m.height * dpr) / dpr };
  };
  renderer.remeasureFont();
}

function skipIdleFrames(term) {
  const renderer = term.renderer;
  const draw = renderer.render.bind(renderer);
  let last = "";
  renderer.render = (buffer, force, viewportY, scrollback, opacity) => {
    const cursor = buffer.getCursor();
    const selected = term.hasSelection() ? JSON.stringify(term.getSelectionPosition()) : "";
    const sig = `${cursor.x},${cursor.y},${viewportY},${opacity},${selected}`;
    const idle = !force && !renderer.cursorBlink && !buffer.isDirty() && !buffer.needsFullRedraw() && sig === last;
    last = sig;
    if (!idle) draw(buffer, force, viewportY, scrollback, opacity);
  };
}

const THEME_KEYS = new Set(["theme", "fontSize", "fontFamily", "cursorStyle", "cursorBlink"]);

class Term {
  #t;
  #fit = new FitAddon();
  #data = new Set();
  #selection = new Set();
  #optionAsAlt = false;
  #copyOnSelect = true;
  #lastSelection = "";

  constructor(t, parent) {
    this.#t = t;
    // The engine focuses itself on open (and again on a timer); a pane opened by the boot must not
    // take the focus, so its focus() is silent while it opens.
    t.focus = () => {};
    t.open(parent);
    delete t.focus;
    alignMetricsToDevicePixels(t.renderer);
    skipIdleFrames(t);
    t.loadAddon(this.#fit);
    this.#fit.observeResize();
    t.onData((d) => this.#emit(d));
    this.#watchSelection(parent);
    t.attachCustomKeyEventHandler((e) => {
      const data = keyData(e, this.#optionAsAlt);
      if (data === null) return false;
      if (data) this.#emit(data);
      return true;
    });
    this.fit();
  }

  // The engine copies every selection to the clipboard with no switch, so the adapter
  // copies (copy-on-select) and notifies itself, after a mouse selection ends.
  #watchSelection(parent) {
    this.#t.selectionManager.copyToClipboard = () => {};
    const settle = () => setTimeout(() => {
      const text = this.#t.getSelection();
      if (text === this.#lastSelection) return;
      this.#lastSelection = text;
      if (text && this.#copyOnSelect) navigator.clipboard.writeText(text).catch((e) => console.warn("tarn-demo: copy", e));
      for (const fn of this.#selection) fn(text);
    }, 0);
    parent.addEventListener("mousedown", () => { this.#lastSelection = this.#t.getSelection(); });
    document.addEventListener("mouseup", settle);
    parent.addEventListener("dblclick", settle);
  }

  #emit(d) {
    for (const fn of this.#data) fn(d);
  }

  get cols() { return this.#t.cols; }
  get rows() { return this.#t.rows; }
  get options() { return Object.freeze({ ...this.#t.options }); }
  // Absolute row of the cursor in scrollback plus screen; the shell stores it per prompt.
  get cursorRow() { return this.#t.getScrollbackLength() + this.#t.buffer.active.cursorY; }
  // Absolute row shown at the top of the viewport.
  get topRow() { return this.#t.getScrollbackLength() - Math.round(this.#t.getViewportY()); }
  get lineCount() { return this.#t.getScrollbackLength() + this.#t.rows; }

  set optionAsAlt(on) { this.#optionAsAlt = on; }
  set copyOnSelect(on) { this.#copyOnSelect = on; }

  write(data) { this.#t.write(data); }
  paste(text) { this.#t.paste(text); }
  // The engine's own focus() repeats itself on a timer, which pulls the focus back from a pane the
  // user already left; focus the element once.
  focus() { this.#t.element.focus(); }
  fit() { this.#fit.fit(); }
  // The engine counts scrollToLine from the bottom, not from the top as its docs say.
  scrollToRow(row) { this.#t.scrollToLine(Math.max(0, this.#t.getScrollbackLength() - row)); }
  getSelection() { return this.#t.getSelection(); }
  clearSelection() { this.#t.clearSelection(); }
  select(col, row, length) { this.#t.select(col, row, length); }

  // A font that is not loaded yet would be measured as the fallback, so wait for it first.
  async setOption(key, value) {
    if (!THEME_KEYS.has(key)) throw new Error(`term option not supported: ${key}`);
    if (key === "fontFamily") await loadFont(value, this.#t.options.fontSize);
    this.#t.options[key] = value;
    if (key === "fontSize" || key === "fontFamily") this.fit();
  }

  onData(fn) { this.#data.add(fn); return () => this.#data.delete(fn); }
  onResize(fn) { return this.#t.onResize(fn).dispose; }
  onSelection(fn) { this.#selection.add(fn); return () => this.#selection.delete(fn); }

  // Text of one absolute row with blanks kept, so a screen is rows x cols.
  lineText(row) {
    const line = this.#t.buffer.active.getLine(row);
    if (!line) return "";
    let s = "";
    for (let x = 0; x < line.length; x++) s += line.getCell(x)?.getChars() || " ";
    return s;
  }

  screenText() {
    const top = this.#t.getScrollbackLength();
    return Array.from({ length: this.#t.rows }, (_, y) => this.lineText(top + y)).join("\n");
  }

  // `find(lineText) -> [{start, end, text}]` (columns, end exclusive); `activate(text, event)` on click.
  addLinkProvider(find, activate) {
    this.#t.registerLinkProvider({
      provideLinks: (y, done) => {
        const found = find(this.lineText(y));
        done(found.length ? found.map(({ start, end, text }) => ({
          text,
          range: { start: { x: start, y }, end: { x: end - 1, y } },
          activate: (e) => activate(text, e),
        })) : undefined);
      },
    });
  }

  // Page position of the middle of a cell on the visible screen, for tests and drag hints.
  cellCentre(col, row) {
    const r = this.#t.renderer;
    const box = r.getCanvas().getBoundingClientRect();
    return { x: box.left + (col + 0.5) * r.charWidth, y: box.top + (row + 0.5) * r.charHeight };
  }

  dispose() {
    this.#data.clear();
    this.#fit.dispose();
    this.#t.dispose();
  }
}

// Fonts load lazily; metrics measured before the file arrives are wrong.
async function loadFont(family, size) {
  await Promise.all(["M", "Мж"].map((s) => document.fonts.load(`${size}px ${family}`, s)));
}

export async function createTerm(parent, options = {}) {
  engine ??= init();
  await engine;
  if (options.fontFamily) await loadFont(options.fontFamily, options.fontSize ?? 14);
  return new Term(new Terminal({ cursorBlink: false, ...options }), parent);
}
