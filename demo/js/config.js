// Options of the demo, named and valued as the Ghostty config keys (src/config/Config.zig).
// Counterpart of TarnSettings.swift. Single writer of the `config` part; effects live in the
// modules that subscribe to `config:changed`.
import { bus } from "./bus.js";
import { register, read } from "./state.js";
import { isObject, load, save } from "./storage.js";
import { THEME_NAMES } from "./themes.js";

const bool = (def) => ({ def, type: "bool" });
const num = (def, min, max, step = 1) => ({ def, type: "number", min, max, step });
const pick = (def, values) => ({ def, type: "enum", values });

export const OPTIONS = Object.freeze({
  theme: pick("", ["", ...THEME_NAMES]),
  "window-theme": pick("auto", ["auto", "system", "light", "dark", "ghostty"]),
  "font-family": { def: "", type: "text" },
  "font-size": num(13, 6, 32),
  "background-opacity": num(1, 0.3, 1, 0.05),
  "background-blur": bool(false),
  "window-padding-x": num(2, 0, 40),
  "unfocused-split-opacity": num(0.7, 0.15, 1, 0.05),
  "cursor-style": pick("block", ["block", "bar", "underline"]),
  "cursor-style-blink": pick("", ["", "true", "false"]),
  "macos-titlebar-style": pick("transparent", ["transparent", "native", "hidden"]),
  "copy-on-select": pick("none", ["none", "clipboard"]),
  "mouse-hide-while-typing": bool(false),
  "clipboard-paste-protection": bool(true),
  "macos-option-as-alt": pick("", ["", "false", "true", "left", "right"]),
  "link-url": bool(true),
  "notify-on-command-finish": pick("never", ["never", "unfocused", "always"]),
  "window-save-state": pick("default", ["default", "never", "always"]),
  "confirm-close-surface": pick("true", ["false", "true", "always"]),
  "window-inherit-working-directory": bool(true),
  "undo-timeout": pick("5s", ["0s", "5s", "10s", "30s"]),
  "drag-handle": pick("auto", ["always", "auto", "never"]),
  "tab-style": pick("sidebar", ["sidebar", "top"]),
  "file-viewer": bool(true),
});

export const DEFAULTS = Object.freeze(Object.fromEntries(Object.entries(OPTIONS).map(([k, o]) => [k, o.def])));

function valid(key, value) {
  const o = OPTIONS[key];
  if (!o) return false;
  if (o.type === "bool") return typeof value === "boolean";
  if (o.type === "number") return typeof value === "number" && value >= o.min && value <= o.max;
  if (o.type === "enum") return o.values.includes(value);
  return typeof value === "string";
}

// Keys whose line is in tarn's own config file: a set writes the line (the empty "default (auto)"
// entry writes an empty value), only a reset removes it.
let written = new Set();
export const isWritten = (key) => written.has(key);
export const writtenKeys = () => [...written];

export function startConfig() {
  const stored = load("config", {}, isObject);
  const initial = { ...DEFAULTS };
  for (const [key, value] of Object.entries(stored)) if (valid(key, value)) initial[key] = value;
  written = new Set(load("config-written", [], Array.isArray).filter((key) => key in OPTIONS));
  const write = register("config", initial);

  const persistWritten = () => save("config-written", [...written]);

  const set = (key, value, { reset = false } = {}) => {
    if (!valid(key, value)) throw new Error(`bad config value: ${key}=${JSON.stringify(value)}`);
    const next = { ...read("config"), [key]: value };
    write(next);
    save("config", next);
    if (reset) written.delete(key);
    else written.add(key);
    persistWritten();
    bus.emit("config:changed", { key, value });
  };

  bus.handle("config.set", ({ key, value }) => set(key, value));
  // One key with `{key}`, every key without a payload.
  bus.handle("config.reset", (payload) => {
    for (const key of payload?.key ? [payload.key] : Object.keys(DEFAULTS)) {
      if (read("config")[key] !== DEFAULTS[key]) set(key, DEFAULTS[key], { reset: true });
      else if (written.delete(key)) persistWritten();
    }
  });
}
