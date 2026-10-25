// One terminal pane: engine, simulated shell, links, paste guard. Counterpart of a Ghostty surface.
// A pane is created once and keeps its instance across reparenting and undo; dispose() frees it.
import { bus } from "./bus.js";
import { read } from "./state.js";
import { clock } from "./clock.js";
import { hooks } from "./test-contract.js";
import { createTerm } from "./term-adapter.js";
import { createShell } from "./shell/shell.js";
import { buildPrompt, tilde } from "./shell/prompt.js";
import { sessionRows } from "./session-rows.js";
import { seedScreen } from "./seed-screens.js";
import { addPaneLinks } from "./pane-links.js";
import { guardPaste } from "./paste-guard.js";
import { themeFor } from "./themes.js";
import { ENGINE_KEYS, effectiveSize, engineOptions, optionAsAlt, copyOnSelect } from "./pane-options.js";
import { HOME } from "./vfs-seed.js";
import { load, save } from "./storage.js";

const LOCAL = { user: "daniil", host: "MacBook", home: HOME };
const LONG_COMMAND_MS = 3000;
const HISTORY_LIMIT = 200;

const panes = new Map();
let vfs;
let focusedId = null;
const history = [];

export const getPane = (id) => panes.get(id);

function startDirectory(cwd) {
  const path = vfs.resolve(HOME, cwd.startsWith("~") ? HOME + cwd.slice(1) : cwd);
  return vfs.isDir(path) ? path : HOME;
}

export function createPane(id, { cwd }) {
  const el = document.createElement("div");
  el.className = "pane";
  el.dataset.pane = id;
  const host = document.createElement("div");
  host.className = "pane-term";
  el.append(host);

  let term = null;
  let shell = null;
  let identity = LOCAL;
  let adjust = 0;
  let urlLinks = read("config")["link-url"];
  const marks = [];
  const subs = [];
  const sub = (off) => subs.push(off);

  const pane = {
    id,
    el,
    get term() { return term; },
    get cwd() { return shell ? tilde(shell.cwd, identity.home) : cwd; },
    get busy() { return shell?.busy ?? null; },
    focus: () => term?.focus(),
    screenText: () => term?.screenText() ?? "",
    applyConfig,
    adjustFont,
    clear: () => shell?.clear(true),
    answer: (allow) => shell?.answer(allow),
    jumpPrompt,
    dispose() {
      subs.forEach((off) => off());
      shell?.dispose();
      term?.dispose();
      el.remove();
      panes.delete(id);
      bus.emit("pane:disposed", { pane: id });
    },
  };

  el.addEventListener("focusin", () => {
    focusedId = id;
    bus.emit("pane:focused", { pane: id });
  });
  el.addEventListener("keydown", () => el.classList.add("typing"), true);
  el.addEventListener("mousemove", () => el.classList.remove("typing"));

  function write(data) {
    term.write(data);
    bus.emit("pane:output", { id });
  }

  function onShellEvent(name, data) {
    switch (name) {
      case "prompt":
        marks.push(term.cursorRow);
        history.splice(0, history.length - HISTORY_LIMIT);
        save("history", history);
        break;
      case "prompt-reset": marks.length = 0; break;
      case "cwd": bus.emit("pane:cwd", { pane: id, cwd: data.cwd }); break;
      case "exit": bus.cmd("pane.close", { id, exited: true }); break;
      case "viewer.open": bus.cmd("viewer.open", { ...data, pane: id }); break;
      case "tab.new": bus.cmd("tab.new", { pane: id, cwd: pane.cwd, focus: false }); break;
      case "hook": bus.cmd("hook", { pane: id, ...data }); break;
      case "command": notifyWhenDone(data); break;
      default: throw new Error(`unknown shell event: ${name}`);
    }
  }

  // notify-on-command-finish: a long command that ends where the user is not looking.
  function notifyWhenDone({ name, ms }) {
    const mode = read("config")["notify-on-command-finish"];
    const away = focusedId !== id || document.hidden;
    if (ms >= LONG_COMMAND_MS && (mode === "always" || (mode === "unfocused" && away))) {
      bus.emit("toast", { text: `${name} finished in ${Math.round(ms / 1000)} s` });
    }
  }

  function jumpPrompt(dir) {
    const rows = marks.filter((r) => term.lineText(r).startsWith(`${identity.user}@`));
    const top = term.topRow;
    const target = dir < 0 ? rows.filter((r) => r < top).at(-1) : rows.find((r) => r > top);
    term.scrollToRow(target ?? (dir < 0 ? 0 : term.lineCount));
  }

  async function adjustFont(op) {
    adjust = op === "reset" ? 0 : adjust + (op === "bigger" ? 1 : -1);
    await term.setOption("fontSize", effectiveSize(read("config"), adjust));
  }

  function applyConfig(key, value) {
    if (!term) return undefined;
    if (ENGINE_KEYS[key]) return term.setOption(ENGINE_KEYS[key], engineOptions(read("config"), adjust)[ENGINE_KEYS[key]]);
    switch (key) {
      case "window-padding-x": return term.fit();
      case "macos-option-as-alt": term.optionAsAlt = optionAsAlt(value); return undefined;
      case "copy-on-select": term.copyOnSelect = copyOnSelect(value); return undefined;
      case "link-url": urlLinks = value; return undefined;
      default: return undefined;
    }
  }

  async function boot() {
    const config = read("config");
    term = await createTerm(host, engineOptions(config, adjust));
    term.optionAsAlt = optionAsAlt(config["macos-option-as-alt"]);
    term.copyOnSelect = copyOnSelect(config["copy-on-select"]);
    addPaneLinks(term, {
      vfs,
      cwd: () => shell?.cwd ?? startDirectory(cwd),
      home: HOME,
      openFile: (path, line) => bus.cmd("viewer.open", { path, line, pane: id }),
      urlEnabled: () => urlLinks,
    });
    guardPaste(el, { enabled: () => read("config")["clipboard-paste-protection"], paste: (t) => term.paste(t) });
  }

  // The shell starts when the pane first has a size, so a hidden tab prints at its real width.
  async function start() {
    await new Promise((resolve) => {
      const watch = new ResizeObserver(() => {
        if (host.clientWidth > 0 && host.clientHeight > 0) { watch.disconnect(); resolve(); }
      });
      watch.observe(host);
      sub(() => watch.disconnect());
    });
    term.fit();
    const local = { ...LOCAL, start: startDirectory(cwd) };
    const seeded = seedScreen(id, {
      prompt: buildPrompt({ identity: LOCAL, cwd: local.start, branch: vfs.gitBranch(local.start) }),
      identity: local,
    });
    identity = seeded.identity;
    write(seeded.text);
    shell = createShell({
      vfs,
      clock,
      history,
      identity,
      write,
      emit: onShellEvent,
      cols: () => term.cols,
      sessions: () => sessionRows({
        workspaces: read("workspaces"),
        registry: read("registry"),
        vfs,
        home: HOME,
        now: clock.now,
      }),
      paneId: id,
    });
    sub(term.onData((d) => shell.input(d)));
    shell.start({ resume: seeded.agent });
  }

  panes.set(id, pane);
  pane.ready = boot();
  pane.started = pane.ready.then(start);
  return pane;
}

