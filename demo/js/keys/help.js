// Key rows of the settings window.
const row = (id, chords, text, cmd, alt) =>
  ({ id, chords, alt, when: "any", group: "Terminal", src: "Ghostty", text, cmd });

export const helpKeys = [
  row("settings.open", ["Cmd+,"], "Settings", "settings.open", ["Ctrl+Alt+,"]),
  row("config.reload", ["Cmd+Shift+,"], "Reload the Ghostty config", "config.reload", ["Ctrl+Alt+Shift+,"]),
];
