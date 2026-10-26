// Effects of the options no pane or layout owns: window theme, transparency, pointer hiding and
// window state. Pane and layout options are applied by their modules from `config:changed`.
import { bus } from "./bus.js";
import { read } from "./state.js";
import { drop } from "./storage.js";
import { themeFor } from "./themes.js";
import { isLight } from "./color.js";
import { deriveChrome, paint, PAGE_VARS } from "./chrome-theme.js";

const root = document.documentElement;
const dark = matchMedia("(prefers-color-scheme: dark)");

// The window colors, or null when a forced light or dark window uses the built-in palettes.
let colors = null;
export const windowColors = () => colors;

// `auto` and `ghostty` take the window from the terminal theme (Ghostty's `auto` also reads the
// background lightness); `system`, `light` and `dark` use the built-in palettes.
function windowTheme() {
  const config = read("config"), mode = config["window-theme"], theme = themeFor(config.theme);
  const fromTheme = mode === "auto" || mode === "ghostty";
  const light = fromTheme ? isLight(theme.background) : mode === "light" || (mode === "system" && !dark.matches);
  root.dataset.theme = light ? "light" : "dark";
  colors = fromTheme ? deriveChrome(theme) : null;
  paint(root, PAGE_VARS, colors);
  bus.emit("chrome:changed", { colors });
}

const effects = {
  "window-theme": windowTheme,
  theme: windowTheme,
  "background-opacity": (value) => root.style.setProperty("--bg-alpha", value),
  "background-blur": (value) => root.style.setProperty("--bg-blur", value ? "20px" : "0px"),
  "mouse-hide-while-typing": (value) => { root.dataset.hideMouse = value ? "on" : "off"; },
};

export function startEffects() {
  const config = read("config");
  for (const [key, apply] of Object.entries(effects)) apply(config[key]);
  bus.on("config:changed", ({ key, value }) => effects[key]?.(value));
  dark.addEventListener("change", windowTheme);

  // Typing hides the pointer until it moves; plain modifier keys do not count as typing.
  document.addEventListener("keydown", (e) => {
    if (root.dataset.hideMouse === "on" && !e.metaKey && !e.ctrlKey) root.dataset.typing = "on";
  }, true);
  document.addEventListener("pointermove", () => { root.dataset.typing = "off"; }, true);

  addEventListener("pagehide", () => {
    if (read("config")["window-save-state"] === "never") drop("workspaces");
  });
}
