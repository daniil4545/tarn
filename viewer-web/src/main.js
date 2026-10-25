// The page of the tarn viewer pane. Swift owns tabs, text and files and pushes state through
// `window.tarn`; this page draws it and reports user actions with `post`. See docs/plans/s2-files.md.
// Markdown setup follows MarkEdit-preview src/render.ts @5bdd252 (MIT); see THIRD_PARTY.md.
import MarkdownIt from "markdown-it";
import hljs from "highlight.js/lib/common";
import { EditorView, lineNumbers, highlightActiveLine, drawSelection, keymap } from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import { history, historyKeymap, defaultKeymap } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { syntaxHighlighting, HighlightStyle, StreamLanguage } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";
import { go } from "@codemirror/legacy-modes/mode/go";
import { python } from "@codemirror/legacy-modes/mode/python";
import { shell } from "@codemirror/legacy-modes/mode/shell";
import { yaml } from "@codemirror/legacy-modes/mode/yaml";
import { toml } from "@codemirror/legacy-modes/mode/toml";
import { swift } from "@codemirror/legacy-modes/mode/swift";
import { rust } from "@codemirror/legacy-modes/mode/rust";
import { standardSQL } from "@codemirror/legacy-modes/mode/sql";
import { c, cpp, java, kotlin } from "@codemirror/legacy-modes/mode/clike";
import { ruby } from "@codemirror/legacy-modes/mode/ruby";
import { lua } from "@codemirror/legacy-modes/mode/lua";
import { dockerFile } from "@codemirror/legacy-modes/mode/dockerfile";
import { diff } from "@codemirror/legacy-modes/mode/diff";
import { properties } from "@codemirror/legacy-modes/mode/properties";
import { protobuf } from "@codemirror/legacy-modes/mode/protobuf";
import { javascript, json, typescript } from "@codemirror/legacy-modes/mode/javascript";
import { css } from "@codemirror/legacy-modes/mode/css";
import { html, xml } from "@codemirror/legacy-modes/mode/xml";

const $ = id => document.getElementById(id);
const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const post = msg => window.webkit.messageHandlers.tarn.postMessage(msg);
const HIGHLIGHT_LIMIT = 512 * 1024;

// ---- state ----
let chrome = { tabs: [], active: -1, tree: { visible: false, rows: [] }, dark: true, conflicts: [] };
const docs = {}; // path -> { rev, kind, lang, text, notice, dir, line, jump }
const modes = {}; // path -> "view" | "source"
const scrollMem = {}; // "path|mode" -> scrollTop
const jumped = {}; // path -> last handled jump token
const rawMm = new Set(); // mermaid sources shown as text
const svgCache = new Map(); // theme + source -> svg
let treeSel = null;
let lastKey = "";
let lastPlace = "";
let cm = null; // { path, view }
let editTimer = null;
let pendingEdit = null;
let mmCount = 0;
let mermaidLoad = null;
let treeWasVisible = false;

const activePath = () => (chrome.active >= 0 && chrome.tabs[chrome.active] ? chrome.tabs[chrome.active].path : null);

// ---- markdown ----
const md = new MarkdownIt({ html: false, linkify: false });

md.core.ruler.after("inline", "tarn_tasks", state => {
  const toks = state.tokens;
  for (let i = 2; i < toks.length; i++) {
    if (toks[i].type !== "inline" || toks[i - 1].type !== "paragraph_open" || toks[i - 2].type !== "list_item_open") continue;
    const first = toks[i].children[0];
    const m = first && first.type === "text" && /^\[( |x|X)\]\s/.exec(first.content);
    if (!m) continue;
    first.content = first.content.slice(m[0].length);
    const li = toks[i - 2];
    li.attrJoin("class", "task");
    const box = new state.Token("html_inline", "", 0);
    box.content = `<input type="checkbox" data-line="${li.map ? li.map[0] : -1}"${m[1] === " " ? "" : " checked"} aria-label="Task"> `;
    toks[i].children.unshift(box);
  }
});

md.core.ruler.push("tarn_maps", state => {
  for (const tok of state.tokens) {
    if (tok.level === 0 && tok.map && tok.nesting !== -1) tok.attrSet("data-map", `${tok.map[0]},${tok.map[1]}`);
  }
});

