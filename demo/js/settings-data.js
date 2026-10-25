// What the settings window says about each Ghostty option: section, help text and when a change
// applies. Types, values and defaults come from OPTIONS in config.js. Order is the order of rows
// and of lines in the config file (GhosttyOption.swift in macos/Sources/Features/Tarn/).
export const SECTIONS = [
  ["tabs", "Tabs"],
  ["viewer", "File Viewer"],
  ["appearance", "Appearance"],
  ["terminal", "Terminal"],
  ["windows", "Windows"],
  ["help", "Help"],
];

const option = (key, help, applies) => ({ key, help, applies });

export const GHOSTTY = {
  appearance: [
    option("theme", "Color theme. The app lists the installed themes."),
    option("window-theme", "Window chrome: follow the system or the terminal colors."),
    option("font-family", "Empty uses the built-in JetBrains Mono. The file starts the list over, so this font replaces the one in your Ghostty config."),
    option("font-size", "Points. A terminal where you pressed cmd+= or cmd+- keeps its own size."),
    option("background-opacity", "Below 1 the desktop shows through.", "restart"),
    option("background-blur", "Blurs what shows through a transparent background. A radius or glass value in the file shows as text."),
    option("window-padding-x", "Space between the window edge and the text, in points.", "windows"),
    option("unfocused-split-opacity", "How much an unfocused split is dimmed."),
    option("cursor-style", "Shell integration shows a bar at the prompt."),
    option("cursor-style-blink", "Default follows the program (DEC mode 12); true or false forces it."),
    option("macos-titlebar-style", "How the title bar looks.", "windows"),
  ],
  terminal: [
    option("copy-on-select", "Copy selected text without cmd+C."),
    option("mouse-hide-while-typing", "Hide the pointer while typing."),
    option("clipboard-paste-protection", "Ask before pasting text that may run commands."),
    option("macos-option-as-alt", "Option sends Alt instead of special characters. Default: on for US layouts, off for others."),
    option("link-url", "Cmd+click opens URLs."),
    option("notify-on-command-finish", "Rings the bell when a command that ran over 5 seconds finishes while the window is not focused."),
  ],
  windows: [
    option("window-save-state", "Restore windows, tabs and splits on launch; default follows macOS."),
    option("confirm-close-surface", "Ask before closing a terminal with a running program."),
    option("window-inherit-working-directory", "A new tab or split starts in the focused tab's folder."),
    option("undo-timeout", "How long cmd+Z can bring back a closed pane or tab."),
    option("drag-handle", "The three dots that drag a pane: on hover, always or never."),
  ],
};

export const APPLIES = { restart: "Restart needed.", windows: "Applies to new windows." };

export const TAB_STYLES = [
  ["sidebar", "Sidebar", "Tabs grouped in workspaces with agent state, on the left of the window."],
  ["top", "Tabs at the top", "The native tab bar, as in Ghostty. Workspaces and agent state are not shown."],
];
