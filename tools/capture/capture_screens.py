"""Screenshots of the demo for the README: dark theme, 1440x900 at 2x, into docs/assets/screens/.

Run: nice -n 10 uv run --with playwright python -I tools/capture/capture_screens.py [name ...]
"""

import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from capture_lib import TAB, focus, open_page, run, server, show_pane, sync_playwright, until  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parents[2] / "docs" / "assets" / "screens"
SPEC = "/Users/you/code/tarn/docs/spec.md"


def shot(pg, name):
    pg.screenshot(path=str(OUT / f"{name}.png"))
    print("saved", name)


def ask_permission(pg):
    """A claude session in the Default workspace that waits for permission."""
    show_pane(pg, "p6")
    focus(pg, "p6")
    until(pg, "p6", "%")
    run(pg, "claude")
    until(pg, "p6", "Type a request")
    run(pg, "update the spec")
    pg.wait_for_function("__tarn.snapshot().registry.p6?.state === 'permission'")
    time.sleep(1.2)


def sidebar(pg):
    pg.mouse.move(900, 600)
    time.sleep(0.5)
    shot(pg, "sidebar")


def permission_card(pg):
    ask_permission(pg)
    pg.hover(f"{TAB}[data-tabid='t6']")
    pg.wait_for_selector("#tabcard [data-answer]")
    time.sleep(0.5)
    shot(pg, "permission-card")


def viewer(pg):
    pg.evaluate(
        "p => window.bus.cmd('viewer.open', {path: p, pane: 'p1'})", SPEC
    )
    pg.wait_for_selector('.leaf[data-kind="viewer"] iframe')
    v = pg.frame_locator('.leaf[data-kind="viewer"] iframe')
    v.locator(".mm svg").first.wait_for()
    v.locator(".mm svg").first.scroll_into_view_if_needed()
    time.sleep(0.8)
    pg.mouse.move(900, 700)
    shot(pg, "viewer")


def drop_zone(pg):
    area = pg.locator("#ws").bounding_box()
    dt = pg.evaluate_handle("new DataTransfer()")
    pos = {
        "dataTransfer": dt,
        "clientX": area["x"] + 10,
        "clientY": area["y"] + area["height"] / 2,
    }
    pg.locator('.leaf[data-kind="viewer"] .grip').dispatch_event(
        "dragstart", {"dataTransfer": dt}
    )
    pg.locator("#ws").dispatch_event("dragover", pos)
    pg.wait_for_selector("#ws > .drop")
    time.sleep(0.5)
    shot(pg, "drop-zone")
    pg.evaluate("document.dispatchEvent(new Event('dragend'))")


def settings(pg):
    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='appearance']")
    time.sleep(0.5)
    shot(pg, "settings")
    pg.click("#setNav [data-sec='help']")
    time.sleep(0.5)
    shot(pg, "help")
    pg.keyboard.press("Escape")


# Order matters: the viewer opens on the seed tab and the drop zone needs it; the permission card
# runs claude in the Default workspace last, so no other shot shows its state.
STEPS = {
    "sidebar": sidebar,
    "viewer": viewer,
    "drop-zone": drop_zone,
    "permission-card": permission_card,
    "settings": settings,
}

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    want = sys.argv[1:] or list(STEPS)
    with server() as base, sync_playwright() as p:
        browser, ctx, pg = open_page(p, base)
        time.sleep(1.5)
        for name in STEPS:
            if name in want:
                STEPS[name](pg)
        browser.close()
