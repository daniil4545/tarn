// Node tests of the theme data and the window colors derived from it. Run: node --test demo/test/unit
import test from "node:test";
import assert from "node:assert/strict";
import { BASE_THEMES, BASE_SINGLES, THEME_NAMES, themeFor } from "../../js/themes.js";
import { deriveChrome, pickAccent } from "../../js/chrome-theme.js";
import { contrast, isLight, mix } from "../../js/color.js";

test("every theme file of Ghostty is listed", () => {
  assert.equal(THEME_NAMES.length, 771);
});

test("base themes exist and each pair is a light theme then a dark theme", () => {
  assert.ok(BASE_THEMES.length >= 2 && BASE_THEMES.length <= 3);
  for (const [light, dark] of BASE_THEMES) {
    assert.ok(THEME_NAMES.includes(light) && THEME_NAMES.includes(dark), `${light} / ${dark}`);
    assert.equal(isLight(themeFor(light).background), true, light);
    assert.equal(isLight(themeFor(dark).background), false, dark);
  }
});

test("single base themes exist", () => {
  assert.deepEqual(BASE_SINGLES, ["Dracula"]);
  for (const name of BASE_SINGLES) assert.ok(THEME_NAMES.includes(name), name);
});

test("the default and an unknown name give the Ghostty default theme", () => {
  assert.equal(themeFor("").background, "#282c34");
  assert.equal(themeFor("no such theme"), themeFor(""));
});

test("window colors come from the theme background, text and a readable palette accent", () => {
  for (const name of ["", ...THEME_NAMES]) {
    const t = themeFor(name), c = deriveChrome(t);
    assert.equal(c.bg, t.background);
    assert.equal(c.fg, t.foreground);
    assert.equal(c.light, isLight(t.background));
    assert.ok(c.accent === t.foreground || contrast(c.accent, t.background) >= 3, name);
    assert.ok(Object.values(c).every((v) => typeof v === "boolean" || /^#[0-9a-f]{6}$/.test(v)), name);
  }
});

test("surface colors sit between the background and the text", () => {
  const c = deriveChrome(themeFor("Catppuccin Mocha"));
  assert.equal(c.bg, "#1e1e2e");
  assert.equal(c.chrome, mix(c.bg, c.fg, 0.06));
  assert.equal(c.accent, pickAccent(themeFor("Catppuccin Mocha")));
  assert.equal(c.accent, "#89b4fa");
});
