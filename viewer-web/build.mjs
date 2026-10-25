// Builds the viewer page into macos/Sources/Features/Tarn/Viewer/. Run: npm install && npm run build.
import { build } from "esbuild";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "..", "macos", "Sources", "Features", "Tarn", "Viewer");
mkdirSync(out, { recursive: true });

await build({
  entryPoints: [join(here, "src", "main.js")],
  bundle: true,
  minify: true,
  format: "iife",
  target: "safari16",
  outfile: join(out, "tarn-viewer.js"),
  legalComments: "eof",
});
copyFileSync(join(here, "src", "viewer.html"), join(out, "tarn-viewer.html"));
copyFileSync(join(here, "src", "viewer.css"), join(out, "tarn-viewer.css"));
copyFileSync(join(here, "node_modules", "mermaid", "dist", "mermaid.min.js"), join(out, "tarn-mermaid.js"));

// License texts of the packages that ship in the page, for the notice the licenses require.
const packages = ["markdown-it", "highlight.js", "mermaid", "codemirror", "@codemirror/view", "@codemirror/state",
  "@codemirror/commands", "@codemirror/language", "@codemirror/lang-markdown", "@lezer/highlight"];
const texts = packages.map(name => {
  const dir = join(here, "node_modules", name);
  const file = ["LICENSE", "LICENSE.md", "LICENSE.txt"].map(f => join(dir, f)).find(existsSync);
  return `== ${name} ==\n${file ? readFileSync(file, "utf8") : "MIT (see the package)"}`;
});
writeFileSync(join(out, "tarn-viewer-licenses.txt"), texts.join("\n\n"));