md.core.ruler.push("tarn_heading_ids", state => {
  const used = new Set();
  state.tokens.forEach((tok, i) => {
    if (tok.type !== "heading_open") return;
    const text = state.tokens[i + 1].content.toLowerCase().trim();
    let id = text.replace(/[^\p{L}\p{N}\s-]/gu, "").replace(/\s+/g, "-") || "section";
    while (used.has(id)) id += "-1";
    used.add(id);
    tok.attrSet("id", "h-" + id);
  });
});

md.renderer.rules.fence = (tokens, idx) => {
  const tok = tokens[idx];
  const lang = tok.info.trim().split(/\s+/)[0];
  const code = tok.content;
  const map = tok.map ? ` data-map="${tok.map[0]},${tok.map[1]}"` : "";
  if (lang === "mermaid") return `<div class="mm"${map} data-src="${esc(code)}"></div>`;
  let html;
  if (lang && hljs.getLanguage(lang) && code.length < HIGHLIGHT_LIMIT) {
    html = hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
  } else {
    html = esc(code);
  }
  return `<pre${map}><button class="copy" type="button">Copy</button><code class="hljs">${html}</code></pre>\n`;
};

function joinPath(dir, rel) {
  const parts = (rel.startsWith("/") ? rel : `${dir}/${rel}`).split("/");
  const out = [];
  for (const p of parts) {
    if (p === "" || p === ".") continue;
    if (p === "..") out.pop();
    else out.push(p);
  }
  return "/" + out.join("/");
}

md.renderer.rules.image = (tokens, idx, _opts, env) => {
  const tok = tokens[idx];
  const src = tok.attrGet("src") || "";
  const alt = esc(tok.content);
  if (/^(https?:)?\/\//i.test(src)) return `<a href="${esc(src)}">${alt || esc(src)}</a>`;
  if (/^data:image\//i.test(src)) return `<img src="${esc(src)}" alt="${alt}">`;
  let rel = src;
  try { rel = decodeURI(src); } catch (e) { /* keep the raw value */ }
  const abs = joinPath(env.dir || "/", rel);
  return `<img src="tarn-md://file${encodeURI(abs).replace(/[?#]/g, encodeURIComponent)}" alt="${alt}">`;
};

// ---- mermaid ----
function loadMermaid() {
  if (!mermaidLoad) {
    mermaidLoad = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = "tarn-mermaid.js";
      s.onload = () => resolve(window.mermaid);
      s.onerror = () => reject(new Error("mermaid failed to load"));
      document.head.appendChild(s);
    });
  }
  return mermaidLoad;
}

function paintMermaid(box, svg) {
  const src = box.dataset.src;
  const raw = rawMm.has(src) || svg === null;
  const toggle = `<button class="mtoggle" type="button">${rawMm.has(src) ? "Diagram" : "Source"}</button>`;
  box.innerHTML = toggle + (raw ? `<pre><code>${esc(src)}</code></pre>` : svg);
}

async function drawMermaid(box) {
  const src = box.dataset.src;
  const key = (chrome.dark ? "d" : "l") + src;
  if (rawMm.has(src)) return paintMermaid(box, null);
  if (svgCache.has(key)) return paintMermaid(box, svgCache.get(key));
  paintMermaid(box, null);
  box.querySelector("pre").style.opacity = ".5";
  try {
    const mermaid = await loadMermaid();
    mermaid.initialize({ startOnLoad: false, securityLevel: "strict", layout: "dagre", theme: chrome.dark ? "dark" : "default" });
    const id = "mm" + mmCount++;
    const { svg } = await mermaid.render(id, src);
    svgCache.set(key, svg);
    if (box.isConnected && !rawMm.has(src)) paintMermaid(box, svg);
  } catch (e) {
    document.querySelectorAll('[id^="dmm"]').forEach(n => n.remove());
    if (box.isConnected) {
      paintMermaid(box, null);
      const note = document.createElement("div");
      note.className = "mmerr";
      note.textContent = "Diagram error: " + String(e && e.message ? e.message : e).split("\n")[0];
      box.appendChild(note);
    }
  }
}

// ---- views ----
function highlightLines(text, lang) {
  let lines;
  if (!lang || text.length > HIGHLIGHT_LIMIT || !hljs.getLanguage(lang)) {
    lines = text.split("\n").map(esc);
  } else {
    const html = hljs.highlight(text, { language: lang, ignoreIllegals: true }).value;
    lines = [];
    let open = [];
    for (const line of html.split("\n")) {
      const stack = [...open];
      const re = /<span[^>]*>|<\/span>/g;
      let m;
      while ((m = re.exec(line))) {
        if (m[0] === "</span>") stack.pop();
        else stack.push(m[0]);
      }
      lines.push(open.join("") + line + "</span>".repeat(stack.length));
      open = stack;
    }
  }
  if (lines.length > 1 && lines[lines.length - 1] === "") lines.pop();
  return lines;
}

