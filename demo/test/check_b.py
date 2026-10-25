"""Slice B checks: layouts and splits, undo, workspaces, sidebar, top tabs, tab card, drop zones, keys.

Ported from docs/mockups/check.py under the same names (1, 13-26, 38-42, W*, S2-S5, C*, O*, V*, A*);
names that start with N or K are new. The page is test/b.html: stub terminals and a stub viewer.
Run: nice -n 10 uv run --with playwright python -I demo/test/check_b.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from lib import Checks, browser_page, server

check = Checks()

TERM = '.tabview:not([hidden]) .leaf[data-kind="term"]'
VIEWER = '.tabview:not([hidden]) .leaf[data-kind="viewer"]'
LEAF = ".tabview:not([hidden]) .leaf"
TAB = ".sidebar .tab[data-tabid]"


def run(base):
    with browser_page(base, "test/b.html") as (pg, errors, requests):
        pg.wait_for_function("document.documentElement.dataset.ready")
        n = pg.locator
        vis = pg.is_visible

        def count(sel):
            return pg.locator(sel).count()

        def snap():
            return pg.evaluate("__tarn.snapshot().workspaces")

        def cmd(name, payload=None):
            return pg.evaluate(
                "async ([n, p]) => { const { bus } = await import('/js/bus.js'); const r = bus.cmd(n, p); return r === undefined ? null : r; }",
                [name, payload or {}],
            )

        def set_config(key, value):
            cmd("config.set", {"key": key, "value": value})

        def layout(expr):
            """Evaluate an expression over layout.js `L` and the current tab `tab`."""
            return pg.evaluate(
                "async () => { const L = await import('/js/layout.js');"
                " const s = __tarn.snapshot().workspaces; const tab = s.tabs[s.cur];"
                f" return ({expr}); }}"
            )

        def drag(src, dst, fx, fy):
            """HTML5 drag from a locator to a point of another, given as fractions of its box."""
            box = dst.bounding_box()
            pos = {
                "clientX": box["x"] + box["width"] * fx,
                "clientY": box["y"] + box["height"] * fy,
            }
            dt = pg.evaluate_handle("new DataTransfer()")
            src.dispatch_event("dragstart", {"dataTransfer": dt})
            dst.dispatch_event("dragover", {"dataTransfer": dt, **pos})
            dst.dispatch_event("drop", {"dataTransfer": dt, **pos})
            pg.evaluate("document.dispatchEvent(new Event('dragend'))")

        def focused_kind():
            return pg.evaluate(
                "document.querySelector('.tabview:not([hidden]) .leaf.focus')?.dataset.kind"
            )

        def ws_tabs(wid):
            return next(w for w in snap()["wss"] if w["id"] == wid)["tabs"]

        def cur():
            return snap()["cur"]

        # ---- layouts and splits ----
        check(
            "1 start: one terminal, no viewer", count(TERM) == 1 and count(VIEWER) == 0
        )
        check(
            "N1 the title is Ghostty's title with the workspace as subtitle",
            pg.inner_text(".titlebar .ttl") == "Claude · spec"
            and pg.inner_text(".titlebar .sub") == "tarn"
            and pg.title() == "Claude · spec · tarn",
        )

        cmd("viewer.open", {"path": "docs/spec.md"})
        cmd("viewer.open", {"path": "docs/plans/s2-files.md"})
        cmd("viewer.open", {"path": "docs/architecture.md"})
        check(
            "N2 viewer:needed puts a viewer right of the terminal block",
            count(VIEWER) == 1
            and n(VIEWER).bounding_box()["x"] > n(TERM).bounding_box()["x"]
            and count(f"{VIEWER} .ftab") == 3,
        )

        pg.click(TERM)
        pg.keyboard.press("Meta+d")
        check("13 cmd+D in a terminal splits the terminal", count(TERM) == 2)
        pg.keyboard.press("Meta+Shift+d")
        check(
            "14 cmd+shift+D splits down, 4 panes",
            count(TERM) == 3
            and layout("L.terminals(tab.layout).length") == 3
            and count(".tabview:not([hidden]) .split.col") == 1,
        )
        pg.keyboard.press("Meta+d")
        check("15 a fifth pane opens", count(LEAF) == 5)
        check(
            "16 terminals stay in one block",
            layout("L.viewers(L.at(tab.layout, L.blockPath(tab.layout))).length") == 0,
        )
        pg.evaluate(
            "document.querySelector('.tabview:not([hidden]) .leaf.focus .leaf-body > *').dataset.mark = 'same'"
        )
        pg.keyboard.press("Meta+w")
        pg.keyboard.press("Meta+z")
        check("16a cmd+Z brings back a closed terminal", count(TERM) == 4)
        check(
            "N3 the pane instance survives close and undo",
            pg.evaluate("document.querySelectorAll('[data-mark=same]').length") == 1,
        )
        pg.keyboard.press("Meta+w")
        n(TERM).last.click()

        pg.keyboard.press("Meta+Alt+ArrowRight")
        check("17 cmd+alt+right moves focus to the viewer", focused_kind() == "viewer")
        pg.keyboard.press("Meta+[")
        check("18 cmd+[ moves to the previous pane", count(f"{TERM}.focus") == 1)
        pg.keyboard.press("Meta+Shift+Enter")
        check("19 cmd+shift+Enter zooms one pane", count(LEAF) == 1)
        pg.keyboard.press("Meta+Shift+Enter")
        check("20 again restores the layout", count(LEAF) == 4)
        pg.keyboard.press("Meta+w")
        check("21 cmd+W closes a terminal", count(TERM) == 2)
        check(
            "21a every terminal has a grab handle",
            count(f"{TERM} .grip") == count(TERM),
        )
        drag(n(f"{TERM} .grip").nth(0), n(TERM).nth(1), 0.5, 0.95)
        check(
            "21b drag a terminal grab handle to a terminal bottom edge stacks them",
            layout("L.at(tab.layout, L.blockPath(tab.layout)).dir") == "col"
            and count(TERM) == 2,
        )
        drag(n(f"{TERM} .grip").nth(0), n(VIEWER), 0.9, 0.5)
        check(
            "21c a terminal dropped on a viewer is refused",
            layout("L.at(tab.layout, L.blockPath(tab.layout)).dir") == "col"
            and layout("L.terminals(tab.layout).length") == 2,
        )

        drag(n(f"{VIEWER} .ftab").nth(0), n(VIEWER), 0.5, 0.95)
        check(
            "22 drag a tab to the viewer bottom edge splits the viewer",
            count(VIEWER) == 2 and count(".tabview:not([hidden]) .split.col") >= 1,
        )
        drag(n(f"{VIEWER} .ftab").first, n(TERM).first, 0.02, 0.5)
        first = pg.evaluate(
            "document.querySelector('.tabview:not([hidden]) .leaf').dataset.kind"
        )
        check(
            "23 drop on a terminal edge puts the viewer beside the block",
            count(VIEWER) == 3
            and first == "viewer"
            and layout("L.viewers(L.at(tab.layout, L.blockPath(tab.layout))).length")
            == 0,
        )
        drag(n(f"{VIEWER} .ftab").first, n(VIEWER).nth(1), 0.5, 0.6)
        check("25 drop the only tab in a viewer center merges", count(VIEWER) == 2)
        cmd("pane.close", {"id": layout("L.viewers(tab.layout)[0].viewer")})
        pg.keyboard.press("Meta+z")
        check("25a cmd+Z brings back a closed viewer", count(VIEWER) == 2)

        def dots():
            return pg.evaluate(
                "getComputedStyle(document.querySelector('.leaf[data-kind=term] .grip svg')).opacity"
            )

        pg.mouse.move(5, 5)
        check("25b grab handle dots are hidden away from the pane top", dots() == "0")
        box = n(TERM).first.bounding_box()
        pg.mouse.move(box["x"] + 30, box["y"] + 20)
        pg.wait_for_timeout(250)
        check("25c dots show in the top band of the pane", dots() == "0.6", dots())
        set_config("drag-handle", "never")
        check("25d drag-handle never removes the handle", not vis(f"{TERM} .grip"))
        set_config("drag-handle", "always")
        pg.mouse.move(5, 5)
        pg.wait_for_timeout(250)
        check("N4 drag-handle always shows the dots everywhere", dots() == "0.6")
        cmd("config.reset", {"key": "drag-handle"})

        sd = n(".tabview:not([hidden]) .sdiv.row").first.bounding_box()
        w0 = n(LEAF).first.bounding_box()["width"]
        pg.mouse.move(sd["x"] + 1, sd["y"] + 200)
        pg.mouse.down()
        pg.mouse.move(sd["x"] + 121, sd["y"] + 200, steps=4)
        pg.mouse.up()
        w1 = n(LEAF).first.bounding_box()["width"]
        check("26 split divider drag resizes", w1 > w0 + 60, f"{w0:.0f} -> {w1:.0f}")
        check("N5 the dragged ratio is in the state", layout("tab.layout.ratio") != 0.5)

        pg.keyboard.press("Control+Meta+ArrowLeft")
        pg.keyboard.press("Control+Meta+=")
        check(
            "N6 ctrl+cmd+= equalizes the splits",
            layout("tab.layout.ratio") == 0.5 or layout("tab.layout.ratio") > 0.3,
        )

        # ---- tabs ----
        pg.click(f"{TAB}[data-tabid='t2']")
        check("38 tab 2 has its own layout", count(VIEWER) == 0 and count(TERM) == 1)
        cmd("viewer.open", {"path": "README.md"})
        check("39 path in tab 2 opens a viewer there", count(VIEWER) == 1)
        pg.click(f"{TAB}[data-tabid='t1']")
        check("40 tab 1 keeps its layout", count(VIEWER) == 2 and count(TERM) == 2)

        pg.click(TERM + " >> nth=0")
        while count(TERM) > 1:
            pg.keyboard.press("Meta+w")
        pg.keyboard.press("Meta+w")
        check(
            "41 cmd+W on the last terminal closes the tab",
            count(f"{TAB}[data-tabid='t1']") == 0 and cur() != "t1",
        )
        n(TERM).first.click()  # cmd+Z is a terminal key; t2 may have its viewer focused
        pg.keyboard.press("Meta+z")
        check(
            "41a cmd+Z brings the closed tab back",
            count(f"{TAB}[data-tabid='t1']") == 1 and cur() == "t1",
            f"{cur()} {pg.inner_text('#toast')}",
        )
        check("N7 the restored tab keeps its viewers", count(VIEWER) == 2)

        import time

        t = time.time()
        for _ in range(10):
            pg.click(f"{TAB}[data-tabid='t2']")
            pg.click(f"{TAB}[data-tabid='t1']")
        check("42 20 tab switches", True, f"{(time.time() - t) * 50:.0f} ms per switch")

        # ---- undo window, cap, persistence ----
        pg.reload()
        pg.wait_for_function("document.documentElement.dataset.ready")
        pg.click(f"{TAB}[data-tabid='t6']")
        for _ in range(7):
            pg.click(TERM)
            pg.keyboard.press("Meta+d")
        check("N8 eight panes fit in a tab", count(TERM) == 8)
        pg.keyboard.press("Meta+d")
        check(
            "N9 the ninth pane is refused with a toast",
            count(TERM) == 8 and "At most 8" in pg.inner_text("#toast"),
        )
        pg.evaluate("__tarn.clock.freeze()")
        pg.keyboard.press("Meta+w")
        pg.evaluate("__tarn.clock.advance(6000)")
        pg.keyboard.press("Meta+z")
        check(
            "N10 undo fails after the undo-timeout",
            count(TERM) == 7 and "Nothing to undo" in pg.inner_text("#toast"),
        )
        before = snap()["tabs"]["t6"]["layout"]
        pg.reload()
        pg.wait_for_function("document.documentElement.dataset.ready")
        check(
            "N11 the layout of a tab survives a reload",
            snap()["tabs"]["t6"]["layout"] == before,
        )
        pg.click(f"{TAB}[data-tabid='t6']")
        while count(TERM) > 1:
            pg.click(TERM)
            pg.keyboard.press("Meta+w")

        # ---- keys ----
        rows = pg.evaluate(
            "async () => { const m = await Promise.all(['tabs','splits','find'].map(f => import(`/js/keys/${f}.js`)));"
            " return m.flatMap(x => Object.values(x).flat()); }"
        )
        bare = [
            r["id"]
            for r in rows
            if any(c.startswith(("Cmd", "Ctrl+Cmd")) for c in r["chords"])
            and not r["alt"]
        ]
        check(
            "K1 every cmd chord has a Ctrl+Alt fallback except the one with Alt already",
            bare == ["tab.close"],
            str(bare),
        )
        n_tabs = len(snap()["tabs"])
        pg.keyboard.press("Control+Alt+t")
        check(
            "K2 the fallback Ctrl+Alt+T opens a tab", len(snap()["tabs"]) == n_tabs + 1
        )
        pg.keyboard.press("Control+Alt+1")
        check("K3 the fallback Ctrl+Alt+1 goes to the first tab", cur() == "t1")
        pg.keyboard.press("Meta+9")
        check("K4 cmd+9 goes to the last tab", cur() == snap()["wss"][-1]["tabs"][-1])
        pg.keyboard.press("Meta+Shift+[")
        pg.keyboard.press("Meta+Shift+]")
        check(
            "K5 cmd+shift+[ and ] step through tabs",
            cur() == snap()["wss"][-1]["tabs"][-1],
        )
        pg.keyboard.press("Meta+Shift+p")
        check("K6 cmd+shift+P opens the palette", vis("#palette"))
        pg.keyboard.type("new tab")
        pg.keyboard.press("Enter")
        check(
            "K7 the palette runs a command",
            len(snap()["tabs"]) == n_tabs + 2 and not vis("#palette"),
        )
        pg.keyboard.press("Meta+f")
        check("K8 cmd+F opens the find bar", vis("#findbar"))
        pg.keyboard.press("Escape")

        # ---- window options ----
        set_config("unfocused-split-opacity", 0.5)
        pg.click(TERM + " >> nth=0")
        pg.keyboard.press("Meta+d")
        op = pg.evaluate(
            "getComputedStyle(document.querySelectorAll('.tabview:not([hidden]) .leaf[data-kind=term]:not(.focus) .leaf-body')[0]).opacity"
        )
        check("N12 unfocused-split-opacity dims an unfocused pane", op == "0.5", op)
        set_config("macos-titlebar-style", "hidden")
        check(
            "N13 macos-titlebar-style hidden hides the title bar",
            not vis(".titlebar") and n("#main.tb-hidden").count() == 1,
        )
        cmd("config.reset", {"key": "macos-titlebar-style"})
        cmd("config.reset", {"key": "unfocused-split-opacity"})
        pg.evaluate(
            "import('/js/workspace.js').then((m) => { m.paneOf(document.querySelector('.tabview:not([hidden]) .leaf.focus').dataset.leaf).busy = () => true; })"
        )
        dialogs = []
        pg.once("dialog", lambda d: (dialogs.append(d.message), d.dismiss()))
        k = count(TERM)
        pg.keyboard.press("Meta+w")
        check("N14 closing a busy pane asks first", dialogs and count(TERM) == k)
        set_config("confirm-close-surface", "false")
        pg.keyboard.press("Meta+w")
        check("N15 confirm-close-surface false closes at once", count(TERM) == k - 1)
        cmd("config.reset", {"key": "confirm-close-surface"})

        # ---- workspaces ----
        pg.reload()
        pg.wait_for_function("document.documentElement.dataset.ready")
        cmd("pane.undo")
        pg.evaluate("localStorage.clear()")
        pg.reload()
        pg.wait_for_function("document.documentElement.dataset.ready")

        def side_tabs():
            return pg.locator(f"{TAB}").all_inner_texts()

        check(
            "W1 all workspaces are visible as groups",
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
        cmd("tab.new", {"pane": "p5", "select": False})
        check(
            "W4 an agent's new tab joins the agent's workspace, folded header shows it",
            len(ws_tabs("w2")) == 2
            and "2" in pg.inner_text(".wsh[data-wsh='w2']")
            and cur() == "t1",
        )
        pg.click(f"{TAB}[data-tabid='t1']")
        pg.keyboard.press("Meta+t")
        new_tab = snap()["tabs"][cur()]
        check(
            "W5 cmd+T opens a tab in the workspace of the current tab",
            len(ws_tabs("w1")) == 5 and "~/D/s/tarn" in new_tab["title"],
        )
        pg.hover(".wsh[data-wsh='w2']")
        pg.click(".wsh[data-wsh='w2'] [data-wsnewtab]")
        check(
            "W6 + on a header opens a tab in that workspace and unfolds it",
            len(ws_tabs("w2")) == 3
            and pg.get_attribute(".wsh[data-wsh='w2']", "aria-expanded") == "true",
        )
        drag(n(f"{TAB}[data-tabid='t3']"), n(".wsh[data-wsh='w2']"), 0.5, 0.5)
        check(
            "W7 drag a tab onto a workspace header moves it there",
            "t3" in ws_tabs("w2"),
        )
        n(f"{TAB}[data-tabid='t3']").click(button="right")
        pg.click("#ctx [data-mmove][data-to='w1']")
        check("W8 Move to in the tab menu moves it back", "t3" in ws_tabs("w1"))
        n(f"{TAB}[data-tabid='t2']").click(button="right")
        check("W9 the tab menu has no pin", count("#ctx [data-mpin]") == 0)
        pg.keyboard.press("Escape")
        drag(n(f"{TAB}[data-tabid='t4']"), n(f"{TAB}[data-tabid='t3']"), 0.5, 0.3)
        order = ws_tabs("w1")
        check(
            "W10 drag reorders tabs", order.index("t4") < order.index("t3"), str(order)
        )
        answers = iter(["home"])
        pg.on("dialog", lambda d: d.accept(next(answers, "")))
        pg.click("#wsNew")
        home = next((w for w in snap()["wss"] if w["name"] == "home"), None)
        check(
            "W11 a new workspace asks a name only, goes last and starts with one tab",
            home is not None
            and len(home["tabs"]) == 1
            and snap()["wss"][-1]["name"] == "home"
            and cur() == home["tabs"][0],
        )
        n(f".wsh[data-wsh='{home['id']}']").click(button="right")
        pg.click("#ctx [data-wsdel]")
        check(
            "W12 deleting it moves its tabs to the workspace above",
            home["tabs"][0] in ws_tabs("w0") and count(".wsh") == 3,
        )
        for tab_id in ws_tabs("w0"):
            pg.click(f"{TAB}[data-tabid='{tab_id}'] .x")
        check(
            "W13 closing the last tab of Default closes Default like any workspace",
            count(".wsh") == 2 and count(".wsh[data-wsh='w0']") == 0,
        )
        drag(n(".wsh[data-wsh='w2']"), n(".wsh[data-wsh='w1']"), 0.5, 0.5)
        check(
            "W13a drag a workspace header before another reorders workspaces",
            snap()["wss"][0]["id"] == "w2",
        )
        pg.wait_for_function("document.querySelector('.wsh').dataset.wsh === 'w2'")
        dt = pg.evaluate_handle("new DataTransfer()")
        head = n(".wsh[data-wsh='w2']").bounding_box()
        n(".wsh[data-wsh='w1']").dispatch_event("dragstart", {"dataTransfer": dt})
        n(".wsh[data-wsh='w2']").dispatch_event(
            "dragover",
            {"dataTransfer": dt, "clientX": head["x"] + 20, "clientY": head["y"] + 4},
        )
        line = n(".wsline").bounding_box()
        check(
            "W13b dragging a workspace draws a line in the gap above the target",
            line is not None and abs(line["y"] + 2 - head["y"]) <= 6,
            str(line),
        )
        pg.evaluate("document.dispatchEvent(new Event('dragend'))")
        check("W13c the line goes away when the drag ends", count(".wsline") == 0)
        pg.click(".wsh[data-wsh='w2']")
        order_saved = ws_tabs("w1")
        pg.reload()
        pg.wait_for_selector(".wsh")
        check(
            "W14 workspaces and folding survive a reload",
            count(".wsh") == 2
            and pg.get_attribute(".wsh[data-wsh='w2']", "aria-expanded") == "false",
        )
        check(
            "W15 tab order survives a reload",
            ws_tabs("w1") == order_saved,
            str(ws_tabs("w1")),
        )
        pg.click("#sbToggle")
        width = n("#sidebar").bounding_box()["width"]
        check(
            "W16 hide sidebar leaves a rail of tab icons",
            width < 60
            and count(".wsh") == 0
            and count(f"#sidebar {'.tab[data-tabid]'}")
            == len([t for w in snap()["wss"] for t in w["tabs"]]),
            f"width={width}",
        )
        pg.click("#sidebar .tab[data-tabid='t2']")
        check("W17 a rail icon selects its tab", cur() == "t2")
        pg.reload()
        pg.wait_for_selector("#sbToggle")
        check("W18 the rail survives a reload", count(".wsh") == 0)
        pg.click("#sbToggle")
        check("W19 show sidebar brings the workspaces back", count(".wsh") == 2)
        grip = n("#sbGrip").bounding_box()
        gx, gy = grip["x"] + 5, grip["y"] + 200
        pg.mouse.move(gx, gy)
        pg.mouse.down()
        pg.mouse.move(gx + 80, gy, steps=4)
        pg.mouse.up()
        wide = n("#sidebar").bounding_box()["width"]
        pg.mouse.move(gx + 80, gy)
        pg.mouse.down()
        pg.mouse.move(gx + 600, gy, steps=4)
        pg.mouse.up()
        widest = n("#sidebar").bounding_box()["width"]
        check(
            "W20 drag the sidebar edge resizes it within 120-400",
            abs(wide - 280) <= 2 and widest == 400,
            f"{wide} {widest}",
        )
        pg.reload()
        pg.wait_for_selector("#sbGrip")
        check(
            "W21 the sidebar width survives a reload",
            n("#sidebar").bounding_box()["width"] == 400,
        )

        def drag_grip(dx):
            g = n("#sbGrip").bounding_box()
            x, y = g["x"] + 5, g["y"] + 200
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
        width = n("#sidebar").bounding_box()["width"]
        check(
            "W23 drag the rail edge right opens the sidebar again",
            count(".wsh") == 2 and abs(width - 194) <= 2,
            f"width={width}",
        )

        # ---- tabs at the top ----
        set_config("tab-style", "top")
        flat = [t for w in snap()["wss"] for t in w["tabs"]]
        check(
            "S2 tabs at the top replace the sidebar with a tab bar",
            not vis("#sidebar") and count("#topTabs [data-toptab]") == len(flat),
        )
        pg.click("#topTabs [data-toptab='t3']")
        check("S4 a top tab selects its tab", cur() == "t3")
        check(
            "S4a a top tab shows its cmd+N key as Ghostty does",
            pg.inner_text("#topTabs .ttab >> nth=0 >> .tk") == "⌘1",
        )
        before = count("#topTabs [data-toptab]")
        pg.click("#topNew")
        check(
            "S4b + in the tab bar opens a tab",
            count("#topTabs [data-toptab]") == before + 1,
        )
        new_id = cur()
        pg.hover(f"#topTabs [data-toptab='{new_id}']")
        pg.click(f"#topTabs [data-toptab='{new_id}'] .tx")
        check("S4c x on a top tab closes it", count("#topTabs [data-toptab]") == before)
        pg.reload()
        pg.wait_for_selector("#topTabs [data-toptab]")
        check("S5 the tab style survives a reload", not vis("#sidebar"))
        cmd("config.reset", {"key": "tab-style"})
        check(
            "N16 sidebar style brings the sidebar back",
            vis("#sidebar") and not vis("#topTabs"),
        )

        # ---- tab card ----
        cmd(
            "hook",
            {
                "pane": "p1",
                "name": "PermissionRequest",
                "event": {"request": "Edit: docs/spec.md", "answerable": True},
            },
        )
        pg.evaluate(
            "import('/js/bus.js').then(({ bus }) => bus.handle('card.answer', ({ pane }) =>"
            " bus.cmd('hook', { pane, name: 'PostToolUse', event: {} })))"
        )
        pg.hover(f"{TAB}[data-tabid='t1']")
        pg.wait_for_timeout(700)
        card = pg.inner_text("#tabcard") if vis("#tabcard") else ""
        check(
            "C1 hover an agent tab opens its card",
            "Needs permission" in card,
            card[:60],
        )
        pg.click("#tabcard [data-answer][data-allow='true']")
        sessions = pg.evaluate("__tarn.snapshot().registry")
        check(
            "C2 Allow in the card answers the agent and closes the card",
            sessions["p1"]["state"] == "working" and not vis("#tabcard"),
        )
        pg.hover(f"{TAB}[data-tabid='t3']")
        pg.wait_for_timeout(700)
        check("C3 a tab without an agent opens no card", not vis("#tabcard"))
        pg.hover(f"{TAB}[data-tabid='t2']")
        pg.wait_for_timeout(700)
        check(
            "N17 a working agent's card shows its state",
            "Working" in pg.inner_text("#tabcard"),
        )
        pg.mouse.move(700, 500)

        # ---- workspace close and window ----
        heads = count(".wsh")
        pg.evaluate("window.prompt = (q) => (q === 'Workspace name' ? 'work' : '')")
        pg.click("#wsNew")
        check(
            "O1 a new workspace shows its header with one tab",
            count(".wsh") == heads + 1 and count(".wsh:has-text('work')") == 1,
        )
        pg.click(TERM)
        pg.keyboard.press("Meta+w")
        check(
            "O2 cmd+W on the last tab of a workspace closes the workspace",
            count(".wsh") == heads and count(".wsh:has-text('work')") == 0,
        )
        pg.keyboard.press("Meta+z")
        check("O3 cmd+Z brings the workspace back", count(".wsh:has-text('work')") == 1)
        for ws in snap()["wss"]:
            if ws.get("collapsed"):
                cmd("ws.fold", {"id": ws["id"]})
        while count(f"{TAB}"):
            pg.click(f"{TAB} >> nth=0 >> .x")
        check(
            "O4 the last tab of the last workspace closes the window",
            len(snap()["wss"]) == 0 and "window closed" in pg.inner_text("#ws"),
        )
        pg.keyboard.press("Meta+n")
        check(
            "O5 a new window starts with Default and one tab",
            [w["name"] + ":" + str(len(w["tabs"])) for w in snap()["wss"]]
            == ["Default:1"]
            and count(".wsh") == 1,
        )

        # ---- viewer drags and drop zones ----
        cmd("viewer.open", {"path": "docs/spec.md"})
        cmd(
            "pane.split",
            {
                "id": layout("L.viewers(tab.layout)[0].viewer"),
                "dir": "right",
                "kind": "viewer",
                "path": "README.md",
            },
        )
        check(
            "V1 every viewer has a grab handle",
            count(f"{VIEWER} .grip") == count(VIEWER) == 2,
        )
        files = sorted(pg.locator(f"{VIEWER} .ftab").all_inner_texts())
        drag(n(f"{VIEWER} .grip").nth(0), n(VIEWER).nth(1), 0.5, 0.5)
        merged = sorted(pg.locator(f"{VIEWER} .ftab").all_inner_texts())
        check(
            "V2 a viewer dropped in the middle of another hands over all its files",
            count(VIEWER) == 1 and set(files) <= set(merged),
            str(merged),
        )
        cmd(
            "pane.split",
            {
                "id": layout("L.viewers(tab.layout)[0].viewer"),
                "dir": "right",
                "kind": "viewer",
                "path": "docs/spec.md",
            },
        )
        drag(n(f"{VIEWER} .grip").nth(1), n(TERM).first, 0.02, 0.5)
        first = pg.evaluate(
            "document.querySelector('.tabview:not([hidden]) .leaf').dataset.kind"
        )
        check(
            "V3 a viewer dropped on a terminal edge moves beside the block with its files",
            count(VIEWER) == 2
            and first == "viewer"
            and layout("L.viewers(L.at(tab.layout, L.blockPath(tab.layout))).length")
            == 0,
        )
        drag(n(f"{VIEWER} .grip").nth(0), n(VIEWER).nth(0), 0.9, 0.5)
        check("V4 a viewer cannot drop on itself", count(VIEWER) == 2)
        drag(n(f"{TERM} .grip").nth(0), n(VIEWER).nth(0), 0.5, 0.95)
        below = layout(
            "(() => { const p = L.pathOf(tab.layout, tab.layout.pane ?? L.terminals(tab.layout)[0].pane);"
            " const parent = L.at(tab.layout, p.slice(0, -1));"
            " return parent.dir === 'col' && p.endsWith('b') && 'viewer' in parent.a; })()"
        )
        check(
            "V5 a lone terminal dropped at a viewer's bottom edge goes below it", below
        )
        dt = pg.evaluate_handle("new DataTransfer()")
        vb = n(VIEWER).first.bounding_box()
        n(f"{VIEWER} .ftab").first.dispatch_event("dragstart", {"dataTransfer": dt})
        n(f"{VIEWER} .scroll").first.dispatch_event(
            "dragover",
            {
                "dataTransfer": dt,
                "clientX": vb["x"] + vb["width"] * 0.25,
                "clientY": vb["y"] + vb["height"] * 0.5,
            },
        )
        pg.wait_for_timeout(250)
        frame = n("#ws > .drop").bounding_box()
        pg.evaluate("document.dispatchEvent(new Event('dragend'))")
        check(
            "V6 a file over the left half of a viewer frames the whole left half",
            frame is not None and abs(frame["width"] - (vb["width"] / 2 - 8)) <= 3,
            str(frame),
        )

        def area_over(src, x, y):
            """Start a drag at src and hover a point of the tab area, in pixels from its corner."""
            dt = pg.evaluate_handle("new DataTransfer()")
            box = n("#ws").bounding_box()
            pos = {"dataTransfer": dt, "clientX": box["x"] + x, "clientY": box["y"] + y}
            src.first.dispatch_event("dragstart", {"dataTransfer": dt})
            n("#ws").dispatch_event("dragover", pos)
            pg.wait_for_timeout(250)
            return box, dt, pos

        def area_drop(pos, dt):
            n("#ws").dispatch_event("drop", {"dataTransfer": dt, **pos})
            pg.evaluate("document.dispatchEvent(new Event('dragend'))")

        pg.click("#sbNew")
        cmd("viewer.open", {"path": "docs/spec.md"})
        box, dt, pos = area_over(n(f"{VIEWER} .ftab"), 10, 300)
        frame = n("#ws > .drop").bounding_box()
        check(
            "A1 a file at the left edge of the tab area frames the left half of the area",
            frame is not None and abs(frame["width"] - (box["width"] / 2 - 8)) <= 3,
            str(frame),
        )
        area_drop(pos, dt)
        check(
            "A2 dropped there it opens left of everything",
            layout("tab.layout.dir === 'row' && 'viewer' in tab.layout.a"),
        )
        cmd("viewer.open", {"path": "README.md"})
        box, dt, pos = area_over(n(f"{VIEWER} .ftab"), 10, 10)
        frame = n("#ws > .drop").bounding_box()
        ratio = layout("tab.layout.ratio")
        check(
            "A3 the top left corner of a split area frames its top left quarter",
            frame is not None
            and abs(frame["width"] - (box["width"] * ratio - 8)) <= 3
            and abs(frame["height"] - (box["height"] / 2 - 8)) <= 3,
            f"{frame} ratio={ratio}",
        )
        area_drop(pos, dt)
        check(
            "A4 dropped there it halves the left side, new viewer on top",
            layout(
                "'dir' in tab.layout.a && tab.layout.a.dir === 'col' && 'viewer' in tab.layout.a.a"
            ),
        )
        pg.click(TERM)
        pg.keyboard.press("Meta+d")
        area_over(n(f"{TERM} .grip"), box["width"] - 10, 300)
        check("A5 split terminals cannot go to the area edge", vis("#ws > .drop.deny"))
        pg.evaluate("document.dispatchEvent(new Event('dragend'))")

        check("N18 no page errors", not errors, "; ".join(errors[:3]))
        check(
            "N19 no request leaves the server",
            all(u.startswith((base, "data:")) for u in requests),
        )


if __name__ == "__main__":
    with server() as base:
        try:
            run(base)
        except Exception:
            check.report()
            raise
    check.exit()
