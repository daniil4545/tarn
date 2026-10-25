// Run: node --test viewer-web/licenses.test.mjs
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { isAllowed, licenseNotice, packageDirsOfMetafile } from "./licenses.mjs";

const metafile = inputs => ({ outputs: { "out.js": { inputs } } });
const used = { bytesInOutput: 10 };

test("a nested copy is its own package, scoped names keep two segments, shaken inputs are skipped", () => {
  const dirs = packageDirsOfMetafile(metafile({
    "node_modules/d3-sankey/src/a.js": used,
    "node_modules/d3-sankey/node_modules/d3-array/src/b.js": used,
    "node_modules/@lezer/common/dist/c.js": used,
    "node_modules/shaken/index.js": { bytesInOutput: 0 },
    "src/main.js": used,
  }));
  assert.deepEqual([...dirs].sort(), [
    "node_modules/@lezer/common",
    "node_modules/d3-sankey",
    "node_modules/d3-sankey/node_modules/d3-array",
  ]);
});

function fixture() {
  const base = mkdtempSync(join(tmpdir(), "licenses-"));
  const add = (dir, name, version, license, text = "text") => {
    mkdirSync(join(base, dir), { recursive: true });
    writeFileSync(join(base, dir, "package.json"), JSON.stringify({ name, version, license }));
    if (text) writeFileSync(join(base, dir, "LICENSE"), `${name} ${text}`);
  };
  return { base, add };
}

test("the notice lists the nested version with its own license text", () => {
  const { base, add } = fixture();
  add("node_modules/d3-sankey", "d3-sankey", "0.12.3", "BSD-3-Clause");
  add("node_modules/d3-sankey/node_modules/d3-array", "d3-array", "2.12.1", "BSD-3-Clause", "old text");
  add("node_modules/d3-array", "d3-array", "3.2.4", "ISC", "new text");
  const notice = licenseNotice(base, [metafile({
    "node_modules/d3-sankey/src/a.js": used,
    "node_modules/d3-sankey/node_modules/d3-array/src/b.js": used,
    "node_modules/d3-array/src/c.js": used,
  })]);
  assert.match(notice, /== d3-array 2\.12\.1 \(BSD-3-Clause\) ==\nd3-array old text/);
  assert.match(notice, /== d3-array 3\.2\.4 \(ISC\) ==\nd3-array new text/);
});

test("a license outside the list or a missing license file fails", () => {
  const { base, add } = fixture();
  add("node_modules/epl", "epl", "1.0.0", "EPL-2.0");
  assert.throws(() => licenseNotice(base, [metafile({ "node_modules/epl/a.js": used })]), /not on the allowed list/);
  add("node_modules/bare", "bare", "1.0.0", "MIT", "");
  assert.throws(() => licenseNotice(base, [metafile({ "node_modules/bare/a.js": used })]), /no license file/);
});

test("an OR expression passes when one side is allowed", () => {
  assert.ok(isAllowed("(MPL-2.0 OR Apache-2.0)"));
  assert.ok(isAllowed("MPL-2.0"));
  assert.ok(!isAllowed("EPL-2.0 OR Unlicense"));
  assert.ok(!isAllowed(""));
});
