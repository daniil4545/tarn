"""Regression checks from the two code reviews of the demo (cr-demo-ui, cr-demo-term).

Each check names the review item. They run on the real index.html; a drag ends with the browser's
own events, not a hand-sent dragend.
Run: nice -n 10 uv run --with playwright python -I demo/test/check_review.py
"""

import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from lib import Checks, app_page, cmd, new_pane, server, show_pane

check = Checks()
REPO = "/Users/daniil/Dev/self-projects/tarn"
VIEWER = '.tabview:not([hidden]) .leaf[data-kind="viewer"]'
TERM = '.tabview:not([hidden]) .leaf[data-kind="term"]'
LOADED = (
    "[...document.querySelectorAll('.viewer-pane iframe')].every("
    "(f) => f.contentDocument?.readyState === 'complete' && f.contentWindow.tarn)"
)


def ws(pg):
    return pg.evaluate("__tarn.snapshot().workspaces")


def layout_ids(pg, tab="t1"):
    return pg.evaluate(
        "(t) => JSON.stringify(__tarn.snapshot().workspaces.tabs[t].layout)", tab
    )


def ui1_undo_keeps_later_layout(base):
    with app_page(base) as (pg, _e, _r):
        cmd(pg, "viewer.open", {"path": "docs/spec.md"})
        pg.wait_for_selector(VIEWER)
        cmd(pg, "pane.close", {"id": "v1"})
        cmd(pg, "pane.split", {"id": "p1", "dir": "right"})
        cmd(pg, "pane.undo")
        text = layout_ids(pg)
        check(
            "R1 undo of a closed viewer keeps a split made after the close",
            '"v1"' in text and text.count('"pane"') == 2,
            text,
        )


def ui3_undo_last_tab(base):
    with app_page(base) as (pg, _e, _r):
        for _ in range(6):
            cmd(pg, "tab.close", {})
        gone = not ws(pg)["wss"]
        pg.keyboard.press("Meta+z")
        s = ws(pg)
        check(
            "R3 Cmd+Z after the last tab closed brings it back",
            gone and len(s["wss"]) == 1 and s["cur"] is not None,
            str(s["cur"]),
        )
        cmd(pg, "config.set", {"key": "undo-timeout", "value": "0s"})
        cmd(pg, "tab.new", {})
        cmd(pg, "tab.close", {})
        check(
            "R3a with undo-timeout 0s the toast does not promise Cmd+Z",
            "⌘Z" not in pg.inner_text("#toast"),
            pg.inner_text("#toast"),
        )


def ui4_dirty_viewer_asks(base):
    with app_page(base) as (pg, _e, _r):
        cmd(pg, "tab.go", {"id": "t3"})
        cmd(pg, "viewer.open", {"path": "docs/spec.md", "pane": None})
        pg.wait_for_selector(VIEWER)
        pg.wait_for_function(LOADED)
        frame = pg.frame_locator(f"{VIEWER} iframe").first
        frame.locator(".ftab.on").click()
        pg.keyboard.press("Meta+e")
        frame.locator(".cm-content").click()
        pg.keyboard.type("dirty text")
        frame.locator(".ftab.on .dirty").wait_for()
        cmd(pg, "tab.close", {"id": "t3"})
        buttons = pg.locator(".ask-dialog button").all_inner_texts()
        check(
            "R4 closing a tab with a dirty viewer asks Save, Don't Save, Cancel",
            buttons == ["Save", "Don't Save", "Cancel"],
            str(buttons),
        )
        pg.click(".ask-dialog button:has-text('Cancel')")
        check("R4a Cancel keeps the tab", "t3" in ws(pg)["tabs"])
        cmd(pg, "tab.close", {"id": "t3"})
        pg.click(".ask-dialog button:has-text('Save')")
        text = pg.evaluate(
            f"__tarn.snapshot().vfs.files['{REPO}/docs/spec.md'].text"
        )
        check(
            "R4b Save writes the file and closes the tab",
            "t3" not in ws(pg)["tabs"] and "dirty text" in text,
        )


def ui2_real_drag_clears_state(base):
    with app_page(base) as (pg, _e, _r):
        cmd(pg, "viewer.open", {"path": "docs/spec.md"})
        pg.wait_for_selector(VIEWER)
        pg.wait_for_function(LOADED)
        grip = pg.locator(f"{VIEWER} .grip").first.bounding_box()
        area = pg.locator("#ws").bounding_box()
        pg.mouse.move(grip["x"] + grip["width"] / 2, grip["y"] + grip["height"] / 2)
        pg.mouse.down()
        pg.mouse.move(area["x"] + 200, area["y"] + 200, steps=5)
        pg.mouse.move(area["x"] + 8, area["y"] + area["height"] / 2, steps=5)
        pg.mouse.up()
        time.sleep(0.5)
        state = pg.evaluate("[document.body.className, document.querySelectorAll('#ws > .drop').length]")
        check(
            "R2 a real drag to the area edge leaves no dragging state behind",
            "dragging" not in state[0] and state[1] == 0,
            str(state),
        )
        layout = layout_ids(pg)
        check("R2a the drop moved the viewer to the left edge", layout.startswith('{"dir":"row","ratio":0.5,"a":{"viewer"'), layout)


SUITES = [ui1_undo_keeps_later_layout, ui3_undo_last_tab, ui4_dirty_viewer_asks, ui2_real_drag_clears_state]

if __name__ == "__main__":
    with server() as base:
        for suite in SUITES:
            try:
                suite(base)
            except Exception as error:  # a crashed suite is a red check, not a lost report
                check(f"{suite.__name__} ran to the end", False, str(error)[:120])
    check.exit()
