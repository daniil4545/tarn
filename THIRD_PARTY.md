# Third-party code

Code ported into tarn from other projects. Each file keeps a header naming its source.

| Our file | Source | Authors | License |
| --- | --- | --- | --- |
| `macos/Sources/Features/Tarn/Sidebar.swift` | [ghostty-org/ghostty PR #14562](https://github.com/ghostty-org/ghostty/pull/14562), vertical tab sidebar | Somnathumapathi, Priyans-hu | MIT |
| `macos/Sources/Features/Tarn/AgentProcess.swift` | [thdxg/macterm](https://github.com/thdxg/macterm) `Macterm/Model/AgentIcon.swift`, `Macterm/System/ProcessInspector.swift` at 764257f, agent detection by process name | Macterm | MIT |
| `macos/Assets.xcassets/TarnAgent*.imageset` | [thdxg/macterm](https://github.com/thdxg/macterm) `Macterm/Assets.xcassets/Agent{Claude,Codex,OpenCode}.imageset` at 764257f | Macterm | MIT; the logos are trademarks of Anthropic, OpenAI and SST, shown only to name the running agent |
| `macos/Sources/Features/Tarn/Viewer/tarn-viewer.js` (bundle of `viewer-web/`) | [markdown-it](https://github.com/markdown-it/markdown-it) 14.1.0; [highlight.js](https://github.com/highlightjs/highlight.js) 11.11.1; [CodeMirror 6](https://github.com/codemirror) packages (`view`, `state`, `commands`, `language`, `lang-markdown`, `lezer`) | their authors | MIT; highlight.js BSD-3-Clause |
| `macos/Sources/Features/Tarn/Viewer/tarn-mermaid.js` | [mermaid](https://github.com/mermaid-js/mermaid) 12.2.0 `dist/mermaid.min.js`, with its bundled packages (d3 and others: MIT, ISC, BSD-3-Clause; DOMPurify: Apache-2.0 or MPL-2.0) | Mermaid contributors | MIT |
| `viewer-web/src/main.js`, `macos/Sources/Features/Tarn/ViewerWebView.swift`, `FileWatcher.swift` | written by us, following [MarkEdit-preview](https://github.com/MarkEdit-app/MarkEdit-preview) `src/render.ts` at 5bdd252 (markdown-it setup), [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) `EditorViewController.swift` at abba496 (asset scheme handler) and [macdown3000](https://github.com/schuyler/macdown3000) `MPFileWatcher.m` at eb3b3c6 (file watcher); no code copied | MarkEdit, macdown3000 authors | MIT |
