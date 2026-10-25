// Builds the license notice shipped with the viewer bundles. The package list is derived, not typed:
// the esbuild metafile gives the packages inside tarn-viewer.js, the installed dependency closure
// of mermaid gives the packages inside the prebuilt tarn-mermaid.js. A package without a license
// file fails the build, so the notice cannot fall behind the bundles.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";

function packageDir(root, name, from) {
  for (let dir = from; ; dir = dirname(dir)) {
    const candidate = join(dir, "node_modules", name);
    if (existsSync(join(candidate, "package.json"))) return candidate;
    if (dir === root || dirname(dir) === dir) return null;
  }
}

/** Package names that appear in the inputs of an esbuild metafile. */
export function packagesOfMetafile(metafile) {
  const names = new Set();
  for (const input of Object.keys(metafile.inputs)) {
    const match = input.match(/(?:^|\/)node_modules\/((?:@[^/]+\/)?[^/]+)\//);
    if (match) names.add(match[1]);
  }
  return names;
}

/** `name` and everything it depends on at run time, as installed. Returns directories. */
function closure(root, names) {
  const found = new Map();
  const visit = (name, from) => {
    const dir = packageDir(root, name, from);
    if (!dir || found.has(dir) || name.startsWith("@types/")) return; // type packages ship no code
    found.set(dir, JSON.parse(readFileSync(join(dir, "package.json"), "utf8")));
    for (const dep of Object.keys(found.get(dir).dependencies ?? {})) visit(dep, dir);
  };
  names.forEach(name => visit(name, root));
  return found;
}

export function licenseNotice(root, metafile, prebuilt) {
  const direct = closure(root, new Set([...packagesOfMetafile(metafile), ...prebuilt]));
  const sections = [...direct].map(([dir, pkg]) => {
    const files = readdirSync(dir).filter(f => /^(licen[sc]e|copying)/i.test(f)).sort();
    if (files.length === 0) throw new Error(`no license file in ${pkg.name}@${pkg.version}`);
    const text = files.map(f => readFileSync(join(dir, f), "utf8").trim()).join("\n\n");
    return { key: `${pkg.name}@${pkg.version}`, body: `== ${pkg.name} ${pkg.version} (${pkg.license ?? "see text"}) ==\n${text}` };
  });
  sections.sort((a, b) => a.key.localeCompare(b.key));
  return sections.map(s => s.body).join("\n\n\n") + "\n";
}
