"""Shared helpers of the capture scripts: a dark 1440x900 page of the real demo.

Run: nice -n 10 uv run --with playwright python -I tools/capture/<script>.py
"""

import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "demo" / "test"))

from lib import server  # noqa: E402,F401
from playwright.sync_api import sync_playwright  # noqa: E402,F401

TAB = ".sidebar .tab[data-tabid]"


def open_page(p, base, dpr=2, video_dir=None):
    browser = p.chromium.launch(channel="chrome")
    opts = {
        "viewport": {"width": 1440, "height": 900},
        "device_scale_factor": dpr,
        "color_scheme": "dark",
    }
    if video_dir:
        opts["record_video_dir"] = str(video_dir)
        opts["record_video_size"] = {"width": 1440, "height": 900}
    ctx = browser.new_context(**opts)
    page = ctx.new_page()
    page.on("dialog", lambda d: d.accept())
    page.goto(f"{base}/index.html")
    page.wait_for_selector("html[data-ready=true]")
    page.evaluate(
        "async () => { const { bus } = await import('/js/bus.js'); window.bus = bus; }"
    )
    return browser, ctx, page


def screen(pg, pane):
    return pg.evaluate(f"__tarn.screen('{pane}')")


def until(pg, pane, pattern, timeout=6.0):
    end = time.time() + timeout
    while True:
        if re.search(pattern, screen(pg, pane)):
            return True
        if time.time() > end:
            return False
        time.sleep(0.05)


def run(pg, line, delay=0):
    pg.keyboard.type(line, delay=delay)
    pg.keyboard.press("Enter")


def focus(pg, pane):
    pg.locator(f"[data-pane='{pane}'] canvas").first.click()


def show_pane(pg, pane):
    pg.evaluate(
        """(id) => { const s = __tarn.snapshot().workspaces;
          const tab = Object.values(s.tabs).find((t) => JSON.stringify(t.layout).includes('"' + id + '"'));
          window.bus.cmd('tab.go', {id: tab.id}); }""",
        pane,
    )
