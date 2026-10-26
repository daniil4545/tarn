// Find in the viewer page, as Ghostty's terminal search bar works (SurfaceView.swift, SurfaceSearchOverlay):
// a field at the top right with "n/m", Enter and Shift+Enter step, Escape closes an empty bar or gives
// the keyboard back to the file. View mode marks the rendered text with the CSS Custom Highlight API;
// source mode marks the editor's whole document, which CodeMirror draws only in part.
import { EditorView, Decoration } from "@codemirror/view";
import { StateEffect, StateField } from "@codemirror/state";

const setMarks = StateEffect.define();

// The marks of the editor: every match, the current one apart. They follow edits.
export const findField = StateField.define({
  create: () => Decoration.none,
  update(marks, tr) {
    for (const e of tr.effects) if (e.is(setMarks)) return e.value;
    return marks.map(tr.changes);
  },
  provide: f => EditorView.decorations.from(f),
});

const all = Decoration.mark({ class: "cm-find" });
const now = Decoration.mark({ class: "cm-find-now" });

// Start and end offsets of each case-insensitive match of `needle` in `text`.
export function matchesIn(text, needle) {
  const out = [];
  if (!needle) return out;
  const hay = text.toLowerCase(), n = needle.toLowerCase();
  for (let i = hay.indexOf(n); i >= 0; i = hay.indexOf(n, i + n.length)) out.push([i, i + n.length]);
  return out;
}

// `env`: { box() the content element, editor() the CodeMirror view or null, focusContent() }.
export function createFind(env) {
  const bar = document.createElement("div");
  bar.id = "findbar";
  bar.hidden = true;
  bar.innerHTML = '<span class="field"><input type="text" placeholder="Search" aria-label="Search" spellcheck="false"><span class="count"></span></span>'
    + '<button data-step="-1" aria-label="Previous match" title="Previous (Shift+Enter)">&#8963;</button>'
    + '<button data-step="1" aria-label="Next match" title="Next (Enter)">&#8964;</button>'
    + '<button data-step="0" aria-label="Close" title="Close">&#10005;</button>';
  const input = bar.querySelector("input"), count = bar.querySelector(".count");
  let hits = [], at = -1;

  const textNodes = root => {
    const walk = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      // Line numbers and diagram drawings are not text of the file.
      acceptNode: n => (n.parentElement.closest(".ln, svg, .mm-src[hidden]") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    const nodes = [];
    for (let n = walk.nextNode(); n; n = walk.nextNode()) nodes.push(n);
    return nodes;
  };

  // DOM ranges of the matches in view mode; a match may cross the spans of highlighted code.
  function domHits(needle) {
    const scroll = env.box().querySelector(".scroll");
    if (!scroll) return [];
    const nodes = textNodes(scroll), starts = [];
    let text = "";
    for (const n of nodes) { starts.push(text.length); text += n.data; }
    const at = offset => {
      let i = starts.length - 1;
      while (i > 0 && starts[i] > offset) i--;
      return [nodes[i], offset - starts[i]];
    };
    return matchesIn(text, needle).map(([from, to]) => {
      const range = document.createRange();
      range.setStart(...at(from));
      range.setEnd(...at(to - 1));
      range.setEnd(range.endContainer, range.endOffset + 1);
      return range;
    });
  }

  function paint() {
    const view = env.editor();
    if (view) {
      const marks = hits.map(([from, to], i) => (i === at ? now : all).range(from, to));
      view.dispatch({ effects: setMarks.of(Decoration.set(marks)) });
      return;
    }
    if (!globalThis.CSS?.highlights) return;
    CSS.highlights.set("tarn-find", new Highlight(...hits.filter((_, i) => i !== at)));
    if (hits[at]) CSS.highlights.set("tarn-find-now", new Highlight(hits[at]));
    else CSS.highlights.delete("tarn-find-now");
  }

  function show() {
    const view = env.editor(), hit = hits[at];
    if (!hit) return;
    if (view) {
      view.dispatch({ effects: EditorView.scrollIntoView(hit[0], { y: "center" }) });
      return;
    }
    const scroll = env.box().querySelector(".scroll");
    const rect = hit.getBoundingClientRect(), outer = scroll.getBoundingClientRect();
    if (rect.top < outer.top || rect.bottom > outer.bottom) scroll.scrollTop += rect.top - outer.top - scroll.clientHeight / 3;
  }

  function search(keep) {
    const view = env.editor(), needle = input.value;
    hits = view ? matchesIn(view.state.sliceDoc(), needle) : domHits(needle);
    at = hits.length ? Math.min(keep ? Math.max(at, 0) : 0, hits.length - 1) : -1;
    count.textContent = !needle ? "" : hits.length ? `${at + 1}/${hits.length}` : "0/0";
    paint();
    if (!keep) show();
  }

  function step(delta) {
    if (!input.value) return open();
    if (!hits.length) return undefined;
    at = (at + delta + hits.length) % hits.length;
    count.textContent = `${at + 1}/${hits.length}`;
    paint();
    show();
    return undefined;
  }

  function clear() {
    hits = []; at = -1;
    globalThis.CSS?.highlights?.delete("tarn-find");
    globalThis.CSS?.highlights?.delete("tarn-find-now");
    env.editor()?.dispatch({ effects: setMarks.of(Decoration.none) });
  }

  function open() {
    bar.hidden = false;
    input.focus();
    input.select();
    search(false);
  }

  function close() {
    bar.hidden = true;
    clear();
    env.focusContent();
  }

  input.addEventListener("input", () => search(false));
  input.addEventListener("keydown", e => {
    if (e.key === "Enter") { e.preventDefault(); step(e.shiftKey ? -1 : 1); }
    else if (e.key === "Escape") { e.preventDefault(); if (input.value) env.focusContent(); else close(); }
  });
  bar.addEventListener("click", e => {
    const b = e.target.closest("[data-step]");
    if (!b) return;
    const n = Number(b.dataset.step);
    if (n) step(n); else close();
  });

  return {
    bar,
    // Swift's menu items: Find, Find Next, Find Previous, Hide Find Bar.
    run(cmd) {
      if (cmd === "open") open();
      else if (cmd === "next") step(1);
      else if (cmd === "prev") step(-1);
      else if (cmd === "hide" && !bar.hidden) close();
    },
    // The page drew the content again (another tab, a change on disk, view or source).
    refresh() { if (!bar.hidden) search(true); },
  };
}
