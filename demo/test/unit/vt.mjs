// Minimal VT screen for unit tests: enough of CR, LF, CUU, CHA, ED, EL, CUP to follow the shell output.
export function createScreen(cols = 40, rows = 12) {
  let grid = Array.from({ length: rows }, () => Array(cols).fill(" "));
  let x = 0;
  let y = 0;
  let pendingWrap = false;
  const scrolled = [];

  const lineFeed = () => {
    if (y === rows - 1) {
      scrolled.push(grid.shift().join("").trimEnd());
      grid.push(Array(cols).fill(" "));
    } else y++;
  };

  function csi(params, final) {
    const n = Number(params.split(";")[0]) || 0;
    if (final === "A") y = Math.max(0, y - (n || 1));
    else if (final === "G") x = Math.min(cols - 1, (n || 1) - 1);
    else if (final === "H") { y = 0; x = 0; }
    else if (final === "J") {
      if (n === 2) grid = grid.map(() => Array(cols).fill(" "));
      else { grid[y].fill(" ", x); for (let r = y + 1; r < rows; r++) grid[r].fill(" "); }
    } else if (final === "K") grid[y].fill(" ", x);
    pendingWrap = false;
  }

  return {
    write(data) {
      const re = /\x1b\[([0-9;?]*)([A-Za-z])|([\s\S])/gu;
      for (const [, params, final, ch] of data.matchAll(re)) {
        if (final) csi(params, final);
        else if (ch === "\r") { x = 0; pendingWrap = false; }
        else if (ch === "\n") lineFeed();
        else if (ch >= " ") {
          if (pendingWrap) { x = 0; lineFeed(); pendingWrap = false; }
          grid[y][x] = ch;
          if (x === cols - 1) pendingWrap = true;
          else x++;
        }
      }
    },
    lines: () => grid.map((r) => r.join("").trimEnd()),
    text: () => [...scrolled, ...grid.map((r) => r.join("").trimEnd())].join("\n").replace(/\n+$/, ""),
    get cursor() { return { x, y }; },
  };
}
