# viewer-web

Web part of the tarn viewer pane: markdown-it, highlight.js, CodeMirror 6 and mermaid, bundled with esbuild.
The app build does not need node: the output is committed to `macos/Sources/Features/Tarn/Viewer/`
(`tarn-viewer.js`, `tarn-viewer.html`, `tarn-viewer.css`, `tarn-mermaid.js`, `tarn-viewer-licenses.txt`).

Rebuild after changing `src/` or a version in `package.json`:

```sh
cd viewer-web
npm ci
npm run build
```

`tarn-mermaid.js` is a copy of `node_modules/mermaid/dist/mermaid.min.js` (version pinned in
`package.json`). It stays in git on purpose. To upgrade mermaid, change the version, run the commands
above, commit the new bundle, and update the matching rows in `THIRD_PARTY.md`.
`build.mjs` also regenerates `tarn-viewer-licenses.txt` from the bundle inputs and the mermaid dependency closure (`licenses.mjs`); it fails if a package has no license file.
