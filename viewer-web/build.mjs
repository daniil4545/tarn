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
  target: "safari16",
  outfile: join(out, "tarn-viewer.js"),
  legalComments: "eof",
  metafile: true,
});
copyFileSync(join(here, "src", "viewer.html"), join(out, "tarn-viewer.html"));
copyFileSync(join(here, "src", "viewer.css"), join(out, "tarn-viewer.css"));
copyFileSync(join(here, "node_modules", "mermaid", "dist", "mermaid.min.js"), join(out, "tarn-mermaid.js"));

writeFileSync(join(out, "tarn-viewer-licenses.txt"), licenseNotice(here, metafile, ["mermaid"]));
