// The settings window: Tabs, three sections of Ghostty options, Help. Counterpart of
// TarnSettings.swift. A changed option always writes its line to tarn's own config file
// (shown under Windows); only Reset removes it.
import { bus } from "./bus.js";
import { read } from "./state.js";
import { OPTIONS, DEFAULTS, isWritten } from "./config.js";
import { SECTIONS, GHOSTTY, APPLIES, TAB_STYLES } from "./settings-data.js";
import { helpGroups, symbols } from "./settings-help.js";
import { esc } from "./esc.js";

const ALL = Object.values(GHOSTTY).flat();

let rows = [];
let root = null;
let section = "tabs";
let opener = null;
let replacing = false;
const problems = new Map(); // option key -> the line shown under a rejected input

function control(key) {
  const o = OPTIONS[key];
  const value = read("config")[key];
  const id = `g-${key}`;
  if (o.type === "bool") return `<input type="checkbox" id="${id}" data-gkey="${key}"${value ? " checked" : ""}>`;
  if (o.type === "enum") {
    const options = o.values.map((v) => `<option value="${v}"${value === v ? " selected" : ""}>${v || "default (auto)"}</option>`);
    return `<select id="${id}" data-gkey="${key}">${options.join("")}</select>`;
  }
  if (o.type === "number" && o.step < 1) {
    return `<input type="range" id="${id}" data-gkey="${key}" min="${o.min}" max="${o.max}" step="${o.step}" value="${value}"><span class="val">${value}</span>`;
  }
  const number = o.type === "number" ? ` min="${o.min}" max="${o.max}"` : "";
  return `<input type="${o.type === "number" ? "number" : "text"}" id="${id}" data-gkey="${key}" value="${esc(value)}"${number}>`;
}

function optionRow({ key, help, applies }) {
  const mark = isWritten(key)
    ? `<span class="set" title="Set here; overrides the same line in the Ghostty config">set in tarn</span><button class="reset" data-greset="${key}">Reset</button>`
    : "";
  const note = APPLIES[applies] ? `<small class="applies">${APPLIES[applies]}</small>` : "";
  const problem = problems.has(key) ? `<small class="err">${esc(problems.get(key))}</small>` : "";
  return `<div class="opt" data-opt="${key}"><label for="g-${key}">${key}</label><span class="ctl">${mark}${control(key)}</span><small>${esc(help)}</small>${note}${problem}</div>`;
}

// The lines tarn writes: a repeatable option such as font-family first clears the list.
export function configLines() {
  const config = read("config");
  const lines = ALL.filter((o) => isWritten(o.key)).flatMap(({ key }) => {
    const value = config[key];
    const line = `${key} = ${value === "" ? '""' : value}`;
    return key === "font-family" && value !== "" ? [`${key} = ""`, line] : [line];
  });
  return lines.length ? lines.join("\n") : "# empty: every value comes from the Ghostty config";
}

function optionSection(name, title) {
  const tail = name === "windows"
    ? `<p class="setnote">Written to <code>~/.config/tarn/ghostty.conf</code>, loaded after your Ghostty config:</p><pre id="tarnConf">${esc(configLines())}</pre><p class="setnote"><button class="act" id="resetDemo">Reset demo</button> Forgets the layout, files, history and settings kept in this browser.</p>`
    : `<p class="setnote">Ghostty options. Others, keys included, are in Ghostty Config.</p>`;
  return `<section data-pane="${name}" hidden><h3>${title}</h3><div class="setgroup">${GHOSTTY[name].map(optionRow).join("")}</div>${tail}</section>`;
}

function tabsSection() {
  const style = read("config")["tab-style"];
  const radios = TAB_STYLES.map(([value, name, text]) =>
    `<label><input type="radio" name="tabstyle" value="${value}"${style === value ? " checked" : ""}><span><b>${name}</b><small>${text}</small></span></label>`);
  return `<section data-pane="tabs"><h3>Tabs</h3><div class="setgroup"><div class="setrow"><span>Tab style</span><div class="radios">${radios.join("")}</div></div></div><p class="setnote">Applies to every open window at once.</p></section>`;
}

function viewerSection() {
  const on = read("config")["file-viewer"];
  return `<section data-pane="viewer" hidden><h3>File Viewer</h3><div class="setgroup"><div class="setrow"><label for="g-file-viewer">File viewer<small>Cmd+B, path clicks and agents open files in a pane beside the terminal. When off, path clicks open files in their default app; an open pane stays until you close it.</small></label><input type="checkbox" id="g-file-viewer" data-gkey="file-viewer"${on ? " checked" : ""}></div></div></section>`;
}

function helpSection() {
  const tables = helpGroups(rows).map(({ name, lines }) => {
    const body = lines.map((l) => `<tr><td>${esc(l.chords.map(symbols).join(" "))}</td><td class="alt">${esc(l.alt.join(" "))}</td><td>${esc(l.text)}</td><td class="src">${l.src}</td></tr>`);
    return `<h4>${esc(name)}</h4><div class="setgroup"><table class="keys"><tr><th>Keys</th><th>If the browser keeps them</th><th></th><th></th></tr>${body.join("")}</table></div>`;
  });
  return `<section data-pane="help" hidden><h3>Help</h3>${tables.join("")}<p class="setnote">Ghostty defaults. A <code>keybind</code> line in the Ghostty config changes them, and the app shows the keys in effect. Where a browser keeps a chord for itself, use the Ctrl+Alt form.</p></section>`;
}

