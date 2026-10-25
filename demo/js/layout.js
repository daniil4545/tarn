// Pure functions over the layout tree of one tab; nothing here writes state.
// Node kinds: terminal leaf {pane}, viewer leaf {viewer}, split {dir: "row"|"col", ratio, a, b}.
// The terminal block (the Ghostty split tree) is not a node: it is the smallest subtree that holds
// every terminal leaf, and the moves below never put a viewer inside it. A path is a string of
// "a" and "b" from the root; "" is the root. Counterpart of Ghostty's SplitTree.
export const isTerm = (n) => "pane" in n;
export const isSplit = (n) => "dir" in n;
export const leafId = (n) => n.pane ?? n.viewer;

export function leaves(n, out = []) {
  if (isSplit(n)) { leaves(n.a, out); leaves(n.b, out); } else out.push(n);
  return out;
}
export const terminals = (n) => leaves(n).filter(isTerm);
export const viewers = (n) => leaves(n).filter((x) => !isTerm(x));

export const at = (n, path) => [...path].reduce((node, side) => node[side], n);

export function setAt(n, path, node) {
  if (!path) return node;
  return { ...n, [path[0]]: setAt(n[path[0]], path.slice(1), node) };
}

export function pathOf(n, id, path = "") {
  if (!isSplit(n)) return leafId(n) === id ? path : null;
  return pathOf(n.a, id, `${path}a`) ?? pathOf(n.b, id, `${path}b`);
}

// Longest common prefix of the terminal leaf paths.
export function blockPath(n) {
  const paths = terminals(n).map((t) => pathOf(n, t.pane));
  return paths.reduce((a, b) => {
    let i = 0;
    while (i < a.length && a[i] === b[i]) i++;
    return a.slice(0, i);
  });
}

// The tree without the leaf; null when the leaf was the whole tree.
export function remove(n, id) {
  if (!isSplit(n)) return leafId(n) === id ? null : n;
  const a = remove(n.a, id), b = remove(n.b, id);
  if (!a) return b;
  if (!b) return a;
  return { ...n, a, b };
}

const FIRST = { left: true, top: true };
export function join(target, node, zone) {
  const first = FIRST[zone] ?? false;
  return { dir: zone === "left" || zone === "right" ? "row" : "col", ratio: 0.5, a: first ? node : target, b: first ? target : node };
}

// Put `node` beside a target on the side `zone`. If the node is already in the tree it moves.
// target: "root" | "block" | {leaf: id} | {child: "a"|"b"}, resolved after the node is taken out.
export function place(root, node, zone, target) {
  const rest = pathOf(root, leafId(node)) === null ? root : remove(root, leafId(node));
  if (!rest) return root;
  const path = target === "root" ? ""
    : target === "block" ? blockPath(rest)
      : target.leaf ? pathOf(rest, target.leaf)
        : target.child;
  return setAt(rest, path, join(at(rest, path), node, zone));
}

export const AXIS = { left: "row", right: "row", up: "col", down: "col" };
const CLAMP = [0.1, 0.9];

// Move the nearest divider on the axis of `dir` by `step`, as Ghostty's resize_split.
export function resize(root, id, dir, step) {
  const path = pathOf(root, id);
  for (let i = path.length - 1; i >= 0; i--) {
    const split = at(root, path.slice(0, i));
    if (split.dir !== AXIS[dir]) continue;
    const delta = dir === "left" || dir === "up" ? -step : step;
    const ratio = Math.min(CLAMP[1], Math.max(CLAMP[0], split.ratio + delta));
    return setAt(root, path.slice(0, i), { ...split, ratio });
  }
  return root;
}

export const setRatio = (root, path, ratio) =>
  setAt(root, path, { ...at(root, path), ratio: Math.min(0.85, Math.max(0.15, ratio)) });

// Weight of a subtree along an axis, as Ghostty's equalize: same-axis splits add up.
function weight(n, dir) {
  if (!isSplit(n)) return 1;
  const a = weight(n.a, dir), b = weight(n.b, dir);
  return n.dir === dir ? a + b : Math.max(a, b);
}
export function equalize(n) {
  if (!isSplit(n)) return n;
  const a = equalize(n.a), b = equalize(n.b);
  return { ...n, a, b, ratio: weight(a, n.dir) / (weight(a, n.dir) + weight(b, n.dir)) };
}

// Same tree without the ratios: when it is equal, a render only moves dividers.
export const shape = (n) => (isSplit(n) ? { dir: n.dir, a: shape(n.a), b: shape(n.b) } : n);