const mdStyle = HighlightStyle.define([
  { tag: t.heading, fontWeight: "bold", color: "var(--p-accent)" },
  { tag: t.strong, fontWeight: "bold" },
  { tag: t.emphasis, fontStyle: "italic" },
  { tag: t.link, color: "var(--p-accent)" },
  { tag: t.url, color: "var(--p-muted)" },
  { tag: t.monospace, color: "var(--p-muted)" },
  { tag: t.quote, color: "var(--p-muted)" },
  { tag: t.processingInstruction, color: "var(--p-muted)" },
]);

// Editor grammars by the `lang` Swift sends (file extension, or the name when there is none).
const modesByLang = {
  go, py: python, sh: shell, bash: shell, zsh: shell, yaml, yml: yaml, toml, swift, rs: rust, sql: standardSQL,
  c, h: c, cpp, cc: cpp, hpp: cpp, java, kt: kotlin, rb: ruby, lua, dockerfile: dockerFile, diff, patch: diff,
  ini: properties, properties, proto: protobuf, js: javascript, mjs: javascript, ts: typescript, json,
  css, html, xml, svg: xml,
};

// Code colors reuse the view-mode highlight.js classes, so both modes and both themes match.
const codeStyle = HighlightStyle.define([
  { tag: [t.keyword, t.typeName, t.standard(t.variableName)], class: "hljs-keyword" },
  { tag: [t.string, t.special(t.string), t.attributeName], class: "hljs-string" },
  { tag: t.comment, class: "hljs-comment" },
  { tag: [t.number, t.bool, t.atom], class: "hljs-number" },
  { tag: [t.definition(t.variableName), t.function(t.variableName), t.className], class: "hljs-title" },
]);

function editorLanguage(doc) {
  if (doc.kind === "md") return [markdown(), syntaxHighlighting(mdStyle)];
  const mode = modesByLang[doc.lang];
  return mode ? [StreamLanguage.define(mode), syntaxHighlighting(codeStyle)] : [];
}

function destroyEditor() {
  if (cm) { cm.view.destroy(); cm = null; }
}

function scheduleEdit(path, text) {
  docs[path].text = text;
  pendingEdit = { path, text, rev: docs[path].rev };
  clearTimeout(editTimer);
  // The first edit goes at once, so the model knows the file is dirty before an agent rewrite can race it.
  const tab = chrome.tabs.find(x => x.path === path);
  if (tab && !tab.dirty) return flushEdit();
  editTimer = setTimeout(flushEdit, 120);
}

function flushEdit() {
  clearTimeout(editTimer);
  if (pendingEdit) { post({ t: "edit", ...pendingEdit }); pendingEdit = null; }
}

function mountEditor(path, text, scroll) {
  const crlf = text.includes("\r\n");
  const host = document.createElement("div");
  host.className = "cm-host";
  $("vcontent").replaceChildren(host);
  const view = new EditorView({
    parent: host,
    state: EditorState.create({
      doc: text,
      extensions: [
        ...(crlf ? [EditorState.lineSeparator.of("\r\n")] : []),
        lineNumbers(), history(), drawSelection(), highlightActiveLine(),
        ...editorLanguage(docs[path]),
        keymap.of([...defaultKeymap, ...historyKeymap]),
        EditorView.updateListener.of(u => { if (u.docChanged && cm && !cm.applying) scheduleEdit(path, u.state.sliceDoc()); }),
      ],
    }),
  });
  cm = { path, view, applying: false };
  view.scrollDOM.scrollTop = scroll;
  view.scrollDOM.addEventListener("scroll", () => { scrollMem[path + "|source"] = view.scrollDOM.scrollTop; }, { passive: true });
}

function scrollerOf() {
  return cm ? cm.view.scrollDOM : $("vcontent").querySelector(".scroll");
}

// The block that holds a source line (0-based); a line past the end gives the last block.
function blockAt(root, index) {
  let best = null;
  for (const el of root.querySelectorAll("[data-map]")) {
    const [from, to] = el.dataset.map.split(",").map(Number);
    if (from > index) break;
    best = el;
    if (index < to) break;
  }
  return best;
}

