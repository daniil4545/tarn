// Find in the focused terminal: a bar over the tab area, scan of the whole scrollback with
// lineText, jump with scrollToRow and select. Enter and Shift+Enter step, Escape closes.
import { bus } from "./bus.js";
import { currentTab, paneOf } from "./workspace.js";

let bar;
let input;
let count;
let matches = [];
let at = -1;

const term = () => paneOf(currentTab().focus)?.term;

export function startFind() {
  const ws = document.getElementById("ws");
  ws.insertAdjacentHTML("beforeend", '<div class="findbar" id="findbar" hidden><input type="text" placeholder="Find" aria-label="Find"><span class="count"></span><button class="ib" data-find="-1" aria-label="Previous">↑</button><button class="ib" data-find="1" aria-label="Next">↓</button><button class="ib" data-find="0" aria-label="Close">✕</button></div>');
  bar = ws.querySelector("#findbar");
  input = bar.querySelector("input");
  count = bar.querySelector(".count");
  input.addEventListener("input", search);
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") step(e.shiftKey ? -1 : 1);
    else if (e.key === "Escape") close();
  });
  bar.addEventListener("click", (e) => {
    const button = e.target.closest("[data-find]");
    if (button) { const n = Number(button.dataset.find); if (n) step(n); else close(); }
  });
  // With the window closed there is no terminal to search.
  const guarded = (fn) => () => (currentTab() ? fn() : undefined);
  bus.handle("find.open", guarded(open));
  bus.handle("find.next", guarded(() => (input.value ? step(1) : open())));
  bus.handle("find.prev", guarded(() => (input.value ? step(-1) : open())));
}

function open() {
  bar.hidden = false;
  input.focus();
  input.select();
  search();
}

function close() {
  bar.hidden = true;
  matches = [];
  paneOf(currentTab().focus)?.focus();
}

function search() {
  const t = term(), needle = input.value.toLowerCase();
  matches = [];
  if (t && needle) {
    for (let row = 0; row < t.lineCount; row++) {
      const text = t.lineText(row).toLowerCase();
      for (let col = text.indexOf(needle); col >= 0; col = text.indexOf(needle, col + needle.length)) matches.push({ row, col });
    }
  }
  at = -1;
  count.textContent = needle ? `${matches.length}` : "";
  if (matches.length) step(1);
}

function step(delta) {
  if (!matches.length) return;
  at = (at + delta + matches.length) % matches.length;
  const { row, col } = matches[at], t = term();
  t.scrollToRow(row);
  t.select(col, row, input.value.length);
  count.textContent = `${at + 1}/${matches.length}`;
}