// Wires the module to the bus; `disk` is the vfs from startVfs().
export function startPanes({ vfs: disk }) {
  vfs = disk;
  history.push(...load("history", []));
  const target = (payload) => panes.get(payload.id ?? focusedId);

  bus.handle("term.clear", (p) => target(p)?.clear());
  bus.handle("term.font", (p) => target(p)?.adjustFont(p.op));
  bus.handle("term.prompt", (p) => target(p)?.jumpPrompt(p.dir));
  bus.handle("card.answer", ({ pane, allow }) => panes.get(pane)?.answer(allow));

  // Window-level effects of pane options; panes apply their own in applyConfig.
  const root = document.documentElement;
  const windowEffects = {
    theme: (v) => {
      root.style.setProperty("--term-bg", themeFor(v).background);
      root.style.setProperty("--term-fg", themeFor(v).foreground);
    },
    "window-padding-x": (v) => root.style.setProperty("--pad-x", `${v}px`),
    "mouse-hide-while-typing": (v) => root.classList.toggle("hide-mouse-typing", v),
  };
  const config = read("config");
  for (const [key, apply] of Object.entries(windowEffects)) apply(config[key]);
  bus.on("config:changed", ({ key, value }) => {
    windowEffects[key]?.(value);
    panes.forEach((p) => p.applyConfig(key, value));
  });

  hooks.screen = (id) => panes.get(id).screenText();
  hooks.term = (id) => panes.get(id).term;
  hooks.linkAt = (id, text) => {
    const t = panes.get(id).term;
    for (let y = 0; y < t.rows; y++) {
      const x = t.lineText(t.topRow + y).indexOf(text);
      if (x >= 0) return t.cellCentre(x + Math.floor(text.length / 2), y);
    }
    return null;
  };
}
