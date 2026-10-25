// Terminal color themes of the `theme` option. Palettes come from the iTerm2-Color-Schemes set
// that ships with Ghostty (MIT, https://github.com/mbadolato/iTerm2-Color-Schemes).
const names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];

// colors: 16 hex strings, normal then bright.
function theme(background, foreground, cursor, selectionBackground, colors) {
  const palette = {};
  names.forEach((n, i) => {
    palette[n] = colors[i];
    palette[`bright${n[0].toUpperCase()}${n.slice(1)}`] = colors[i + 8];
  });
  return { background, foreground, cursor, cursorAccent: background, selectionBackground, selectionForeground: foreground, ...palette };
}

export const THEMES = {
  ghostty: theme("#282c34", "#ffffff", "#c5c8c6", "#4a5160", [
    "#1d1f21", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb", "#8abeb7", "#c5c8c6",
    "#666666", "#d54e53", "#b9ca4a", "#e7c547", "#7aa6da", "#c397d8", "#70c0b1", "#eaeaea",
  ]),
  dracula: theme("#282a36", "#f8f8f2", "#f8f8f2", "#44475a", [
    "#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
    "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff",
  ]),
  "catppuccin-mocha": theme("#1e1e2e", "#cdd6f4", "#f5e0dc", "#585b70", [
    "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8",
    "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
  ]),
  nord: theme("#2e3440", "#d8dee9", "#d8dee9", "#4c566a", [
    "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
    "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4",
  ]),
};

// The default theme is the empty name, as in the Ghostty config.
export const themeFor = (name) => THEMES[name || "ghostty"];
