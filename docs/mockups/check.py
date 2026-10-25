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
    pos = {"dataTransfer": dt, "clientX": x, "clientY": y}
    pg.locator(src).first.dispatch_event("dragstart", {"dataTransfer": dt})
    pg.locator(dst_sel).first.dispatch_event("dragover", pos)
    pg.locator(dst_sel).first.dispatch_event("drop", pos)
    pg.evaluate("document.dispatchEvent(new Event('dragend'))")


with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome")
    pg = b.new_page(viewport={"width": 1400, "height": 860})
    errors = []
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    pg.goto(URL)
    pg.wait_for_selector(".tpane")
    vis = pg.is_visible
    n = pg.locator

    def count(sel):
        return pg.locator(sel).count()

    def x_of(sel):
        return pg.locator(sel).first.bounding_box()["x"]

    check(
        "1 start: one terminal, no viewer",
        count(".tpane") == 1 and count(".vpane") == 0,
    )

    pg.click(".term .path[data-path='docs/spec.md']")
    pg.wait_for_selector(".vpane .mm svg", timeout=15000)
    check(
        "2 path click opens a viewer right of the terminal, tree hidden",
        count(".vpane") == 1
        and count(".vtree") == 0
        and x_of(".vpane") > x_of(".tpane"),
    )
    check("3 the file opens as a preview tab", count(".ftab.preview") == 1)
    pg.click(".term .path[data-path='docs/plans/s2-files.md']")
    check(
        "4 next path replaces the preview tab",
        count(".ftab") == 1 and "s2-files.md" in pg.inner_text(".ftab.on"),
    )
    pg.dblclick(".ftab.on")
    check("5 double click pins the tab", count(".ftab.preview") == 0)
    pg.click(".term .path[data-path='docs/spec.md']")
    pg.dblclick(".ftab.on")
    check("6 path after a pinned tab adds a tab", count(".ftab") == 2)

    pg.keyboard.press("Meta+b")
    check(
        "7 cmd+B shows the files tree on the right of the viewer",
        vis(".vtree") and x_of(".vtree") > x_of(".vcontent"),
    )
    pg.click(".vtree .tr[data-tpath='README.md']")
    check(
        "8 tree click opens the file, tree stays",
        "README.md" in pg.inner_text(".ftab.on") and vis(".vtree"),
    )
    pg.keyboard.press("ArrowDown")
    pg.keyboard.press("ArrowDown")
    pg.keyboard.press("Enter")
    check(
        "9 arrows and Enter in the tree open a file",
        "architecture.md" in pg.inner_text(".ftab.on"),
        pg.inner_text(".ftab.on"),
    )
    pg.keyboard.press("Escape")
    check("10 Esc hides the tree", count(".vtree") == 0)
    pg.click("#toggleFiles")
    check("11 title button shows the tree", vis(".vtree"))
    pg.click("[data-vtree]")
    check("12 viewer Files button hides the tree", count(".vtree") == 0)

    pg.click(".tpane")
    pg.keyboard.press("Meta+d")
    check("13 cmd+D in a terminal splits the terminal", count(".tpane") == 2)
    pg.keyboard.press("Meta+Shift+d")
    check(
        "14 cmd+shift+D splits down, 4 panes",
        count(".tpane") == 3 and count(".split.col") == 1,
    )
    pg.keyboard.press("Meta+d")
    check("15 no pane limit: a fifth pane opens", count("[data-pid]") == 5)
    check("16 terminals stay in one block", count(".block .tpane") == 4)
    pg.keyboard.press("Meta+w")
    pg.keyboard.press("Meta+z")
    check("16a cmd+Z brings back a closed terminal", count(".tpane") == 4)
    pg.keyboard.press("Meta+w")
    pg.click(".tpane >> nth=-1 >> .term")

    focus0 = n(".focus").get_attribute("data-pid")
    pg.keyboard.press("Meta+Alt+ArrowRight")
    check(
        "17 cmd+alt+right moves focus to the viewer",
        n(".focus").get_attribute("class").startswith("vpane"),
        f"from {focus0}",
    )
    pg.keyboard.press("Meta+[")
    check("18 cmd+[ moves to the previous pane", n(".tpane.focus").count() == 1)
    pg.keyboard.press("Meta+Shift+Enter")
    check("19 cmd+shift+Enter zooms one pane", count("[data-pid]") == 1)
    pg.keyboard.press("Meta+Shift+Enter")
    check("20 again restores the layout", count("[data-pid]") == 4)
    pg.keyboard.press("Meta+w")
    check("21 cmd+W closes a terminal", count(".tpane") == 2)
    check("21a every terminal has a grab handle", count(".grip") == count(".tpane"))
    drag(pg, ".tpane >> nth=0 >> .grip", ".tpane >> nth=1", 0.5, 0.95)
    check(
        "21b drag a terminal grab handle to a terminal bottom edge stacks them",
        count(".block > .split.col") == 1 and count(".tpane") == 2,
    )
    drag(pg, ".tpane >> nth=0 >> .grip", ".vpane", 0.9, 0.5)
    check(
        "21c a terminal dropped on a viewer is refused",
        count(".block .tpane") == 2 and count(".block > .split.col") == 1,
    )

    drag(pg, ".ftab:has-text('spec.md')", ".vpane", 0.5, 0.95)
    check(
        "22 drag a tab to the viewer bottom edge splits the viewer",
        count(".vpane") == 2 and count(".split.col") >= 1,
    )
    drag(pg, ".vpane >> nth=0 >> .ftab", ".tpane", 0.02, 0.5)
    first = n("[data-pid]").first.get_attribute("class")
    check(
        "23 drop on a terminal edge puts the viewer beside the block",
        count(".vpane") == 3
        and first.startswith("vpane")
        and count(".block .vpane") == 0,
    )
    drag(pg, ".vpane >> nth=0 >> .ftab", ".vpane >> nth=1", 0.5, 0.6)
    check("25 drop the only tab in a viewer center merges", count(".vpane") == 2)
    pg.click("[data-vclose] >> nth=0")
    pg.keyboard.press("Meta+z")
    check("25a cmd+Z brings back a closed viewer", count(".vpane") == 2)

    def dots():
        return pg.evaluate(
            "getComputedStyle(document.querySelector('.tpane .grip svg')).opacity"
        )

    pg.mouse.move(5, 5)
    check("25b grab handle dots are hidden away from the pane top", dots() == "0")
    box = n(".tpane").first.bounding_box()
    pg.mouse.move(box["x"] + 30, box["y"] + 20)
    pg.wait_for_timeout(200)
    check("25c dots show in the top band of the pane", dots() == "0.3", dots())
    pg.click("[data-seg='header'] [data-v='never']")
    check("25d drag-handle never removes the handle", not vis(".grip"))
    pg.click("[data-seg='header'] [data-v='auto']")

    sd = n(".sdiv.row").first.bounding_box()
    w0 = n("[data-pid]").first.bounding_box()["width"]
    pg.mouse.move(sd["x"], sd["y"] + 200)
    pg.mouse.down()
    pg.mouse.move(sd["x"] + 120, sd["y"] + 200)
    pg.mouse.up()
    w1 = n("[data-pid]").first.bounding_box()["width"]
    check("26 split divider drag resizes", w1 > w0 + 60, f"{w0:.0f} -> {w1:.0f}")

    pg.click(".vpane .ftab:has-text('spec.md')")
    pg.wait_for_selector(".vpane .mm svg")
    pg.keyboard.press("Meta+e")
    check("27 cmd+E shows the raw editor", vis(".raw textarea"))
    pg.click(".raw textarea")
    pg.keyboard.press("End")
    pg.keyboard.type(" edited")
    check("28 typing marks the tab dirty", count(".ftab.on .dirty") == 1)
    pg.keyboard.press("Escape")
    check("29 Esc in the editor only leaves editing", vis(".raw textarea"))
    pg.click("#agentEdit")
    check("30 agent edit while dirty shows the banner", vis(".banner"))
    pg.click("[data-keep]")
    check(
        "31 keep mine hides the banner",
        not vis(".banner") and "edited" in pg.input_value(".raw textarea"),
    )
    pg.click(".raw textarea")
    pg.keyboard.press("Meta+s")
    check("32 cmd+S saves", count(".ftab.on .dirty") == 0)
    pg.keyboard.press("Meta+e")
    pg.wait_for_selector(".vpane.focus .mm svg")
    pg.evaluate("document.querySelector('.vpane.focus .scroll').scrollTop = 400")
    pg.click("#agentEdit")
    pg.wait_for_timeout(700)
    top = pg.evaluate("document.querySelector('.vpane.focus .scroll').scrollTop")
    check(
        "33 clean agent edit re-renders, scroll kept",
        "Agent note" in pg.inner_text(".vpane.focus .doc") and top > 300,
        f"scrollTop={top}",
    )

    pg.click(".term .path[data-path='macos/Sources/Features/Tarn/Sidebar.swift']")
    check("34 swift opens with the line highlighted", count(".codeview .row.hl") == 1)

    pg.click("[data-seg='theme'] [data-v='light']")
    pg.wait_for_timeout(600)
    check("35 light viewer theme", count(".vpane.light") == count(".vpane"))
    pg.click("[data-seg='theme'] [data-v='dark']")

    while count("[data-vclose]"):
        pg.click("[data-vclose] >> nth=0")
    check(
        "36 closing viewers leaves terminals",
        count(".vpane") == 0 and count(".tpane") >= 1,
    )
    pg.keyboard.press("Meta+b")
    check(
        "37 cmd+B with no viewer opens one with the tree",
        vis(".vtree") and vis(".vpane .empty"),
    )

    pg.click(".tab[data-tabid='t2']")
    check("38 tab 2 has its own layout", count(".vpane") == 0 and count(".tpane") == 1)
    pg.click(".term .path[data-path='README.md']")
    check("39 path in tab 2 opens a viewer there", count(".vpane") == 1)
    pg.click(".tab[data-tabid='t1']")
    check("40 tab 1 keeps its layout", count(".vtree") == 1)

    pg.click(".tpane >> nth=0")
    while count(".tpane") > 1:
        pg.keyboard.press("Meta+w")
    pg.keyboard.press("Meta+w")
    check("41 the last terminal is not closed", count(".tpane") == 1)

    t = time.time()
    for _ in range(10):
        pg.click(".tab[data-tabid='t2']")
        pg.click(".tab[data-tabid='t1']")
    check("42 20 tab switches", True, f"{(time.time() - t) * 50:.0f} ms per switch")

    def side_tabs():
        return pg.locator(".sidebar .tab[data-tabid]").all_inner_texts()

    def ws_tabs(wid):
        return pg.evaluate(f"wss.find(w => w.id === '{wid}').tabs")

    check(
        "W1 all workspaces are visible as groups, pinned tab first",
        count(".wsh") == 3 and len(side_tabs()) == 6 and "spec" in side_tabs()[0],
    )
    pg.click(".wsh[data-wsh='w1']")
    check(
        "W2 a folded workspace hides its tabs, shows count and state",
        len(side_tabs()) == 2
        and "4" in pg.inner_text(".wsh[data-wsh='w1']")
        and count(".wsh[data-wsh='w1'] .dot") == 1,
    )
    pg.click(".wsh[data-wsh='w1']")
    check("W3 unfold shows them again", len(side_tabs()) == 6)
    pg.click(".wsh[data-wsh='w2']")
    pg.click("#agentTab")
    check(
        "W4 an agent tab from ~/Dev/Galera joins galera, folded header shows it waits",
        len(ws_tabs("w2")) == 2 and "2" in pg.inner_text(".wsh[data-wsh='w2']"),
    )
    pg.click(".tab[data-tabid='t1']")
    pg.keyboard.press("Meta+t")
    check(
        "W5 cmd+T opens a tab in the workspace of the current tab",
        len(ws_tabs("w1")) == 5 and "~/D/s/tarn" in pg.inner_text(".tpane .term"),
    )
    pg.hover(".wsh[data-wsh='w2']")
    pg.click(".wsh[data-wsh='w2'] [data-wsnewtab]")
    check(
        "W6 + on a header opens a tab in its folder and unfolds it",
        len(ws_tabs("w2")) == 3 and "~/D/Galera" in pg.inner_text(".tpane .term"),
    )
    drag(pg, ".tab[data-tabid='t3']", ".wsh[data-wsh='w2']", 0.5, 0.5)
    check(
        "W7 drag a tab onto a workspace header moves it there by hand",
        "t3" in ws_tabs("w2") and pg.evaluate("tabs.t3.manual"),
    )
    pg.click(".tab[data-tabid='t3']", button="right")
    pg.click("#ctx [data-mmove][data-to='w1']")
    check(
        "W8 back to its folder workspace clears the manual flag",
        "t3" in ws_tabs("w1") and not pg.evaluate("tabs.t3.manual"),
    )
    pg.click(".tab[data-tabid='t2']", button="right")
    pg.click("#ctx [data-mpin]")
    check("W9 pin from the menu puts the tab on top", "review" in side_tabs()[1])
    drag(pg, ".tab[data-tabid='t4']", ".tab[data-tabid='t3']", 0.5, 0.3)
    order = ws_tabs("w1")
    check("W10 drag reorders tabs", order.index("t4") < order.index("t3"), str(order))
    answers = iter(["home", "~"])
    pg.on("dialog", lambda d: d.accept(next(answers, "")))
    pg.click("#wsNew")
    home = pg.evaluate("wss.find(w => w.name === 'home')")
    check(
        "W11 a new workspace with a folder pulls in its open tabs",
        home is not None and home["tabs"] == ["t6"] and count(".wsh") == 4,
    )
    pg.click(f".wsh[data-wsh='{home['id']}']", button="right")
    pg.click("#ctx [data-wsdel]")
    check(
        "W12 deleting it moves the tabs to Default",
        ws_tabs("w0") == ["t6"] and count(".wsh") == 3,
    )
    pg.click(".tab[data-tabid='t6'] .x")
    check("W13 an empty workspace stays with No tabs", vis(".wsempty"))
    drag(pg, ".wsh[data-wsh='w0']", ".wsh[data-wsh='w1']", 0.5, 0.5)
    check(
        "W13a drag a workspace header before another reorders workspaces",
        pg.evaluate("wss.map(w => w.id)")[0] == "w0",
    )
    dt = pg.evaluate_handle("new DataTransfer()")
    box = pg.locator(".wsh[data-wsh='w2']").bounding_box()
    pg.locator(".wsh[data-wsh='w0']").dispatch_event("dragstart", {"dataTransfer": dt})
    pg.locator(".wsh[data-wsh='w2']").dispatch_event(
        "dragover",
        {"dataTransfer": dt, "clientX": box["x"] + 20, "clientY": box["y"] + 4},
    )
    line = pg.locator(".wsline").bounding_box()
    check(
        "W13b dragging a workspace draws a line in the gap above the target",
        line is not None and abs(line["y"] + 2 - box["y"]) <= 6,
        str(line),
    )
    pg.evaluate("document.dispatchEvent(new Event('dragend'))")
    check("W13c the line goes away when the drag ends", count(".wsline") == 0)
    pg.click(".wsh[data-wsh='w2']")
    pg.reload()
    pg.wait_for_selector(".wsh")
    check(
        "W14 workspaces and folding survive a reload",
        count(".wsh") == 3
        and pg.get_attribute(".wsh[data-wsh='w2']", "aria-expanded") == "false",
    )
    check(
        "W15 tab order and pins survive a reload",
        "spec" in side_tabs()[0] and "review" in side_tabs()[1],
    )
    pg.click("#sbToggle")
    width = pg.locator("#sidebar").bounding_box()["width"]
    check(
        "W16 hide sidebar leaves a rail of tab icons",
        width < 60
        and count(".wsh") == 0
        and count("#sidebar .tab[data-tabid]") == pg.evaluate("flat().length"),
        f"width={width}",
    )
    pg.click("#sidebar .tab[data-tabid='t2']")
    check("W17 a rail icon selects its tab", pg.evaluate("cur") == "t2")
    pg.reload()
    pg.wait_for_selector("#sbToggle")
    check("W18 the rail survives a reload", count(".wsh") == 0)
    pg.click("#sbToggle")
    check("W19 show sidebar brings the workspaces back", count(".wsh") == 3)
    grip = pg.locator("#sbGrip").bounding_box()
    gx, gy = grip["x"] + 5, grip["y"] + 200
    pg.mouse.move(gx, gy)
    pg.mouse.down()
    pg.mouse.move(gx + 80, gy, steps=4)
    pg.mouse.up()
    wide = pg.locator("#sidebar").bounding_box()["width"]
    pg.mouse.move(gx + 80, gy)
    pg.mouse.down()
    pg.mouse.move(gx + 600, gy, steps=4)
    pg.mouse.up()
    widest = pg.locator("#sidebar").bounding_box()["width"]
    check(
        "W20 drag the sidebar edge resizes it within 120-400",
        abs(wide - 280) <= 2 and widest == 400,
        f"{wide} {widest}",
    )
    pg.reload()
    pg.wait_for_selector("#sbGrip")
    check(
        "W21 the sidebar width survives a reload",
        pg.locator("#sidebar").bounding_box()["width"] == 400,
    )

    def drag_grip(dx):
        box = pg.locator("#sbGrip").bounding_box()
        x, y = box["x"] + 5, box["y"] + 200
        pg.mouse.move(x, y)
        pg.mouse.down()
        pg.mouse.move(x + dx, y, steps=8)
        pg.mouse.up()

    drag_grip(-500)
    check(
        "W22 drag the edge all the way left folds the sidebar to the rail",
        count(".wsh") == 0,
    )
    drag_grip(150)
    width = pg.locator("#sidebar").bounding_box()["width"]
    check(
        "W23 drag the rail edge right opens the sidebar again",
        count(".wsh") == 3 and abs(width - 194) <= 2,
        f"width={width}",
    )
    pg.keyboard.press("Meta+Comma")
    check("S1 cmd+, opens the settings window", vis("#settings"))
    pg.check("input[name=tabstyle][value=top]")
    check(
        "S2 tabs at the top replace the sidebar with a tab bar",
        not vis("#sidebar")
        and count("#topTabs [data-toptab]") == pg.evaluate("flat().length"),
    )
    pg.keyboard.press("Escape")
    check("S3 Escape closes the settings window", not vis("#settings"))
    pg.click("#topTabs [data-toptab='t3']")
    check("S4 a top tab selects its tab", pg.evaluate("cur") == "t3")
    pg.reload()
    pg.wait_for_selector("#topTabs [data-toptab]")
    check("S5 the tab style survives a reload", not vis("#sidebar"))
    pg.click("#openSettings")
    pg.check("input[name=tabstyle][value=sidebar]")
    pg.click("#settingsClose")
    check(
        "S6 sidebar style brings the sidebar back",
        vis("#sidebar") and not vis("#settings"),
    )
    pg.hover(".tab[data-tabid='t1']")
    pg.wait_for_timeout(700)
    card = pg.inner_text("#tabcard") if vis("#tabcard") else ""
    check("C1 hover an agent tab opens its card", "Needs permission" in card, card[:60])
    pg.click("#tabcard [data-answer]")
    check(
        "C2 Allow in the card answers the agent and closes the card",
        pg.evaluate("tabs.t1.state") == "working" and not vis("#tabcard"),
    )
    pg.hover(".tab[data-tabid='t3']")
    pg.wait_for_timeout(700)
    check("C3 a tab without an agent opens no card", not vis("#tabcard"))
    pg.mouse.move(700, 500)
    pg.click("#soloDemo")
    check(
        "O1 with one workspace the sidebar is a plain tab list",
        count(".wsh") == 0
        and count("#sidebar .tab[data-tabid]") == pg.evaluate("flat().length"),
    )
    pg.evaluate("window.prompt = q => q === 'Workspace name' ? 'work' : ''")
    pg.click("#wsNew")
    check(
        "O2 a second workspace shows headers, Default among them",
        pg.evaluate("wss.map(w => w.name)") == ["work", "Default"]
        and count(".wsh") == 2,
    )

    pg.set_viewport_size({"width": 420, "height": 860})
    sw = pg.evaluate("document.documentElement.scrollWidth")
    check("43 phone width: no horizontal page scroll", sw <= 420, f"scrollWidth={sw}")
    pg.screenshot(path=sys.argv[1] if len(sys.argv) > 1 else "/dev/null")
    check("44 no page errors", not errors, "; ".join(errors[:3]))
    b.close()

for name, ok, detail in results:
    print(("PASS " if ok else "FAIL ") + name + (f" ({detail})" if detail else ""))
print(f"{sum(ok for _, ok, _ in results)}/{len(results)} passed")
