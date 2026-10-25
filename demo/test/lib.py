"""Shared helpers of the demo checks: static server, Chrome page, check recorder.

Run a check: uv run --with playwright python -I demo/test/check_0.py
Under load use: nice -n 10 (the server and Chrome are children of the script).
"""

import functools
import http.server
import pathlib
import sys
import threading
from contextlib import contextmanager

from playwright.sync_api import sync_playwright

DEMO = pathlib.Path(__file__).resolve().parent.parent


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


@contextmanager
def server():
    handler = functools.partial(Quiet, directory=str(DEMO))
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        yield f"http://127.0.0.1:{srv.server_address[1]}"
    finally:
        srv.shutdown()


@contextmanager
def browser_page(base, path="index.html", dpr=1, width=1400, height=860, init=None):
    """Yield (page, errors, requests): console errors, page errors and every request URL."""
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome")
        ctx = browser.new_context(
            viewport={"width": width, "height": height}, device_scale_factor=dpr
        )
        if init:
            ctx.add_init_script(init)
        page = ctx.new_page()
        errors, requests = [], []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on(
            "console", lambda m: errors.append(m.text) if m.type == "error" else None
        )
        page.on("request", lambda r: requests.append(r.url))
        page.goto(f"{base}/{path}")
        try:
            yield page, errors, requests
        finally:
            browser.close()


class Checks:
    def __init__(self):
        self.results = []

    def __call__(self, name, ok, detail=""):
        self.results.append((name, bool(ok), detail))

    def report(self):
        for name, ok, detail in self.results:
            print(
                f"{'PASS' if ok else 'FAIL'}  {name}"
                + (f"  [{detail}]" if detail and not ok else "")
            )
        failed = [r for r in self.results if not r[1]]
        print(f"{len(self.results) - len(failed)}/{len(self.results)} passed")
        return 1 if failed else 0

    def exit(self):
        sys.exit(self.report())