function renderContent(force) {
  const path = activePath();
  const box = $("vcontent");
  if (!path) {
    destroyEditor();
    box.innerHTML = '<div class="empty">Pick a file in the tree<br>or click a path in a terminal</div>';
    lastKey = ""; lastPlace = "";
    return;
  }
  const doc = docs[path];
  if (!doc) { destroyEditor(); box.innerHTML = '<div class="empty">Loading</div>'; lastKey = ""; lastPlace = ""; return; }
  const mode = doc.kind !== "notice" ? modes[path] || "view" : "view";
  const key = [path, doc.rev, mode, chrome.dark, doc.line, doc.jump].join("|");
  if (key === lastKey && !force) return;
  const place = path + "|" + mode;
  const same = place === lastPlace;
  const prev = same && scrollerOf() ? scrollerOf().scrollTop : null;
  const target = prev !== null ? prev : scrollMem[place] || 0;
  lastKey = key; lastPlace = place;

  if (doc.kind === "notice") {
    destroyEditor();
    box.innerHTML = `<div class="empty">${esc(doc.notice || "")}</div>`;
    return;
  }
  if (mode === "source") {
    if (cm && cm.path === path) {
      const cur = cm.view.state.sliceDoc();
      if (cur !== doc.text) {
        cm.applying = true;
        cm.view.dispatch({ changes: { from: 0, to: cur.length, insert: doc.text } });
        cm.applying = false;
      }
    } else {
      destroyEditor();
      mountEditor(path, doc.text, target);
    }
    return;
  }
  destroyEditor();
  if (doc.kind === "code") {
    const lines = highlightLines(doc.text, doc.lang);
    box.innerHTML = `<div class="scroll"><pre class="codeview">${lines.map((l, i) => `<div class="row${doc.line === i + 1 ? " hl" : ""}"><span class="ln">${i + 1}</span><code>${l || " "}</code></div>`).join("")}</pre></div>`;
  } else {
    box.innerHTML = `<div class="scroll"><article class="doc">${md.render(doc.text, { dir: doc.dir })}</article></div>`;
  }
  const sc = box.querySelector(".scroll");
  sc.scrollTop = target;
  sc.addEventListener("scroll", () => { scrollMem[place] = sc.scrollTop; }, { passive: true });
  const row = sc.querySelector(".row.hl");
  if (row && doc.jump && jumped[path] !== doc.jump) {
    jumped[path] = doc.jump;
    sc.scrollTop = Math.max(0, row.offsetTop - 120);
    row.classList.add("flash");
  }
  if (doc.kind === "md" && doc.line && doc.jump && jumped[path] !== doc.jump) {
    jumped[path] = doc.jump;
    const block = blockAt(sc, doc.line - 1);
    if (block) { sc.scrollTop = Math.max(0, block.offsetTop - 80); block.classList.add("flash"); }
  }
  const boxes = [...sc.querySelectorAll(".mm")];
  Promise.all(boxes.map(drawMermaid)).then(() => {
    if (same && box.isConnected && sc.isConnected && sc.scrollTop < target) sc.scrollTop = target;
  });
}

// ---- chrome ----
function renderTabs() {
  $("vtabs").innerHTML = chrome.tabs.map((tab, i) =>
    `<div class="ftab${i === chrome.active ? " on" : ""}${tab.preview ? " preview" : ""}" role="tab" draggable="true" data-idx="${i}" title="${esc(tab.path)}${tab.preview ? " (preview: the next file replaces this tab)" : ""}"><span class="nm">${esc(tab.name)}</span>${tab.dirty ? '<span class="dirty"></span>' : ""}<button class="x" type="button" data-close="${i}" aria-label="Close tab">✕</button></div>`).join("");
  const on = $("vtabs").querySelector(".ftab.on");
  if (on) on.scrollIntoView({ block: "nearest", inline: "nearest" });
  const path = activePath();
  const doc = path && docs[path];
  const editable = !!(doc && doc.kind !== "notice");
  const mode = path ? modes[path] || "view" : "view";
  $("vact").innerHTML =
    `<button class="ib" type="button" data-act="mode" ${editable ? "" : "disabled"} aria-pressed="${editable && mode === "source"}" title="View or source (⌘E)">${editable && mode === "source" ? "Source" : "View"}</button>` +
    `<button class="ib" type="button" data-act="tree" aria-pressed="${!!chrome.tree.visible}" title="Files tree (Esc hides it)">Files</button>` +
    `<button class="ib" type="button" data-act="closePane" title="Close viewer">✕</button>`;
}

