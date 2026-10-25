// Effects of the options no pane or layout owns: window theme, transparency, pointer hiding and
// window state. Pane and layout options are applied by their modules from `config:changed`.
import { bus } from "./bus.js";
import { read } from "./state.js";
import { drop } from "./storage.js";

const root = document.documentElement;
const dark = matchMedia("(prefers-color-scheme: dark)");

// Every theme shipped with the demo is dark, so "ghostty" (follow the terminal) is dark.
function windowTheme(value) {
  const light = value === "light" || ((value === "auto" || value === "system") && !dark.matches);
  root.dataset.theme = light ? "light" : "dark";
}

const effects = {
  "window-theme": windowTheme,
  "background-opacity": (value) => root.style.setProperty("--bg-alpha", value),
  "background-blur": (value) => root.style.setProperty("--bg-blur", value ? "20px" : "0px"),
  "mouse-hide-while-typing": (value) => { root.dataset.hideMouse = value ? "on" : "off"; },
};

export function startEffects() {
  const config = read("config");
  for (const [key, apply] of Object.entries(effects)) apply(config[key]);
  bus.on("config:changed", ({ key, value }) => effects[key]?.(value));
  dark.addEventListener("change", () => windowTheme(read("config")["window-theme"]));

  // Typing hides the pointer until it moves; plain modifier keys do not count as typing.
  document.addEventListener("keydown", (e) => {
    if (root.dataset.hideMouse === "on" && !e.metaKey && !e.ctrlKey) root.dataset.typing = "on";
  }, true);
  document.addEventListener("pointermove", () => { root.dataset.typing = "off"; }, true);

  addEventListener("pagehide", () => {
    if (read("config")["window-save-state"] === "never") drop("workspaces");
  });
}