function build() {
  const nav = SECTIONS.map(([name, title]) => `<button class="setitem" data-sec="${name}">${title}</button>`).join("");
  const sections = tabsSection() + viewerSection() + ["appearance", "terminal", "windows"].map((n) => optionSection(n, SECTIONS.find(([k]) => k === n)[1])).join("") + helpSection();
  root.innerHTML = `<div class="setwin" role="dialog" aria-modal="true" aria-label="Settings"><div class="setside"><div class="lights"><i id="settingsClose" title="Close"></i><i></i><i></i></div><nav id="setNav" aria-label="Settings sections">${nav}</nav><button class="setcfg" id="ghosttyConfig" title="All Ghostty options, keys included. Opens the Ghostty config file.">Ghostty Config…</button></div><div class="setmain" id="setMain">${sections}</div></div>`;
}

function show(name) {
  section = name;
  root.querySelectorAll("#setNav [data-sec]").forEach((b) => b.classList.toggle("on", b.dataset.sec === name));
  root.querySelectorAll("#setMain [data-pane]").forEach((s) => { s.hidden = s.dataset.pane !== name; });
}

function open({ section: name } = {}) {
  if (!root.hidden) return;
  opener = document.activeElement;
  build();
  show(name ?? section);
  root.hidden = false;
  const pane = root.querySelector(`[data-pane="${section}"]`);
  (pane.querySelector("input, select") ?? root.querySelector("#setNav")).focus();
}

function close() {
  root.hidden = true;
  if (opener?.isConnected) opener.focus();
}

// An option row after a change: the Set mark, Reset and the file text follow the config.
function refreshRow(key) {
  const row = root.querySelector(`[data-opt="${key}"]`);
  const option = ALL.find((o) => o.key === key);
  if (row && option) {
    const next = document.createElement("template");
    next.innerHTML = optionRow(option);
    replacing = true; // removing a focused field fires its change event once more
    row.replaceWith(next.content);
    replacing = false;
  }
  const conf = root.querySelector("#tarnConf");
  if (conf) conf.textContent = configLines();
}

function onChange(e) {
  if (replacing) return;
  const key = e.target.dataset?.gkey;
  if (key) {
    const o = OPTIONS[key];
    let value = e.target.type === "checkbox" ? e.target.checked : e.target.value;
    if (o.type === "number") {
      value = Number(value);
      const whole = Number.isInteger(o.step);
      if (e.target.value === "" || Number.isNaN(value) || value < o.min || value > o.max || (whole && !Number.isInteger(value))) {
        problems.set(key, `Enter ${whole ? "a whole number" : "a number"} from ${o.min} to ${o.max}.`);
        return refreshRow(key);
      }
    }
    problems.delete(key);
    return bus.cmd("config.set", { key, value });
  }
  if (e.target.name === "tabstyle") bus.cmd("config.set", { key: "tab-style", value: e.target.value });
}

function onClick(e) {
  if (e.target === root || e.target.closest("#settingsClose")) return close();
  if (e.target.closest("#resetDemo")) return bus.cmd("demo.reset");
  if (e.target.closest("#ghosttyConfig")) return bus.emit("toast", { text: "Opens the Ghostty config file" });
  const nav = e.target.closest("#setNav [data-sec]");
  if (nav) return show(nav.dataset.sec);
  const reset = e.target.closest("[data-greset]");
  if (!reset) return;
  problems.delete(reset.dataset.greset);
  bus.cmd("config.reset", { key: reset.dataset.greset });
  refreshRow(reset.dataset.greset);
}

// Reload the Ghostty config: every option applies again from the stored values.
function reload() {
  const config = read("config");
  for (const key of Object.keys(DEFAULTS)) bus.emit("config:changed", { key, value: config[key] });
  bus.emit("toast", { text: "config reloaded" });
}

export const settingsOpen = () => root !== null && !root.hidden;

// `keyRows`: all key rows of the demo, for the Help section.
export function startSettings(keyRows) {
  rows = keyRows;
  root = document.createElement("div");
  root.id = "settings";
  root.className = "setwrap";
  root.hidden = true;
  document.getElementById("window").append(root);
  root.addEventListener("click", onClick);
  root.addEventListener("change", onChange);
  root.addEventListener("input", (e) => {
    if (e.target.type === "range") e.target.nextElementSibling.textContent = e.target.value;
  });
  document.addEventListener("keydown", (e) => {
    const closeKey = e.key === "Escape" || (e.code === "KeyW" && (e.metaKey || (e.ctrlKey && e.altKey)));
    if (!closeKey || root.hidden) return;
    e.stopImmediatePropagation();
    close();
  }, true);
  bus.on("config:changed", ({ key }) => { if (!root.hidden) refreshRow(key); });
  bus.handle("settings.open", open);
  bus.handle("config.reload", reload);
}
