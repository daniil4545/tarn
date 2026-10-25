// Builds the license notice shipped with the viewer bundles. The package list is derived, not typed:
// the esbuild metafiles of both bundles (viewer and mermaid) name the packages inside them. A package
// without a license file, or with a license outside the allowed list, fails the build, so the notice
// cannot fall behind the bundles.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Directories (relative to the metafile base) of the packages with code in the output of an esbuild
 * metafile. A package is named by the last `node_modules` segment of the input path, so a nested copy
 * (`d3-sankey/node_modules/d3-array`) is found as its own package; tree-shaken inputs do not count.
 */
export function packageDirsOfMetafile(metafile) {
  const dirs = new Set();
  for (const output of Object.values(metafile.outputs)) {
    for (const [input, info] of Object.entries(output.inputs)) {
      if (info.bytesInOutput === 0) continue;
      const marker = "node_modules/";
      const at = input.lastIndexOf(marker);
      if (at < 0) continue;
      const rest = input.slice(at + marker.length).split("/");
      const name = rest[0].startsWith("@") ? rest.slice(0, 2) : rest.slice(0, 1);
      dirs.add(input.slice(0, at + marker.length) + name.join("/"));
    }
  }
  return dirs;
}

// Packages whose package.json has no license field; the license file was read and checked by hand.
const DECLARED = { khroma: "MIT" };

const ALLOWED = ["MIT", "Apache-2.0", "ISC", "BSD-2-Clause", "BSD-3-Clause", "MPL-2.0"];

/** True when the SPDX expression can be met with allowed licenses only (`A OR B`: one is enough). */
export function isAllowed(expression) {
  return expression.replace(/[()]/g, "").split(/\s+OR\s+/).some(part =>
    part.split(/\s+AND\s+/).every(id => ALLOWED.includes(id.trim())));
}

export function licenseNotice(base, metafiles) {
  const dirs = new Set(metafiles.flatMap(m => [...packageDirsOfMetafile(m)]));
  const sections = [...dirs].map(relative => {
    const dir = join(base, relative);
    const pkg = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
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
