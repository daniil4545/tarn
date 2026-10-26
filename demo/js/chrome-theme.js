// Window colors taken from the terminal theme: the sidebar, title bar, menus and the viewer use
// the theme's background and text, and one accent from its palette. Same rule for every theme,
// so nothing is hand-tuned per theme:
//   surface (sidebar, title bar)  background mixed 6% toward the text color
//   menu                          background mixed 10% toward the text color
//   line                          background mixed 16% toward the text color
//   divider                       background mixed toward black (22% on light, 45% on dark)
//   muted, key                    text color mixed 38% and 55% toward the background; muted mixes
//                                 less where 38% falls below contrast 4.5:1 (light themes)
//   accent                        the first of palette blue, bright blue, cyan, magenta that has
//                                 contrast 3:1 against the background; else the text color
import { mix, contrast, isLight } from "./color.js";

// The text color faded toward the background by `amount`, or less if that drops below `floor`.
export function fade(fg, bg, amount, floor) {
  let a = amount;
  while (a > 0 && contrast(mix(fg, bg, a), bg) < floor) a = Math.max(0, a - 0.02);
  return mix(fg, bg, a);
}

export function pickAccent(t) {
  return [t.blue, t.brightBlue, t.cyan, t.magenta].find((c) => contrast(c, t.background) >= 3) ?? t.foreground;
}

// Every color the window needs, as "#rrggbb", for a theme object of themes.js.
export function deriveChrome(t) {
  const bg = t.background, fg = t.foreground;
  return {
    light: isLight(bg),
    bg,
    fg,
    chrome: mix(bg, fg, 0.06),
    menu: mix(bg, fg, 0.1),
    line: mix(bg, fg, 0.16),
    div: mix(bg, "#000000", isLight(bg) ? 0.22 : 0.45),
    muted: fade(fg, bg, 0.38, 4.5),
    key: mix(fg, bg, 0.55),
    code: mix(bg, fg, 0.05),
    accent: pickAccent(t),
  };
}

// Root custom properties of the page (css/chrome.css, css/base.css) and the viewer page
// (viewer/tarn-viewer.css) that the derived colors replace.
export const PAGE_VARS = { "--bg": "bg", "--fg": "fg", "--dim": "muted", "--chrome": "chrome", "--menu": "menu", "--line": "line", "--div": "div", "--muted": "muted", "--key": "key", "--accent": "accent" };
export const VIEWER_VARS = { "--p-bg": "bg", "--p-bar": "chrome", "--p-fg": "fg", "--p-muted": "muted", "--p-line": "line", "--p-code": "code", "--p-accent": "accent" };

export function paint(el, vars, colors) {
  for (const [name, key] of Object.entries(vars)) {
    if (colors) el.style.setProperty(name, colors[key]);
    else el.style.removeProperty(name);
  }
}
