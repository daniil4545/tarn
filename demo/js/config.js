// Options of the demo, named and valued as the Ghostty config keys (src/config/Config.zig).
// Counterpart of TarnSettings.swift. Single writer of the `config` part; effects live in the
// modules that subscribe to `config:changed`.
import { bus } from "./bus.js";
import { register, read } from "./state.js";
import { load, save } from "./storage.js";

const bool = (def) => ({ def, type: "bool" });
const num = (def, min, max, step = 1) => ({ def, type: "number", min, max, step });
const pick = (def, values) => ({ def, type: "enum", values });

export const OPTIONS = Object.freeze({
  theme: pick("ghostty", ["ghostty", "dracula", "catppuccin-mocha", "nord"]),
  "window-theme": pick("auto", ["auto", "system", "light", "dark", "ghostty"]),
  "font-family": { def: "JetBrains Mono", type: "text" },
  "font-size": num(13, 8, 32),
  "background-opacity": num(1, 0.2, 1, 0.05),
  "background-blur": num(0, 0, 40),
  "window-padding-x": num(2, 0, 40),
  "unfocused-split-opacity": num(0.7, 0.15, 1, 0.05),
  "cursor-style": pick("block", ["block", "bar", "underline"]),
  "cursor-style-blink": bool(true),
  "macos-titlebar-style": pick("transparent", ["native", "transparent", "tabs", "hidden"]),
  "copy-on-select": bool(true),
  "mouse-hide-while-typing": bool(false),
  "clipboard-paste-protection": bool(true),
  "macos-option-as-alt": bool(false),
  "link-url": bool(true),
  "notify-on-command-finish": pick("never", ["never", "unfocused", "always"]),
  "window-save-state": pick("default", ["default", "never", "always"]),
  "confirm-close-surface": pick("true", ["false", "true", "always"]),
  "window-inherit-working-directory": bool(true),
  "undo-timeout": num(5, 0, 60),
  "drag-handle": pick("auto", ["always", "auto", "never"]),
  "tab-style": pick("sidebar", ["sidebar", "top"]),
});

export const DEFAULTS = Object.freeze(Object.fromEntries(Object.entries(OPTIONS).map(([k, o]) => [k, o.def])));

function valid(key, value) {
  const o = OPTIONS[key];
  if (!o) return false;
  if (o.type === "bool") return typeof value === "boolean";
  if (o.type === "number") return typeof value === "number" && value >= o.min && value <= o.max;
  if (o.type === "enum") return o.values.includes(value);
  return typeof value === "string" && value.length > 0;
}

export function startConfig() {
  const stored = load("config", {});
  const initial = { ...DEFAULTS };
  for (const [key, value] of Object.entries(stored)) if (valid(key, value)) initial[key] = value;
  const write = register("config", initial);

  const set = (key, value) => {
    if (!valid(key, value)) throw new Error(`bad config value: ${key}=${JSON.stringify(value)}`);
    const next = { ...read("config"), [key]: value };
    write(next);
    save("config", next);
    bus.emit("config:changed", { key, value });
  };

  bus.handle("config.set", ({ key, value }) => set(key, value));
  bus.handle("config.reset", () => {
    for (const [key, value] of Object.entries(DEFAULTS)) if (read("config")[key] !== value) set(key, value);
  });
}
