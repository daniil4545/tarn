// Key rows of the terminal pane. Counterpart of Ghostty's menu bindings for clear_screen,
// increase_font_size and jump_to_prompt. Fallbacks are Ctrl+Alt plus the same key; Ctrl+Alt+Up and Down belong to split focus, so the
// prompt jumps use Page Up and Page Down.
const row = (id, chords, text, cmd, payload, alt = chords.map((c) => c.replace("Cmd+", "Ctrl+Alt+"))) => ({
  id,
  chords,
  alt,
  when: "terminal",
  group: "Terminal",
  text,
  cmd,
  payload,
});

export const TERMINAL_KEYS = [
  row("terminal.clear", ["Cmd+K"], "Clear the screen", "term.clear", {}),
  row("terminal.font-bigger", ["Cmd+="], "Font size bigger", "term.font", { op: "bigger" }),
  row("terminal.font-smaller", ["Cmd+-"], "Font size smaller", "term.font", { op: "smaller" }),
  row("terminal.font-reset", ["Cmd+0"], "Font size reset", "term.font", { op: "reset" }),
  row("terminal.prompt-previous", ["Cmd+Up"], "Jump to the previous prompt", "term.prompt", { dir: -1 }, ["Ctrl+Alt+PageUp"]),
  row("terminal.prompt-next", ["Cmd+Down"], "Jump to the next prompt", "term.prompt", { dir: 1 }, ["Ctrl+Alt+PageDown"]),
];
