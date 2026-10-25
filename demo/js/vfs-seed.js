// Start content of the virtual disk. Paths of the tarn repository are relative to REPO.
// Files are the ones the viewer shows; `DIRTY` are files git reports as modified at start.
export const HOME = "/Users/daniil";
export const REPO = `${HOME}/Dev/self-projects/tarn`;
export const GALERA = `${HOME}/Dev/Galera`;

export const REPO_FILES = {
  "docs/spec.md": `# Spec: tarn, an agent-first terminal

tarn is a fork of Ghostty for macOS. It keeps the Ghostty core and adds a narrow set of features for CLI coding agents.

## Goal and scope

| ID | Requirement | Wave |
| --- | --- | --- |
| R5 | Markdown viewer next to the terminal, mermaid rendered, no network | first |
| R6 | File editing in the viewer | first |
| R9 | Click on a file path opens it in the viewer | first |

## State model

\`\`\`mermaid
stateDiagram-v2
  [*] --> idle
  idle --> working: UserPromptSubmit
  working --> permission: PermissionRequest
  permission --> working: PostToolUse
  working --> waiting: Stop
  waiting --> working: UserPromptSubmit
  waiting --> idle: SessionEnd
\`\`\`

## Viewer checklist

- [x] Rendered and raw views, switched with cmd+E
- [x] Mermaid without network
- [ ] Scroll kept when the agent edits the file
- [ ] Tabs split by drag and drop

> No network: a content rule list blocks every load except \`tarn-md://\`.
`,
  "docs/architecture.md": `# Architecture of tarn

One process: the Ghostty macOS app. State lives in memory.

## Map

\`\`\`mermaid
flowchart LR
  hook["hook.sh"] --> sock["ControlSocket"]
  sock --> reg["SessionRegistry"]
  proc["AgentProcess"] --> model["SidebarModel"]
  reg --> model
  model --> views["Sidebar views"]
  click["path click"] --> viewer["Viewer pane"]
\`\`\`

## Hook flow

\`\`\`mermaid
sequenceDiagram
  participant H as hook.sh
  participant S as ControlSocket
  participant R as SessionRegistry
  H->>S: event JSON
  S->>R: receive
  R-->>S: answer
\`\`\`
`,
  "docs/plans/s2-files.md": `# Plan: s2-files

## Steps

1. Workspace layout: terminal block and viewer panes
2. Viewer pane with file tabs and a files tree
3. Drag a file tab to a pane edge to split

\`\`\`sh
make -f tarn.mk check
\`\`\`
`,
  "README.md": `# tarn

An agent-first terminal for macOS, built on Ghostty.

- Sidebar with every Claude Code session and its state
- One notification when a session needs you
- Markdown and code open beside the terminal
`,
  "macos/Sources/Features/Tarn/Sidebar.swift": `/// Places the sidebar beside a terminal window's content.
struct SidebarLayout<Content: View>: View {
    @ObservedObject var model: SidebarModel
    @ObservedObject var ghostty: Ghostty.App
    let content: Content

    @AppStorage(Sidebar.collapsedKey) private var isCollapsed = false
    @AppStorage(Sidebar.widthKey) private var width = Sidebar.defaultWidth
    @AppStorage(TabStyle.key) private var tabStyle: TabStyle = .sidebar

    var body: some View {
        if tabStyle == .top {
            content
        } else {
            sidebarAndContent
        }
    }

    private var sidebarAndContent: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, isCollapsed: $isCollapsed)
                .frame(width: isCollapsed ? Sidebar.collapsedWidth : width)
            content
        }
    }
}
`,
  "macos/Sources/Features/Tarn/TarnSettings.swift": `/// Where a terminal window lists its tabs.
enum TabStyle: String, CaseIterable, Identifiable {
    case sidebar
    case top

    static let key = "TarnTabStyle"
    var id: String { rawValue }
}
`,
  "macos/Sources/Features/Tarn/AgentProcess.swift": `/// Finds the agent process that runs in a terminal surface.
enum AgentProcess {
    static let known = ["claude", "codex", "opencode"]
}
`,
  "plugin/hooks/hook.sh": `#!/bin/sh
# Forwards a Claude Code hook event to the tarn app and never fails the agent.
tarn hook "$@" 2>/dev/null || true
exit 0
`,
  ".git/HEAD": "ref: refs/heads/main\n",
  ".git/log": `4f1c2a9 feat(viewer): open a path from the terminal
b7d03e5 feat(sidebar): agent state dot per tab
91ac6d2 docs(spec): state model of agent sessions
3e58f10 chore: fork Ghostty
`,
};

export const DIRTY = ["docs/spec.md", "macos/Sources/Features/Tarn/TarnSettings.swift"];

export const GALERA_FILES = {
  "README.md": "# Galera\n\nTelegram reminder bot.\n",
  "bot/schedule.py": `"""Reminder schedule of the bot."""
from datetime import time

REMINDERS = {"morning": time(9, 0), "evening": time(20, 30)}
`,
  ".git/HEAD": "ref: refs/heads/main\n",
  ".git/log": "c0a7e41 feat(bot): reminder schedule\n6d2b9f3 chore: init\n",
};

export const EXTRA_DIRS = [`${HOME}/Desktop`, `${HOME}/Documents`, "/root"];
