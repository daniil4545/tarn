# Plan: S2 files, the viewer pane

Status: draft for `spec-reviewer`, ticket T-137, branch `s2-files`.
Canon: `docs/spec.md` (1, 2, 2.5, 3, 7, 12, 13); `docs/architecture.md`; look and behavior: `docs/mockups/tarn.html` (approved for the viewer pane only).
Inputs: recon files of 2026-10-25 (markdown panel, open file, Ghostty built-ins).

## 1. Goal and scope

- Goal: one viewer pane that opens files from path clicks, shows markdown rendered, shows code with line numbers, edits and saves, follows agent rewrites.
- In: file tabs (preview and pinned), files tree on the right, markdown view and source (editor), mermaid, code blocks with Copy, task-list write-back, code view with `path:line`, file watcher with conflict banner, no-network rule, theme from terminal background, a temporary host (one pane right of the terminal area of a window tab), path click and socket `open`.
- Out: several panes, outer layout tree, tab drag between panes, terminal pane headers, pane limits, HTML and PDF (R11), diff mode, workspace changes, the `tarn` CLI binary (the socket command exists; the binary does not).

## 2. Ghostty first: what is reused

| Need | Ghostty has | Use |
|---|---|---|
| Pane beside a view | `SplitView` `Sources/Features/Splits/SplitView.swift:8`; used by `InspectorView.swift:29` | host uses `SplitView(.horizontal ...)`, divider color from `ghostty.config.splitDividerColor` |
| Path click | core detects paths, `openURL` `Ghostty.App.swift:808`; the call at `:747` has `target` in `performAction` but does not pass it | we pass `target` and add one block at the top of `openURL`; `openConfig` (`:139`) and OSC 8 links keep the upstream path |
| Cwd of the clicked terminal | `SurfaceView.pwd` `Sources/Ghostty/Surface View/OSSurfaceView.swift:14` | relative path base |
| Undo of a close | `ExpiringUndoManager` `Sources/Helpers/ExpiringUndoManager.swift:14`, `undoExpiration` `BaseTerminalController.swift:113`, pattern at `:553-580` | closing the viewer registers an undo that reopens its tabs; same timeout as splits |
| Cmd+W | menu "Close" sends `close(_:)` `BaseTerminalController.swift:1310` along the responder chain | the viewer web view implements `close(_:)`, so the menu path and the user's key binding work with no key hook |
| Focus | `InspectorView.swift:45-52` moves focus with `@FocusState` and `resignFirstResponder`; `Ghostty.moveFocus(to:)` (`SurfaceView.swift:1075`) takes a surface only | the page takes first responder with `makeFirstResponder`; `moveFocus` returns focus to the terminal |
| Theme | `NSColor(ghostty.config.backgroundColor).isLightColor` `Sidebar.swift:445` | dark/light for the page |
| Window state per tab | `private let sidebarModel` `TerminalController.swift:65` | same pattern for the host |

Own (Ghostty lacks it): the web view, the file model, the watcher, the tree. Not reused on purpose: `SplitTree` (outer layout is undecided, the temporary host needs one fixed split). No parallel undo, title, notification or menu system is added. Not done: a window-level Cmd+B and a titlebar Files button (they need the window model); Cmd+B, Cmd+E, Cmd+S act when the viewer has focus.

## 3. Analogs (project, file, commit)

| Mechanism | Analog | Mode |
|---|---|---|
| markdown-it setup, mermaid fence, `html:false` | MarkEdit-preview `src/render.ts` @5bdd252 (MIT) | follow, own bundle |
| scheme handler for assets | MarkEdit `EditorViewController.swift:166` @abba496 (MIT) | follow |
| file and directory vnode watcher, re-arm, 300 ms | macdown3000 `MPFileWatcher.m` @eb3b3c6 (MIT); cmux `FileWatcher.swift` @f9f71ac4 (GPL, structure only) | port idea to Swift |
| live DOM swap keeping scroll | cmux `shell.html:1165-1200` (structure only) | write own |
| block-all rule list | own test of 2026-10-25 (3 requests to 0) | reuse |
| preview tab versus pinned tab | VS Code behavior (not code) | behavior only |
| source editor | CodeMirror 6 (MIT), as MarkEdit does | vendor |

