// Clickable text in a pane: file paths that exist on the vfs (`path` or `path:line`) and URLs.
const PATH = /[\w~./-]*[\w-]\.[A-Za-z0-9]+(?::\d+)?/g;
const URL = /https?:\/\/[^\s)'"]+/g;

export function addPaneLinks(term, { vfs, cwd, home, openFile, urlEnabled }) {
  const find = (line, regex, keep) => [...line.matchAll(regex)]
    .map((m) => ({ start: m.index, end: m.index + m[0].length, text: m[0] }))
    .filter(keep);

  // "docs/spec.md:12" -> absolute path and line.
  const target = (text) => {
    const [path, line] = text.split(/:(?=\d+$)/);
    return { path: vfs.resolve(cwd(), path.startsWith("~") ? home + path.slice(1) : path), line: line && Number(line) };
  };

  term.addLinkProvider(
    (line) => find(line, PATH, ({ text }) => vfs.isFile(target(text).path)),
    (text) => {
      const { path, line } = target(text);
      openFile(path, line || undefined);
    },
  );

  term.addLinkProvider(
    (line) => (urlEnabled() ? find(line, URL, () => true) : []),
    (text, e) => {
      if (e.metaKey || e.ctrlKey) window.open(text, "_blank", "noopener");
    },
  );
}
