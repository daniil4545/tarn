// Paths of the viewer: what a path click or `tarn open` asks for. Port of ViewerPaths.swift
// (macos/Sources/Features/Tarn/ViewerPaths.swift). Pure functions, no DOM.

export const dirname = (path) => path.slice(0, Math.max(0, path.lastIndexOf("/"))) || "/";
export const basename = (path) => path.slice(path.lastIndexOf("/") + 1);

const MARKDOWN = new Set(["md", "markdown", "mdown", "mkd"]);
const extension = (path) => (basename(path).includes(".") ? basename(path).split(".").pop().toLowerCase() : "");

export const isMarkdown = (path) => MARKDOWN.has(extension(path));

// The highlight.js language hint: the extension, or the lowercase name of `Makefile` and the like.
export const language = (path) => extension(path) || basename(path).toLowerCase();

// Resolves `.` and `..`; the result is absolute.
export function normalize(path) {
  const out = [];
  for (const part of path.split("/")) {
    if (part === "" || part === ".") continue;
    if (part === "..") out.pop();
    else out.push(part);
  }
  return "/" + out.join("/");
}

const expand = (path, home) => (path === "~" || path.startsWith("~/") ? home + path.slice(1) : path);

// `~/`, absolute and relative paths with an optional `:line[:column]` suffix. A real file whose
// name contains a colon wins over the `:line` split. Returns {path, line} or null.
export function resolve(raw, { cwd, home, exists }) {
  let text = raw.trim();
  if (text.startsWith("file://")) text = decodeURI(new URL(text).pathname);
  if (!text) return null;
  const candidates = [[text, null]];
  const suffix = /:(\d+)(:\d+)?$/.exec(text);
  if (suffix) candidates.push([text.slice(0, suffix.index), Number(suffix[1])]);

  let fallback = null;
  for (const [candidate, line] of candidates) {
    if (!candidate) continue;
    const full = candidate.startsWith("~") || candidate.startsWith("/") ? expand(candidate, home) : cwd && `${expand(cwd, home)}/${candidate}`;
    if (!full) continue;
    const target = { path: normalize(full), line };
    if (exists(target.path)) return target;
    fallback = target;
  }
  return fallback;
}

// Task-list write-back: `- [ ] item` and `- [x] item` lines, also inside quotes. Returns the new
// text, or null when the line has no marker.
export function setTask(text, line, checked) {
  const lines = text.split("\n");
  const match = lines[line] && /^([\s>]*(?:[-*+]|\d+[.)])\s+\[)([ xX])(\])/.exec(lines[line]);
  if (!match) return null;
  const at = match[1].length;
  lines[line] = lines[line].slice(0, at) + (checked ? "x" : " ") + lines[line].slice(at + 1);
  return lines.join("\n");
}
