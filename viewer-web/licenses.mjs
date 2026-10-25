// Builds the license notice shipped with the viewer bundles. The package list is derived, not typed:
// the esbuild metafiles of both bundles (viewer and mermaid) name the packages inside them. A package
// without a license file, or with a license outside the allowed list, fails the build, so the notice
// cannot fall behind the bundles.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";

function packageDir(root, name, from) {
  for (let dir = from; ; dir = dirname(dir)) {
    const candidate = join(dir, "node_modules", name);
    if (existsSync(join(candidate, "package.json"))) return candidate;
    if (dir === root || dirname(dir) === dir) return null;
  }
}

/** Package names with code in the output of an esbuild metafile (tree-shaken inputs do not count). */
export function packagesOfMetafile(metafile) {
  const names = new Set();
  for (const output of Object.values(metafile.outputs)) {
    for (const [input, info] of Object.entries(output.inputs)) {
      if (info.bytesInOutput === 0) continue;
      const match = input.match(/(?:^|\/)node_modules\/((?:@[^/]+\/)?[^/]+)\//);
      if (match) names.add(match[1]);
    }
  }
  return names;
}

// Packages whose package.json has no license field; the license file was read and checked by hand.
const DECLARED = { khroma: "MIT" };

const ALLOWED = ["MIT", "Apache-2.0", "ISC", "BSD-2-Clause", "BSD-3-Clause", "MPL-2.0"];

/** True when the SPDX expression can be met with allowed licenses only (`A OR B`: one is enough). */
export function isAllowed(expression) {
  return expression.replace(/[()]/g, "").split(/\s+OR\s+/).some(part =>
    part.split(/\s+AND\s+/).every(id => ALLOWED.includes(id.trim())));
}

export function licenseNotice(root, metafiles) {
  const names = new Set(metafiles.flatMap(m => [...packagesOfMetafile(m)]));
  const dirs = new Map();
  for (const name of names) {
    const dir = packageDir(root, name, root);
    if (dir) dirs.set(dir, JSON.parse(readFileSync(join(dir, "package.json"), "utf8")));
  }
  const sections = [...dirs].map(([dir, pkg]) => {
    const id = `${pkg.name}@${pkg.version}`;
    const license = typeof pkg.license === "string" ? pkg.license : DECLARED[pkg.name] ?? "";
    if (!isAllowed(license)) throw new Error(`${id}: license "${license}" is not on the allowed list ${ALLOWED.join(", ")}`);
    const files = readdirSync(dir).filter(f => /^(licen[sc]e|copying)/i.test(f)).sort();
    if (files.length === 0) throw new Error(`no license file in ${id}`);
    const text = files.map(f => readFileSync(join(dir, f), "utf8").trim()).join("\n\n");
    return { key: id, body: `== ${pkg.name} ${pkg.version} (${license}) ==\n${text}` };
  });
  sections.sort((a, b) => a.key.localeCompare(b.key));
  return sections.map(s => s.body).join("\n\n\n") + "\n";
}
