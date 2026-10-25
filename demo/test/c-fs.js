// A small in-memory file set for the viewer and settings checks (the demo's own vfs.js is the terminal slice's).
const ROOT = "/home/demo/tarn";
const filler = Array.from({ length: 60 }, (_, i) => `Paragraph ${i + 1} of the spec text, long enough to scroll the page.`).join("\n\n");

export const files = new Map([
  [`${ROOT}/README.md`, "# tarn\n\nAn agent-first terminal.\n"],
  [`${ROOT}/docs/spec.md`, `# Spec\n\n\`\`\`mermaid\ngraph LR\n  A --> B\n\`\`\`\n\n- [ ] first task\n- [x] second task\n\nSee [the plan](plans/s2-files.md) and [missing](nope.md).\n\n${filler}\n`],
  [`${ROOT}/docs/architecture.md`, "# Architecture\n\nSections.\n"],
  [`${ROOT}/docs/plans/s2-files.md`, "# Plan s2\n\nFiles.\n"],
  [`${ROOT}/macos/Sources/Features/Tarn/Sidebar.swift`, Array.from({ length: 40 }, (_, i) => `let line${i + 1} = ${i + 1}`).join("\n") + "\n"],
]);

export const fs = {
  home: "/home/demo",
  exists: (path) => files.has(path) || fs.isDir(path),
  isDir: (path) => [...files.keys()].some((f) => f.startsWith(`${path}/`)),
  read: (path) => files.get(path) ?? null,
  list(dir) {
    const names = new Map();
    for (const file of files.keys()) {
      if (!file.startsWith(`${dir}/`)) continue;
      const [name, ...rest] = file.slice(dir.length + 1).split("/");
      names.set(name, rest.length > 0);
    }
    return [...names].map(([name, isDir]) => ({ name, dir: isDir }));
  },
};

export { ROOT };
