// Splits a command line into words: quotes, backslash, ~ and $VAR. Pipes, redirects, lists
// and globs are not part of the demo shell and give an error naming the operator.
const OPERATORS = new Set(["|", "&", ";", "<", ">", "*", "?", "(", ")", "`"]);

export function parseLine(line, env) {
  const words = [];
  let word = null;
  let quote = null;

  const add = (s) => { word = (word ?? "") + s; };

  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quote === "'") {
      if (ch === "'") quote = null;
      else add(ch);
    } else if (ch === "\\" && i + 1 < line.length) {
      add(line[++i]);
    } else if (ch === quote) {
      quote = null;
    } else if (!quote && (ch === "'" || ch === '"')) {
      quote = ch;
      word ??= "";
    } else if (ch === "$" && /[A-Za-z_{]/.test(line[i + 1] ?? "")) {
      const m = /^\$(?:\{(\w+)\}|(\w+))/.exec(line.slice(i));
      if (!m) { add(ch); continue; }
      add(env[m[1] ?? m[2]] ?? "");
      i += m[0].length - 1;
    } else if (!quote && /\s/.test(ch)) {
      if (word !== null) words.push(word);
      word = null;
    } else if (!quote && OPERATORS.has(ch)) {
      return { words: [], error: `not supported in the demo: ${ch}` };
    } else if (!quote && ch === "~" && word === null && (i + 1 === line.length || /[\s/]/.test(line[i + 1]))) {
      add(env.HOME);
    } else {
      add(ch);
    }
  }
  if (quote) return { words: [], error: `unmatched ${quote}` };
  if (word !== null) words.push(word);
  return { words, error: null };
}
