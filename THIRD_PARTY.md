# Third-party code

Code ported into tarn from other projects. Each file keeps a header naming its source.

| Our file | Source | Authors | License |
| --- | --- | --- | --- |
| `macos/Sources/Features/Tarn/Sidebar.swift` | [ghostty-org/ghostty PR #14562](https://github.com/ghostty-org/ghostty/pull/14562), vertical tab sidebar | Somnathumapathi, Priyans-hu | MIT |
| `macos/Sources/Features/Tarn/AgentProcess.swift` | [thdxg/macterm](https://github.com/thdxg/macterm) `Macterm/Model/AgentIcon.swift`, `Macterm/System/ProcessInspector.swift` at 764257f, agent detection by process name | Macterm | MIT |
| `macos/Assets.xcassets/TarnAgent*.imageset` | [thdxg/macterm](https://github.com/thdxg/macterm) `Macterm/Assets.xcassets/Agent{Claude,Codex,OpenCode}.imageset` at 764257f | Macterm | MIT; the logos are trademarks of Anthropic, OpenAI and SST, shown only to name the running agent |
| `macos/Sources/Features/Tarn/Viewer/tarn-viewer.js` (bundle of `viewer-web/`) | [markdown-it](https://github.com/markdown-it/markdown-it) 14.1.0; [highlight.js](https://github.com/highlightjs/highlight.js) 11.11.1; [CodeMirror 6](https://github.com/codemirror) packages (`view`, `state`, `commands`, `language`, `lang-markdown`, `lezer`) | their authors | MIT; highlight.js BSD-3-Clause |
| `macos/Sources/Features/Tarn/Viewer/tarn-mermaid.js` (bundle) | [mermaid](https://github.com/mermaid-js/mermaid) 12.2.0, bundled from source by `viewer-web/build.mjs` without elkjs (EPL-2.0); the page uses the dagre layout | Mermaid contributors | MIT |
| same, bundled | [d3](https://github.com/d3/d3) 7.9.0 and its `d3-*` modules (3.x and 4.x) | Mike Bostock and contributors | ISC |
| same, bundled | [d3-ease](https://github.com/d3/d3-ease) 3.0.1, [d3-sankey](https://github.com/d3/d3-sankey) 0.12.3 | Mike Bostock and contributors | BSD-3-Clause |
| same, bundled | [DOMPurify](https://github.com/cure53/DOMPurify) 3.4.17 | Cure53 and contributors | MPL-2.0 or Apache-2.0; tarn uses it under Apache-2.0 |
| same, bundled | [chevrotain](https://github.com/Chevrotain/chevrotain) 13.2.0 and its `@chevrotain/*` packages | Chevrotain contributors | Apache-2.0 |
| `macos/Sources/Features/Tarn/Viewer/tarn-viewer.js` (bundle) | [entities](https://github.com/fb55/entities) 4.5.0 (dependency of markdown-it), and the small MIT packages of CodeMirror and markdown-it (`@lezer/common`, `@lezer/markdown`, `style-mod`, `w3c-keyname`, `crelt`, `linkify-it`, `mdurl`, `uc.micro`, `punycode.js`) | their authors | BSD-2-Clause; MIT |
| `viewer-web/src/main.js`, `macos/Sources/Features/Tarn/ViewerWebView.swift`, `FileWatcher.swift` | written by us, following [MarkEdit-preview](https://github.com/MarkEdit-app/MarkEdit-preview) `src/render.ts` at 5bdd252 (markdown-it setup), [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) `EditorViewController.swift` at abba496 (asset scheme handler) and [macdown3000](https://github.com/schuyler/macdown3000) `MPFileWatcher.m` at eb3b3c6 (file watcher); no code copied | MarkEdit, macdown3000 authors | MIT |

The complete list of packages inside the viewer bundles (86, including the transitive MIT ones such as katex, cytoscape, dayjs, marked, lodash-es) with versions and license texts is `macos/Sources/Features/Tarn/Viewer/tarn-viewer-licenses.txt`. `viewer-web/build.mjs` generates it from the esbuild metafiles of both bundles (`viewer-web/licenses.mjs`) and fails when a package has no license file or a license outside MIT, Apache-2.0, ISC, BSD-2-Clause, BSD-3-Clause and MPL-2.0. The rows above group them by license.
