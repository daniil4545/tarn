// Builds the viewer page into macos/Sources/Features/Tarn/Viewer/. Run: npm install && npm run build.
import { build } from "esbuild";
import { copyFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { licenseNotice } from "./licenses.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "..", "macos", "Sources", "Features", "Tarn", "Viewer");
mkdirSync(out, { recursive: true });

const { metafile } = await build({
  entryPoints: [join(here, "src", "main.js")],
  bundle: true,
  minify: true,
  format: "iife",
  absWorkingDir: here, // metafile paths are relative to the viewer-web folder
  target: "safari16",
  outfile: join(out, "tarn-viewer.js"),
  legalComments: "eof",
  metafile: true,
});
copyFileSync(join(here, "src", "viewer.html"), join(out, "tarn-viewer.html"));
copyFileSync(join(here, "src", "viewer.css"), join(out, "tarn-viewer.css"));
// Mermaid is bundled from source, not copied from dist/mermaid.min.js, to leave out elkjs (EPL-2.0).
const { metafile: mermaidMeta } = await build({
  entryPoints: [join(here, "src", "mermaid-entry.js")],
  bundle: true,
  minify: true,
  format: "iife",
  absWorkingDir: here, // metafile paths are relative to the viewer-web folder
  target: "safari16",
  outfile: join(out, "tarn-mermaid.js"),
  legalComments: "none",
  alias: { "elkjs/lib/elk.bundled.js": join(here, "src", "elk-stub.js") },
  metafile: true,
});

writeFileSync(join(out, "tarn-viewer-licenses.txt"), licenseNotice(here, [metafile, mermaidMeta]));
