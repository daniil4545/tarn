"""Slice C checks: viewer panes, the settings window, Help. Mockup checks of this area keep their names.

Run: nice -n 10 uv run --with playwright python -I demo/test/check_c.py
Runs on the real index.html. The spec of the repository gets a fixture text (tasks, links, a
diagram, length) written through vfs.write, as an agent's edit would.
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from lib import Checks, app_page, cmd, server

check = Checks()
ROOT = "/Users/you/code/tarn"
SPEC = f"{ROOT}/docs/spec.md"
VIEWER = '.tabview:not([hidden]) .leaf[data-kind="viewer"]'
FILLER = "\n\n".join(
    f"Paragraph {i} of the spec text, long enough to scroll the page."
    for i in range(1, 61)
)
SPEC_TEXT = f"""# Spec

```mermaid
graph LR
  A --> B
```

- [ ] first task
- [x] second task

See [the plan](plans/s2-files.md) and [missing](nope.md).

Raw <b>html</b> <img src="raw.png"> stays text.

{FILLER}
"""


def vfs_text(pg, path):
    return pg.evaluate("p => __tarn.snapshot().vfs.files[p].text", path)


def viewers(pg):
    return pg.locator(VIEWER).count()


def focus_viewer(pg):
    """Click the active file tab: keyboard focus goes into the viewer page."""
    pg.wait_for_function(
        "[...document.querySelectorAll('.viewer-pane iframe')].every("
        "(f) => f.contentDocument?.readyState === 'complete' && f.contentWindow.tarn"
        " && f.contentDocument.querySelector('.ftab.on'))"
    )
    pg.frame_locator(f"{VIEWER} iframe").first.locator(".ftab.on").click()


def viewer_checks(pg):
    v = pg.frame_locator(f"{VIEWER} iframe").first
    vis = lambda sel: v.locator(sel).first.is_visible()
    count = lambda sel: v.locator(sel).count()
    tree = "#vtree:not([hidden])"

    def open_file(path, line=None):
        cmd(pg, "viewer.open", {"path": path, "line": line})

    def x_of(sel):
        return v.locator(sel).first.bounding_box()["x"]

    open_file("docs/spec.md")
    v.locator(".mm svg").wait_for(timeout=20000)
    check(
        "C1 a path makes a viewer pane, the tree is hidden",
        viewers(pg) == 1 and count(tree) == 0,
    )
    # spec: docs/spec.md 2.5.4 - raw HTML inside markdown is escaped.
    check(
        "C1a raw HTML in markdown is shown as text",
        count("#vcontent b") == 0
        and count("#vcontent img") == 0
        and "<b>html</b>" in v.locator("#vcontent").inner_text(),
    )
    focus_viewer(pg)
    check("3 the file opens as a preview tab", count(".ftab.preview") == 1)
    open_file("docs/plans/s2-files.md")
    v.locator(".ftab.on", has_text="s2-files.md").wait_for()
    check("4 next path replaces the preview tab", count(".ftab") == 1)
    v.locator(".ftab.on").dblclick()
    check("5 double click pins the tab", count(".ftab.preview") == 0)
    open_file("docs/spec.md")
    v.locator(".ftab.on", has_text="spec.md").wait_for()
    v.locator(".ftab.on").dblclick()
    check("6 path after a pinned tab adds a tab", count(".ftab") == 2)

    v.locator("[data-act=tree]").click()
    v.locator(tree).wait_for()
    check(
        "7 the Files button shows the files tree on the right of the viewer",
        x_of(tree) > x_of("#vcontent"),
    )
    v.locator(".tr[data-path$='/README.md']").click()
    v.locator(".ftab.on", has_text="README.md").wait_for()
    check("8 tree click opens the file, tree stays", vis(tree))
    paths = v.locator(".tr").evaluate_all("els => els.map(e => e.dataset.path)")
    up = paths.index(f"{ROOT}/README.md") - paths.index(f"{ROOT}/docs/architecture.md")
    v.locator("#vtree .tree").focus()  # opening a file moved the keyboard to the file
    for _ in range(up):
        pg.keyboard.press("ArrowUp")
    pg.keyboard.press("Enter")
    v.locator(".ftab.on", has_text="architecture.md").wait_for()
    check(
        "9 arrows and Enter in the tree open a file",
        "architecture.md" in v.locator(".ftab.on").inner_text(),
    )
    v.locator("#vtree .tree").focus()
    pg.keyboard.press("Escape")
    check("10 Esc hides the tree", count(tree) == 0)
    v.locator("[data-act=tree]").click()
    check("11 title button shows the tree", vis(tree))
    v.locator("[data-act=tree]").click()
    check("12 viewer Files button hides the tree", count(tree) == 0)

    v.locator(".ftab", has_text="spec.md").click()
    v.locator(".mm svg").wait_for()
    pg.keyboard.press("Meta+e")
    v.locator(".cm-content").wait_for()
    check("27 cmd+E shows the raw editor", vis(".cm-content"))
    v.locator(".cm-content").click()
    pg.keyboard.press("End")
    pg.keyboard.type(" edited")
    v.locator(".ftab.on .dirty").wait_for()
    check("28 typing marks the tab dirty", count(".ftab.on .dirty") == 1)
    pg.keyboard.press("Escape")
    check("29 Esc in the editor only leaves editing", vis(".cm-content"))
    agent_write(pg, "\nAgent note\n")
    v.locator("#banner:not([hidden])").wait_for()
    check("30 agent edit while dirty shows the banner", vis("#banner"))
    v.locator("[data-keep]").click()
    check(
        "31 keep mine hides the banner",
        count("#banner:not([hidden])") == 0
        and "edited" in v.locator(".cm-content").inner_text(),
    )
    v.locator(".cm-content").click()
    pg.keyboard.press("Meta+s")
    v.locator(".ftab.on .dirty").wait_for(state="detached")
    saved = vfs_text(pg, SPEC)
    check("32 cmd+S saves", count(".ftab.on .dirty") == 0 and "edited" in saved)

    pg.keyboard.press("Meta+e")
    v.locator(".mm svg").wait_for()
    v.locator(".scroll").evaluate("e => { e.scrollTop = 400; }")
    agent_write(pg, "\nSecond agent note\n")
    v.locator(".doc", has_text="Second agent note").wait_for()
    top = v.locator(".scroll").evaluate("e => e.scrollTop")
    check("33 clean agent edit re-renders, scroll kept", top > 300, f"scrollTop={top}")

    open_file("macos/Sources/Features/Tarn/Sidebar.swift", 12)
    v.locator(".codeview").wait_for()
    check("34 swift opens with the line highlighted", count(".codeview .row.hl") == 1)

    cmd(pg, "config.set", {"key": "window-theme", "value": "light"})
    v.locator("html[data-theme=light]").wait_for()
    check("35 light viewer theme", count("html[data-theme=light]") == 1)
    cmd(pg, "config.reset", {"key": "window-theme"})

    task_checks(pg, v, open_file)
    key_checks(pg, v)
    close_checks(pg, v)


def agent_write(pg, note):
    """The agent appends a note to the spec, as its hook-driven edit does."""
    cmd(
        pg,
        "vfs.write",
        {"path": SPEC, "text": vfs_text(pg, SPEC) + note, "by": "agent"},
    )


def task_checks(pg, v, open_file):
    open_file("docs/spec.md")
    v.locator(".ftab.on", has_text="spec.md").wait_for()
    v.locator(".doc input[data-line]").first.wait_for()
    v.locator(".doc input[data-line]").first.click()
    pg.wait_for_function(
        "p => __tarn.snapshot().vfs.files[p].text.includes('- [x] first task')",
        arg=SPEC,
    )
    text = vfs_text(pg, SPEC)
    check(
        "C2 ticking a task box writes the file",
        "- [x] first task" in text
        and "- [x] second task" in text
        and "- [ ] first task" not in text,
        text[:120],
    )

    v.locator(".doc a", has_text="the plan").click()
    v.locator(".ftab.on", has_text="s2-files.md").wait_for()
    check(
        "C3 a relative link opens the file",
        "s2-files.md" in v.locator(".ftab.on").inner_text(),
        v.locator(".ftab.on").inner_text(),
    )
    open_file("docs/spec.md")
    v.locator(".doc a", has_text="missing").click()
    v.locator("#toast", has_text="No such file").wait_for()
    notice = v.locator("#toast").inner_text()
    check(
        "C4 a link to a missing file shows a notice and opens nothing",
        "No such file" in notice
        and "missing" not in v.locator(".ftab.on").inner_text(),
        notice,
    )


def key_checks(pg, v):
    pg.evaluate("window.calls.length = 0")
    pg.keyboard.press("Meta+d")
    pg.wait_for_function(
        "[...document.querySelectorAll('.viewer-pane iframe')].every((f) => f.contentDocument?.readyState === 'complete' && f.contentWindow?.tarn)"
    )
    pg.keyboard.press("Meta+Shift+d")
    splits = pg.evaluate(
        "window.calls.filter((c) => c[0] === 'pane.split').map((c) => c[1])"
    )
    check(
        "C5 cmd+D and shift+cmd+D split the viewer with the open file",
        [x["dir"] for x in splits] == ["right", "down"]
        and all(x["kind"] == "viewer" and x["path"].endswith(".md") for x in splits)
        and viewers(pg) == 3,
        str(splits),
    )
    focus_viewer(pg)
    before = v.locator(".ftab").count()
    pg.keyboard.press("Meta+w")
    pg.wait_for_function(
        "n => document.querySelector('.viewer-pane iframe').contentDocument.querySelectorAll('.ftab').length < n",
        arg=before,
    )
    check("C6 cmd+W closes the file tab", v.locator(".ftab").count() == before - 1)
    pg.keyboard.press("Control+Alt+w")
    pg.wait_for_function(
        "n => document.querySelector('.viewer-pane iframe').contentDocument.querySelectorAll('.ftab').length < n",
        arg=before - 1,
    )
    check(
        "C7 the Ctrl+Alt fallback closes the file tab too",
        v.locator(".ftab").count() == before - 2,
    )


def close_checks(pg, v):
    start = viewers(pg)
    while viewers(pg) == start and v.locator(".ftab").count():
        pg.keyboard.press("Meta+w")
        pg.wait_for_timeout(150)
    check("C8 closing the last file tab closes the pane", viewers(pg) == start - 1)
    while viewers(pg):
        focus_viewer(pg)
        pg.keyboard.press("Meta+w")
        pg.wait_for_timeout(150)
    pg.evaluate("document.activeElement.blur()")
    pg.keyboard.press("Meta+b")
    pg.frame_locator("iframe").locator("#vtree:not([hidden])").wait_for()
    check(
        "37 cmd+B with no viewer opens one with the tree",
        pg.frame_locator("iframe").locator("#vtree").is_visible()
        and pg.frame_locator("iframe").locator(".empty").first.is_visible(),
    )


def key_rows(pg):
    """How many key rows the demo defines: Help lists each once."""
    return pg.evaluate(
        """async () => {
          const names = ['tabs', 'splits', 'find', 'terminal', 'viewer', 'help'];
          const mods = await Promise.all(names.map((n) => import(`/js/keys/${n}.js`)));
          return mods.flatMap((m) => Object.values(m).flat()).length;
        }"""
    )


def settings_checks(pg):
    s = pg.locator
    vis = pg.is_visible

    def conf():
        pg.click("#setNav [data-sec='windows']")
        return s("#tarnConf").inner_text()

    def option(key, value):
        pg.fill(f"#g-{key}", str(value))
        pg.press(f"#g-{key}", "Tab")

    pg.evaluate("document.activeElement.blur()")
    pg.keyboard.press("Meta+Comma")
    check("S1 cmd+, opens the settings window", vis("#settings"))
    pg.keyboard.press("Escape")
    check("S3 Escape closes the settings window", not vis("#settings"))
    pg.keyboard.press("Control+Alt+Comma")
    check("S1a the Ctrl+Alt fallback opens the settings window", vis("#settings"))
    pg.click("#settingsClose")
    check("S3a the red light closes the settings window", not vis("#settings"))

    pg.keyboard.press("Meta+Comma")
    pg.click("input[name=tabstyle][value=top]")
    check(
        "S2a the tab style radio writes tab-style",
        pg.evaluate("__tarn.snapshot().config['tab-style']") == "top",
    )
    pg.click("input[name=tabstyle][value=sidebar]")

    pg.click("#setNav [data-sec='appearance']")
    check(
        "S7 a section shows its Ghostty options only",
        vis("[data-opt='font-size']") and not vis("[data-opt='drag-handle']"),
    )
    option("font-size", 16)
    check(
        "S8 a changed option is marked as set in tarn and applies",
        vis("[data-opt='font-size'] .set")
        and pg.evaluate("__tarn.snapshot().config['font-size']") == 16,
    )
    check(
        "S8a only non-live options show when they apply",
        "Restart needed" in s("[data-opt='background-opacity']").inner_text()
        and "Applies to new windows"
        in s("[data-opt='macos-titlebar-style']").inner_text()
        and s("[data-opt='font-size'] .applies").count() == 0,
    )
    option("font-size", 13)
    check("S8b a value equal to the default keeps its line", "font-size = 13" in conf())
    pg.click("#setNav [data-sec='appearance']")
    option("font-size", 16)
    pg.click("#setNav [data-sec='windows']")
    pg.select_option("#g-drag-handle", "never")
    lines = s("#tarnConf").inner_text().splitlines()
    check(
        "S9 the tarn file lists only changed options",
        lines == ["font-size = 16", "drag-handle = never"],
        repr(lines),
    )
    pg.click("[data-greset='drag-handle']")
    check(
        "S10 Reset removes the line and the mark",
        "drag-handle" not in s("#tarnConf").inner_text()
        and s("[data-opt='drag-handle'] .set").count() == 0,
    )
    pg.click("#setNav [data-sec='help']")
    text = s("[data-pane='help']").inner_text()
    check(
        "S11 Help lists Ghostty and tarn keys",
        "⌥⌘W" in text and "⌘B" in text and "keybind" in text,
    )
    check(
        "S11a Help shows the Ctrl+Alt fallback of a row",
        "Ctrl+Alt+W" in text and "Ctrl+Alt+T" in text,
    )
    check(
        "S11b Help lists every key row once",
        s("[data-pane='help'] tr:has(td.src)").count() == key_rows(pg),
    )
    pg.keyboard.press("Escape")

    option_rows_check(pg)
    effect_checks(pg)

    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='appearance']")
    option("font-size", 16)
    pg.click("#settingsClose")
    pg.reload()
    pg.wait_for_function("document.documentElement.dataset.ready")
    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='appearance']")
    check(
        "S12 set options survive a reload",
        pg.evaluate("__tarn.snapshot().config['font-size']") == 16
        and vis("[data-opt='font-size'] .set"),
    )


def option_rows_check(pg):
    """Every row of every section: a change writes the line and the mark, Reset removes both."""
    bad = []
    pg.keyboard.press("Meta+Comma")
    for sec in ("appearance", "terminal", "windows"):
        pg.click(f"#setNav [data-sec='{sec}']")
        keys = pg.eval_on_selector_all(
            f"[data-pane='{sec}'] [data-opt]", "els => els.map(e => e.dataset.opt)"
        )
        for key in keys:
            if key == "font-size":
                continue
            pg.evaluate(CHANGE, key)
            written = pg.is_visible(f"[data-opt='{key}'] .set")
            pg.click(f"[data-greset='{key}']")
            if not written or pg.locator(f"[data-opt='{key}'] .set").count():
                bad.append(key)
    check(
        "S13 every option row writes its line and Reset removes it",
        not bad,
        ", ".join(bad),
    )
    pg.click("#settingsClose")


# Changes the control of a row to another value the way a user does, and fires the change event.
CHANGE = """key => {
  const el = document.getElementById('g-' + key);
  if (el.type === 'checkbox') el.checked = !el.checked;
  else if (el.tagName === 'SELECT') el.value = el.options[el.selectedIndex === 0 ? 1 : 0].value;
  else if (el.type === 'range') el.value = el.min;
  else if (el.type === 'number') el.value = el.min;
  else el.value = 'Fira Code';
  el.dispatchEvent(new Event('change', { bubbles: true }));
}"""


def effect_checks(pg):
    cfg = lambda k, v: cmd(pg, "config.set", {"key": k, "value": v})
    theme = lambda: pg.evaluate("document.documentElement.dataset.theme")
    cfg("window-theme", "light")
    light = theme()
    cfg("window-theme", "dark")
    dark = theme()
    pg.emulate_media(color_scheme="light")
    cfg("window-theme", "auto")
    auto_light = theme()
    pg.emulate_media(color_scheme="dark")
    pg.wait_for_function("document.documentElement.dataset.theme === 'dark'")
    check(
        "S14 window-theme forces light or dark and auto follows the system",
        (light, dark, auto_light) == ("light", "dark", "light"),
        str((light, dark, auto_light)),
    )
    cfg("background-opacity", 0.5)
    cfg("background-blur", True)
    bg = pg.evaluate(
        "getComputedStyle(document.getElementById('window')).backgroundColor"
    )
    blur = pg.evaluate(
        "getComputedStyle(document.getElementById('window')).backdropFilter"
    )
    check(
        "S15 background-opacity and background-blur reach the window",
        "0.5" in bg and blur == "blur(20px)",
        f"{bg} {blur}",
    )
    cfg("background-opacity", 1)
    cfg("background-blur", False)

    cfg("mouse-hide-while-typing", True)
    pg.keyboard.press("a")
    hidden = pg.evaluate("getComputedStyle(document.body).cursor")
    # A pointer over a viewer iframe never reaches the page: move it over the settings overlay.
    cmd(pg, "settings.open")
    pg.mouse.move(40, 40)
    pg.mouse.move(60, 60)
    shown = pg.evaluate("getComputedStyle(document.body).cursor")
    check(
        "S16 mouse-hide-while-typing hides the pointer until it moves",
        hidden == "none" and shown != "none",
        f"{hidden} {shown}",
    )
    pg.click("#settingsClose")
    cfg("mouse-hide-while-typing", False)

    pg.evaluate("localStorage.setItem('tarn-demo-v1:workspaces', '{}')")
    pg.evaluate("dispatchEvent(new Event('pagehide'))")
    kept = pg.evaluate("localStorage.getItem('tarn-demo-v1:workspaces')")
    cfg("window-save-state", "never")
    pg.evaluate("dispatchEvent(new Event('pagehide'))")
    gone = pg.evaluate("localStorage.getItem('tarn-demo-v1:workspaces')")
    check(
        "S17 window-save-state never keeps no layout in storage",
        kept == "{}" and gone is None,
        f"{kept} {gone}",
    )
    cfg("window-save-state", "default")

    pg.evaluate("document.activeElement.blur()")
    pg.evaluate(
        """async () => {
          const { bus } = await import('/js/bus.js');
          window.reloaded = [];
          bus.on('config:changed', ({ key }) => window.reloaded.push(key));
        }"""
    )
    pg.keyboard.press("Meta+Shift+Comma")
    pg.wait_for_selector("#toast:has-text('config reloaded')")
    keys = pg.evaluate("window.reloaded")
    check(
        "S18 reload the Ghostty config toasts and re-applies every option",
        len(set(keys)) >= 20 and "font-size" in keys and "theme" in keys,
        f"{len(set(keys))} keys",
    )


def path_checks(pg):
    got = pg.evaluate(
        """async () => {
          const { resolve, setTask } = await import('/js/viewer-paths.js');
          const exists = (p) => p === '/h/a:b.md' || p === '/h/x/a.go';
          const env = { cwd: '~/x', home: '/h', exists };
          return [resolve('a.go:42:7', env), resolve('~/a:b.md', env), resolve('../x/./a.go', env),
                  setTask('- [ ] a\\n> 1. [x] b', 1, false), setTask('plain', 0, true)];
        }"""
    )
    check(
        "P1 path click: line suffix is split off when no such file exists",
        got[0] == {"path": "/h/x/a.go", "line": 42},
    )
    check(
        "P2 path click: a real file with a colon in its name wins",
        got[1] == {"path": "/h/a:b.md", "line": None},
    )
    check(
        "P3 path click: dots resolve against the cwd",
        got[2] == {"path": "/h/x/a.go", "line": None},
    )
    check(
        "P4 task write-back works in quotes and refuses a plain line",
        got[3] == "- [ ] a\n> 1. [ ] b" and got[4] is None,
    )


def main():
    with server() as base:  # noqa: SIM117 (the page needs the server address)
        with app_page(base) as (pg, errors, requests):
            cmd(pg, "vfs.write", {"path": SPEC, "text": SPEC_TEXT, "by": "test"})
            path_checks(pg)
            viewer_checks(pg)
            settings_checks(pg)
            external = [r for r in requests if not r.startswith(base)]
            check(
                "X1 no request leaves the demo origin", not external, str(external[:3])
            )
            check("44 no page errors", not errors, "; ".join(errors[:3]))
    check.exit()


main()
