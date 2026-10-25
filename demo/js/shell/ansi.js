// Escape sequences and text width for the simulated shell.
export const ESC = "\x1b";

const paint = (code) => (s) => `${ESC}[${code}m${s}${ESC}[0m`;
export const dim = paint(2);
export const bold = paint(1);
export const red = paint(31);
export const green = paint(32);
export const yellow = paint(33);
export const blue = paint(34);
export const magenta = paint(35);
export const cyan = paint(36);

// The terminal wants CR LF; command output is written with plain LF.
export const crlf = (s) => s.replace(/\r?\n/g, "\r\n");

export const stripAnsi = (s) => s.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "");

const COMBINING = /[̀-ͯ​-‏︀-️]/u;
const WIDE = /[ᄀ-ᅟ⺀-꓏가-힣豈-﫿︰-﹯＀-｠￠-￦\u{1f300}-\u{1f64f}\u{1f900}-\u{1f9ff}\u{20000}-\u{3fffd}]/u;

// Columns a character takes: 0 for combining marks, 2 for wide (CJK, emoji), else 1.
export function charWidth(ch) {
  if (COMBINING.test(ch)) return 0;
  return WIDE.test(ch) ? 2 : 1;
}

export const width = (s) => Array.from(stripAnsi(s)).reduce((n, ch) => n + charWidth(ch), 0);
