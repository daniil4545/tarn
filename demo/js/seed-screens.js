// What the seeded panes show when the demo opens, and who runs in them.
import { crlf, dim, green, magenta } from "./shell/ansi.js";

const tool = (name, arg) => `${magenta(`● ${name}`)}(${arg})`;
const claudeHead = dim("╭─ Claude Code ─────────────────────────╮");

const AGENT_SCREENS = {
  p1: [
    claudeHead,
    `${green(">")} update the spec and the plan for the viewer`,
    "",
    tool("Update", "docs/spec.md"),
    tool("Write", "docs/plans/s2-files.md"),
    tool("Read", "macos/Sources/Features/Tarn/Sidebar.swift:9"),
    "",
    "Done. Changes:",
    "- docs/spec.md: R6 and the network rule",
    "- docs/plans/s2-files.md: stage steps",
    "- docs/architecture.md: viewer module",
    "- macos/Sources/Features/Tarn/Sidebar.swift:9: insertion point",
    "",
  ],
  p2: [
    `${green(">")} check the README`,
    "",
    tool("Read", "README.md"),
    "",
    "The README is fine. The module map in docs/architecture.md matches the code.",
    "",
    dim("✻ Working… (esc to interrupt)"),
  ],
  p5: [
    `${green(">")} fix the navigation links on the website`,
    "",
    tool("Edit", "src/nav.js"),
    "",
    dim("✻ Working… (esc to interrupt)"),
  ],
};

// Panes that run a remote login instead of the local shell.
const REMOTE = { user: "root", host: "staging", home: "/root", start: "/root", remote: true };

// Returns {text, agent, identity?}: text is written before the shell starts; `agent` means a
// claude session is already open there.
export function seedScreen(paneId, { prompt, identity }) {
  const agent = AGENT_SCREENS[paneId];
  if (agent) return { text: `${crlf(agent.join("\n"))}\r\n`, agent: true, identity };
  if (paneId === "p3") {
    const status = ` M docs/spec.md\n M macos/Sources/Features/Tarn/TarnSettings.swift`;
    return { text: `${prompt} git status -s\r\n${crlf(status)}\r\n`, agent: false, identity };
  }
  if (paneId === "p4") {
    return {
      text: `${prompt} ssh staging\r\n${dim("Welcome to Ubuntu 24.04 LTS")}\r\n`,
      agent: false,
      identity: REMOTE,
    };
  }
  return { text: `${dim("Last login: Sun Oct 25 12:34:44 on ttys001")}\r\n`, agent: false, identity };
}