function renderBanner() {
  const path = activePath();
  const show = path && chrome.conflicts.includes(path);
  $("banner").hidden = !show;
  if (show) {
    $("banner").innerHTML = `<span>The agent changed this file and you have unsaved edits.</span><button type="button" data-take="1">Take the agent version</button><button type="button" data-keep="1">Keep mine</button>`;
  }
}

function renderTree() {
  const tree = chrome.tree;
  const el = $("vtree");
  el.hidden = !tree.visible;
  if (!tree.visible) { treeWasVisible = false; return; }
  const current = activePath();
  if (!treeSel || !tree.rows.some(r => r.path === treeSel)) treeSel = current || (tree.rows[0] && tree.rows[0].path) || null;
  const rows = tree.rows.map(r =>
    `<div class="tr${r.path === treeSel ? " sel" : ""}${r.path === current ? " cur" : ""}" data-path="${esc(r.path)}" data-kind="${r.kind}" style="padding-left:${6 + r.depth * 12}px" title="${esc(r.path)}"><span class="chev">${r.kind === "dir" ? (r.open ? "▾" : "▸") : ""}</span>${esc(r.name)}${r.mod ? '<span class="mod">M</span>' : ""}</div>`).join("");
  const hadFocus = el.contains(document.activeElement);
  el.innerHTML = `<div class="tree" tabindex="0"><div class="th">${esc(tree.root || "")}<span>Enter open · ← file · Esc hide</span></div>${rows}</div>`;
  const sel = el.querySelector(".tr.sel");
  if (sel) sel.scrollIntoView({ block: "nearest" });
  if (!treeWasVisible || hadFocus) { treeWasVisible = true; el.querySelector(".tree").focus(); }
}

function refreshAll(force) {
  renderTabs(); renderBanner(); renderTree(); renderContent(force);
}

function toast(text) {
  const el = $("toast");
  el.textContent = text; el.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { el.hidden = true; }, 3500);
}

// ---- API for Swift ----
window.tarn = {
  setChrome(c) {
    const prevPath = activePath();
    chrome = c;
    document.documentElement.dataset.theme = c.dark ? "dark" : "light";
    if (prevPath !== activePath()) flushEdit();
    refreshAll(false);
  },
  setDoc(d) {
    const old = docs[d.path];
    docs[d.path] = d;
    if (d.kind !== "notice" && !modes[d.path]) modes[d.path] = "view";
    if (d.path === activePath()) {
      renderContent(d.reason === "revert" || !!(old && old.rev !== d.rev));
      if (d.reason === "external") {
        const el = $("vcontent").querySelector(".doc, .codeview");
        if (el) { el.classList.remove("flash"); void el.offsetWidth; el.classList.add("flash"); }
      }
    }
    renderTabs();
  },
  cmd(name) {
    const path = activePath();
    if (name === "mode") return setMode();
    if (name === "save" && path) { flushEdit(); post({ t: "save", path }); }
  },
  toast,
  flush() { flushEdit(); },
  focusTree() { const tree = $("vtree").querySelector(".tree"); if (tree) tree.focus(); },
  focusContent() {
    if (cm) return cm.view.focus();
    const box = $("vcontent");
    box.tabIndex = -1;
    box.focus();
  },
  setFocus(on) { $("app").classList.toggle("focus", !!on); },
};

function setMode(force) {
  const path = activePath();
  const doc = path && docs[path];
  if (!doc || doc.kind === "notice") return;
  if (force !== "view" && (modes[path] || "view") === "view") {
    modes[path] = "source";
  } else {
    flushEdit();
    modes[path] = "view";
  }
  lastKey = "";
  renderTabs();
  renderContent(true);
  window.tarn.focusContent();
}