Vendored into the bundle (all offline): markdown-it 14.1.0 MIT (15 is ESM-only; the bundler takes either, 14 chosen as the UMD-tested one), highlight.js 11.11.1 BSD-3, mermaid 12.2.0 MIT (older 11.x had XSS fixes), CodeMirror 6 packages MIT. Entries go to `THIRD_PARTY.md`. Build input is `viewer-web/` (npm, esbuild); the build output is committed under `macos/Sources/Features/Tarn/Viewer/`, so the app build needs no node.

## 4. Design

```
path click / socket open
  -> ViewerRouter (resolve, classify)
  -> ViewerHost of the window (open state, SplitView)
  -> ViewerModel (tabs, documents, tree, watchers)  <->  ViewerWebView (WKWebView, page draws the pane)
```

- `ViewerModel` is the source of truth for tabs, text, dirty flag, conflicts and tree rows. The page draws and sends events (`open`, `pin`, `close`, `edit`, `save`, `toggleTask`, `take`, `keep`, `link`, `copy`). Swift pushes `setChrome` (tabs, tree, theme) and `setDoc` (path, revision, text) as JSON. The page keeps scroll and mode per path and applies a doc only when its revision changed.
- Tab rules (`ViewerTabs`): open adds a preview tab; the next open replaces the preview tab; a pinned tab is never replaced; pin by double click, by an edit, or by `pin`; opening an open path activates it; closing the last tab closes the pane.
- Document rules (`ViewerDocument`): text, saved text, disk fingerprint (mtime, size). Disk change with clean text: reload, revision up. Disk change with unsaved edits: `conflict` banner; Take sets disk text, Keep clears the banner and keeps the fingerprint. Save writes UTF-8 atomically. A task toggle edits the text at the n-th task marker and saves.
- Limits: over 5 MB or invalid UTF-8 gives a one-line notice instead of content; highlight is skipped over 512 KB.
- No network: rule list `[{block ".*"}, {ignore-previous-rules "^tarn-md:"}]`, navigation policy (own scheme and anchors only; http(s) and mailto go to `NSWorkspace`), CSP meta, `html:false`, mermaid `securityLevel: strict`, remote images rendered as links. Assets and images come through `tarn-md://`: bundle files by name, images only from the allowed roots (terminal cwd root, directories of open files) with an extension allowlist.
- Path rules (`ViewerPaths`): `path[:line[:col]]`; `~/`, absolute, relative to the clicked surface cwd; a real file whose name contains a colon wins over the split; directories and missing files are not opened (missing: a one-line notice); images, audio, video, PDF, archives go to the default app.
- Socket contract: `{"version":1,"cmd":"open","surface":uuid,"path":"/abs","line":n}`. The path must be absolute. Reply `{"ok":true}` or `{"ok":false,"error":...}` for a bad version, relative path, unknown surface, missing file (`tarn: no such file: <path>`), folder, non-text file. It never launches another app. A line without `cmd` stays a hook event; the dispatch is in the socket callback, not in the registry's `receive`.
- Focus rules: the path click moves focus to the viewer (the user acted). Socket `open` never does: a new pane changes the layout and takes the first responder, so the host restores the previous first responder; if the user types in the pane, the file opens as a background tab and the active tab stays.
- Router kinds: only clicks of kind `unknown` (plain paths, `file://`) go to the router. OSC 8 links keep the strict upstream path. Text files open in the viewer (non-UTF-8 and over 5 MB give the notice); image, audio, video, PDF, archive and application types open in their own app; folders and a missing file without a pane keep the default.
- Text ownership: Swift holds the text; each page message carries the revision it was made against; a stale `edit` or `task` is dropped. Save compares the disk fingerprint first and stops with a notice on a conflict; the fingerprint after our own write is stored, so our write is no change. A checkbox on a dirty document asks to save first; the line comes from the markdown-it token map.
- Deleted file: the tab keeps the text, a notice says so, Save writes the file again. Write error: a notice with the reason, the tab stays dirty. Closing a dirty tab or the pane asks first; undo of a closed pane reopens paths only.
- `path:line` in markdown scrolls the rendered view to the block with that line and flashes it; a line past the end gives the last block.
- Any other failure (bad diagram, script error, web process killed): the page logs it, shows a line in the pane and keeps the model; a bad diagram shows its source and the error; a killed web process reloads the page and the model refills it. The web view is created at the first open and dropped when the pane closes.
- Keys: while the pane has focus Cmd+B, Cmd+E and Cmd+S go to the pane before the menu (Cmd+E beats Ghostty's selection-for-find there); Cmd+W reaches the pane as the menu action `close:`.

## 5. Files

| File | Role |
|---|---|
| `Tarn/ViewerPaths.swift` | path parse, resolve, classify |
| `Tarn/ViewerTabs.swift` | tab list, preview and pin rules |
| `Tarn/ViewerDocument.swift` | text, dirty, disk change, task write-back |
| `Tarn/ViewerRules.swift` | rule list JSON, CSP, asset allowlist |
| `Tarn/FileWatcher.swift` | vnode file and directory watcher |
| `Tarn/FileTree.swift` | folder listing and fold state |
| `Tarn/ViewerModel.swift` | owns the above, talks to the page |
| `Tarn/ViewerWebView.swift` | WKWebView, scheme handler, key handling |
| `Tarn/ViewerHost.swift` | open state, SplitView layout, router, undo |
| `Tarn/Viewer/*` | page: html, css, js bundle, mermaid.min.js |
| `viewer-web/` | npm sources and `build.mjs` |
| `Tests/Tarn/Viewer*Tests.swift` | model tests |

Insertion points in upstream files (to `docs/architecture.md` section 9): (10) `TerminalController.swift`: property `viewerHost`, wrap of `TerminalView` in `ViewerLayout`; (11) `Ghostty.App.swift`: call to `ViewerRouter.handle(...)` at the `open_url` action, `target` passed; the socket callback in `SessionRegistry.start` (our file) hands `cmd` lines to the router.

## 6. Test scenarios

| Level | Scenario | Fact that proves it |
|---|---|---|
| unit | open A, open B: one tab; pin A, open B: two tabs | tab count and preview flags |
| unit | edit marks pinned and dirty; close last tab reports pane close | flags |
| unit | `a.md:12:3`, `~/x`, `./y`, absolute; a file named `a:b` | resolved path and line |
| unit | directory, missing, image, 6 MB, invalid UTF-8 | classification |
| unit | disk change, clean: reload; with edits: conflict; Take; Keep; same fingerprint twice: one banner | state after each call |
| unit | rule list JSON has block-all and the ignore rule for `tarn-md:`; compiles in `WKContentRuleListStore` | JSON and compile result |
| unit | background open keeps the active tab | tab state |
| unit | asset path outside roots or with `..` or wrong extension is refused | refusal |
| unit | task toggle n-th marker, code fences ignored, other lines unchanged | resulting text |
| run | path click opens rendered markdown with a mermaid diagram | page reports one `svg`; web snapshot read |
| run | tree toggles on the right; Cmd+E shows the editor; Cmd+S writes | page state, web snapshot, `diff` of the file |
| run | socket `open`: first responder unchanged; background tab while typing in the pane; error replies | first responder before and after |
| run | agent rewrite re-renders; with edits a banner shows and Save is refused | page state |
| run | Cmd+W closes the active tab, the last tab closes the pane, undo reopens it | page state |
| not run | no request leaves the page: only the rule list compile is tested, the earlier 3-to-0 test (recon 2026-10-25) is not repeated | - |
| user | look against the mockup, Cmd+W, undo of the close | by eye |

## 7. Steps

1. Spec and plan edits, `spec-reviewer` (10 must-fix, answered in sections 4 and 6).
2. Web bundle (`viewer-web/`), page.
3. Swift model parts with tests.
4. Web view, host, router, insertion points.
5. Build, lint, run, screenshots.
6. `code-reviewer`, fixes, commit, push.
