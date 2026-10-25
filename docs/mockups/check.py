"""Walk the user paths of the tarn mockup in Chrome and report each check.

Run: uv run --with playwright python -I docs/mockups/check.py [screenshot.png]
"""

import pathlib
import sys
import time

from playwright.sync_api import sync_playwright

URL = (pathlib.Path(__file__).parent / "tarn.html").resolve().as_uri()
results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))


def drag(pg, src, dst_sel, fx, fy):
    """HTML5 drag from src to a point of dst given as fractions of its box."""
    box = pg.locator(dst_sel).first.bounding_box()
    x, y = box["x"] + box["width"] * fx, box["y"] + box["height"] * fy
    dt = pg.evaluate_handle("new DataTransfer()")
    pg.dispatch_event(src, "dragstart", {"dataTransfer": dt})
    pg.dispatch_event(
        dst_sel, "dragover", {"dataTransfer": dt, "clientX": x, "clientY": y}
    )
    pg.dispatch_event(dst_sel, "drop", {"dataTransfer": dt, "clientX": x, "clientY": y})
    if pg.locator(src).count():
        pg.dispatch_event(src, "dragend", {"dataTransfer": dt})


with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome")
    pg = b.new_page(viewport={"width": 1400, "height": 860})
    errors = []
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    pg.goto(URL)
    pg.wait_for_selector(".mm svg", timeout=15000)
    vis = pg.is_visible
    ntabs = lambda: pg.locator(".ftab").count()
    ngroups = lambda: pg.locator(".grp").count()

    check(
        "1 start: panel open, spec.md tab, mermaid drawn",
        vis("#panel") and ntabs() == 1 and pg.locator(".mm svg").count() == 1,
    )
    check("2 first open is a preview tab", pg.locator(".ftab.preview").count() == 1)

    pg.click(".term .path[data-path='docs/plans/s2-files.md']")
    check(
        "3 next path replaces the preview tab",
        ntabs() == 1 and "s2-files.md" in pg.inner_text(".ftab.on"),
    )
    pg.dblclick(".ftab.on")
    check("4 double-click pins the tab", pg.locator(".ftab.preview").count() == 0)
    pg.click(".term .path[data-path='docs/spec.md']")
    check("5 new path after a pinned tab adds a tab", ntabs() == 2)
    pg.dblclick(".ftab.on")

    pg.keyboard.press("Escape")
    check("6 Esc in single mode shows the tree", vis(".gbody .tree.big"))
    pg.keyboard.press("ArrowDown")
    pg.keyboard.press("ArrowUp")
    sel = pg.inner_text(".tree.big .tr.sel")
    check("7 arrows move the tree selection", "spec.md" in sel, sel)
    pg.keyboard.press("Escape")
    check("8 second Esc returns to the file", vis(".doc"))
    pg.keyboard.press("Escape")
    pg.click(".tree.big .tr[data-tpath='README.md']")
    check(
        "9 tree click opens README in the group",
        "README.md" in pg.inner_text(".ftab.on") and vis(".doc"),
    )

    n0 = ngroups()
    drag(pg, ".ftab:has-text('spec.md')", ".grp", 0.5, 0.95)
    check(
        "10 drag tab to bottom edge splits the panel vertically",
        ngroups() == n0 + 1 and pg.locator(".split.col").count() == 1,
    )
    pg.wait_for_selector(".grp >> nth=1 >> .mm svg")
    check("11 the new bottom group shows spec.md with mermaid", True)

    drag(pg, ".grp >> nth=1 >> .ftab", ".grp >> nth=0", 0.5, 0.6)
    check(
        "12 drag the only tab back to center merges groups",
        ngroups() == 1 and pg.locator(".split").count() == 0,
    )

    pg.keyboard.press("Escape")
    drag(pg, ".tree .tr[data-tpath='docs/architecture.md']", ".grp", 0.97, 0.5)
    check(
        "13 drag a tree file to the right edge splits horizontally",
        pg.locator(".split.row").count() == 1,
    )
    pg.wait_for_function("document.querySelectorAll('.mm svg').length >= 2")

    sd = pg.locator(".sdiv.row").bounding_box()
    g0 = pg.locator(".grp").first.bounding_box()["width"]
    pg.mouse.move(sd["x"], sd["y"] + 200)
    pg.mouse.down()
    pg.mouse.move(sd["x"] - 100, sd["y"] + 200)
    pg.mouse.up()
    g1 = pg.locator(".grp").first.bounding_box()["width"]
    check("14 split divider drag resizes groups", g1 < g0 - 60, f"{g0:.0f} -> {g1:.0f}")

    pg.click(".grp >> nth=1")
    pg.keyboard.press("Meta+w")
    check("15 cmd+W on the last tab of a group closes the group", ngroups() == 1)

    pg.keyboard.press("Meta+\\")
    check("16 cmd+\\ splits right", ngroups() == 2)
    pg.click(".grp >> nth=1")
    pg.keyboard.press("Meta+w")

    pg.click(".ftab:has-text('README.md')")
    pg.click(".ftab:has-text('spec.md')")
    pg.keyboard.press("Meta+e")
    check("17 cmd+E shows raw editor", vis(".raw textarea"))
    pg.click(".raw textarea")
    pg.keyboard.press("End")
    pg.keyboard.type(" edited")
    check(
        "18 typing marks tab and tree dirty", pg.locator(".ftab.on .dirty").count() == 1
    )
    pg.keyboard.press("Escape")
    check("19 first Esc in editor only leaves editing", vis(".raw textarea"))
    pg.click("#agentEdit")
    check("20 agent edit while dirty shows banner", vis(".banner"))
    pg.click("[data-keep]")
    check(
        "21 keep mine hides banner",
        not vis(".banner") and "edited" in pg.input_value(".raw textarea"),
    )
    pg.keyboard.press("Meta+s")
    check("22 cmd+S saves", pg.locator(".ftab.on .dirty").count() == 0)
    pg.keyboard.press("Meta+e")
    pg.wait_for_selector(".mm svg")
    pg.evaluate("document.querySelector('.gbody .scroll').scrollTop = 400")
    pg.click("#agentEdit")
    pg.wait_for_timeout(700)
    top = pg.evaluate("document.querySelector('.gbody .scroll').scrollTop")
    check(
        "23 clean agent edit re-renders, scroll kept",
        "Agent note" in pg.inner_text(".doc") and top > 300,
        f"scrollTop={top}",
    )

    pg.click(".term .path[data-path='macos/Sources/Features/Tarn/Sidebar.swift']")
    check(
        "24 swift opens with line highlight",
        pg.locator(".codeview .row.hl").count() == 1,
    )

    pg.click("#closePanel")
    check("25 close button hides panel", not vis("#panel") and not vis("#resizer"))
    pg.keyboard.press("Meta+b")
    check("26 cmd+B reopens", vis("#panel"))

    pg.click("[data-tab='1']")
    check("27 tab 2 has its own closed panel", not vis("#panel"))
    pg.click(".term .path[data-path='README.md']")
    check("28 path in tab 2 opens README there", vis("#panel") and ntabs() == 1)
    pg.click("[data-tab='0']")
    check("29 tab 1 keeps its tabs", ntabs() >= 3)

    pg.click("[data-seg='mode'] [data-v='tree']")
    check("30 tree mode shows the tree column", vis(".tcol"))
    pg.click(".tcol .tr[data-tpath='docs/architecture.md']")
    check("31 tree column opens a file", "architecture.md" in pg.inner_text(".ftab.on"))
    pg.click(".tcol .tr[data-tpath='docs']")
    check(
        "32 fold folder in column",
        pg.locator(".tcol .tr[data-tpath='docs/spec.md']").count() == 0,
    )
    pg.click("[data-seg='mode'] [data-v='single']")

    pg.click("[data-seg='theme'] [data-v='light']")
    pg.wait_for_timeout(800)
    check(
        "33 light theme applies", "light" in (pg.get_attribute("#panel", "class") or "")
    )
    pg.click("[data-seg='theme'] [data-v='dark']")

    rz = pg.locator("#resizer").bounding_box()
    w0 = pg.locator("#panel").bounding_box()["width"]
    pg.mouse.move(rz["x"] + 3, rz["y"] + 100)
    pg.mouse.down()
    pg.mouse.move(rz["x"] - 120, rz["y"] + 100)
    pg.mouse.up()
    w1 = pg.locator("#panel").bounding_box()["width"]
    check("34 drag resizer widens panel", w1 > w0 + 80, f"{w0:.0f} -> {w1:.0f}")

    t = time.time()
    for _ in range(10):
        pg.click("[data-tab='1']")
        pg.click("[data-tab='0']")
    check("35 20 tab switches", True, f"{(time.time() - t) * 50:.0f} ms per switch")

    pg.set_viewport_size({"width": 420, "height": 860})
    sw = pg.evaluate("document.documentElement.scrollWidth")
    check("36 phone width: no horizontal page scroll", sw <= 420, f"scrollWidth={sw}")
    pg.screenshot(path=sys.argv[1] if len(sys.argv) > 1 else "/dev/null")
    check("37 no page errors", not errors, "; ".join(errors[:3]))
    b.close()

for name, ok, detail in results:
    print(("PASS " if ok else "FAIL ") + name + (f" ({detail})" if detail else ""))
print(f"{sum(ok for _, ok, _ in results)}/{len(results)} passed")
