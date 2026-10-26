// Small color math on "#rrggbb" strings, shared by the theme code and the settings preview.
const channels = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
const hex2 = (n) => Math.round(Math.min(255, Math.max(0, n))).toString(16).padStart(2, "0");

// `a` with `amount` (0..1) of `b` mixed in.
export function mix(a, b, amount) {
  const [ca, cb] = [channels(a), channels(b)];
  return `#${ca.map((v, i) => hex2(v + (cb[i] - v) * amount)).join("")}`;
}

// WCAG relative luminance, 0 (black) to 1 (white).
export function luminance(hex) {
  const [r, g, b] = channels(hex).map((v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export const isLight = (hex) => luminance(hex) > 0.4;

// WCAG contrast ratio, 1 to 21.
export function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}