// ---- events ----
document.addEventListener("click", e => {
  const el = e.target;
  const closeBtn = el.closest("[data-close]");
  if (closeBtn) { e.stopPropagation(); return post({ t: "closeTab", index: +closeBtn.dataset.close }); }
  const tab = el.closest(".ftab");
  if (tab) return post({ t: "tab", index: +tab.dataset.idx, pin: e.detail > 1 });
  const act = el.closest("[data-act]");
  if (act) {
    if (act.dataset.act === "mode") return setMode();
    if (act.dataset.act === "tree") return post({ t: "toggleTree" });
    if (act.dataset.act === "closePane") return post({ t: "closePane" });
  }
  const row = el.closest(".tr");
  if (row) {
    treeSel = row.dataset.path;
    if (row.dataset.kind === "dir") return post({ t: "treeToggle", path: row.dataset.path });
    return post({ t: "treeOpen", path: row.dataset.path, pin: e.detail > 1 });
  }
  const path = activePath();
  if (el.closest("[data-take]")) return post({ t: "take", path });
  if (el.closest("[data-keep]")) return post({ t: "keep", path });
  const copy = el.closest(".copy");
  if (copy) {
    post({ t: "copy", text: copy.parentElement.querySelector("code").textContent });
    copy.textContent = "Copied";
    setTimeout(() => { copy.textContent = "Copy"; }, 1200);
    return;
  }
  const tog = el.closest(".mtoggle");
  if (tog) {
    const box = tog.closest(".mm");
    const src = box.dataset.src;
    if (rawMm.has(src)) rawMm.delete(src); else rawMm.add(src);
    return void drawMermaid(box);
  }
  const link = el.closest("a[href]");
  if (link) {
    e.preventDefault();
    const href = link.getAttribute("href");
    if (href.startsWith("#")) {
      const target = document.getElementById("h-" + decodeURIComponent(href.slice(1)));
      if (target) target.scrollIntoView();
      return;
    }
    post({ t: "link", href, from: path });
  }
});

document.addEventListener("change", e => {
  const box = e.target.closest && e.target.closest("input[data-line]");
  if (!box) return;
  flushEdit();
  const path = activePath();
  post({ t: "task", path, rev: docs[path].rev, line: +box.dataset.line, checked: box.checked });
});

document.addEventListener("dragstart", e => {
  const tab = e.target.closest && e.target.closest(".ftab");
  if (tab) post({ t: "tab", index: +tab.dataset.idx, pin: true });
});

$("vtree").addEventListener("keydown", e => {
  const rows = chrome.tree.rows;
  if (!rows.length) return;
  let i = Math.max(0, rows.findIndex(r => r.path === treeSel));
  const move = d => { treeSel = rows[Math.min(rows.length - 1, Math.max(0, i + d))].path; renderTree(); e.preventDefault(); };
  const row = rows[i];
  if (e.key === "ArrowDown" || e.key === "j") move(1);
  else if (e.key === "ArrowUp" || e.key === "k") move(-1);
  else if (e.key === "ArrowRight" && row.kind === "dir" && !row.open) { post({ t: "treeToggle", path: row.path }); e.preventDefault(); }
  else if (e.key === "ArrowLeft" && row.kind === "dir" && row.open) { post({ t: "treeToggle", path: row.path }); e.preventDefault(); }
  else if (e.key === "ArrowLeft" && activePath()) { e.preventDefault(); window.tarn.focusContent(); }
  else if (e.key === "Enter") {
    e.preventDefault();
    if (row.kind === "dir") post({ t: "treeToggle", path: row.path });
    else post({ t: "treeOpen", path: row.path, pin: e.shiftKey || e.metaKey, enter: true });
  } else if (e.key === "Escape") { e.preventDefault(); post({ t: "hideTree" }); }
});

// View mode: the focused content box is not the scroller, so arrows scroll it here; Right goes to the tree.
$("vcontent").addEventListener("keydown", e => {
  if (cm || e.metaKey || e.ctrlKey || e.altKey) return;
  const sc = $("vcontent").querySelector(".scroll");
  const step = { ArrowDown: 40, ArrowUp: -40, PageDown: 0.9, PageUp: -0.9 }[e.key];
  if (step && sc) {
    e.preventDefault();
    sc.scrollBy(0, Math.abs(step) < 1 ? step * sc.clientHeight : step);
  } else if (e.key === "ArrowRight") {
    e.preventDefault();
    if (chrome.tree.visible) window.tarn.focusTree(); else post({ t: "toggleTree" });
  }
});

window.addEventListener("error", e => post({ t: "error", message: String(e.message), at: `${e.filename}:${e.lineno}` }));
window.addEventListener("unhandledrejection", e => post({ t: "error", message: String(e.reason) }));
window.addEventListener("focus", () => window.tarn.setFocus(true));
window.addEventListener("blur", () => { flushEdit(); window.tarn.setFocus(false); });
post({ t: "ready" });
