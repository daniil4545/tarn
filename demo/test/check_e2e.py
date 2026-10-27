"""End-to-end walk of the user story on the real index.html, in one browser session.

Open the demo, type in the shell, run claude through permission and waiting, open a file from the
output in the viewer, split, drag a pane to a zone, change font size and theme in Settings, use the
Cmd and Ctrl+Alt keys, reload (state kept), reset the demo. No console errors, no external request.
Run: nice -n 10 uv run --with playwright python -I demo/test/check_e2e.py
"""

import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from lib import DEMO, Checks, app_page, cmd, server, show_pane

check = Checks()
TERM = '.tabview:not([hidden]) .leaf[data-kind="term"]'
TAB = ".sidebar .tab[data-tabid]"


def screen(pg, pane):
    return pg.evaluate(f"__tarn.screen('{pane}')")


def until(pg, pane, pattern, timeout=4.0):
    end = time.time() + timeout
    while True:
        text = screen(pg, pane)
        if re.search(pattern, text) or time.time() > end:
            return bool(re.search(pattern, text))
        time.sleep(0.05)


def run(pg, line):
    pg.keyboard.type(line)
    pg.keyboard.press("Enter")


def snap(pg):
    return pg.evaluate("__tarn.snapshot()")


def ready(pg):
    pg.wait_for_selector("html[data-ready=true]")


def folder_story(pg):
    """docs/specs/workspace-folder.md: the outside-folder mark, Set and Remove Folder, top tab prefix."""
    out = pg.locator(f"{TAB}[data-tabid='t2'] .l2.out")
    check(
        "F1 an agent outside its workspace folder is marked; one inside is not",
        out.count() == 1
        and "Outside the tarn folder" in (out.get_attribute("title") or "")
        and pg.locator(f"{TAB}[data-tabid='t1'] .out").count() == 0,
    )
    check(
        "F2 a workspace without a folder never marks",
        pg.locator(f"{TAB}[data-tabid='t6'] .out").count() == 0,
    )
    cmd(pg, "ws.folder", {"id": "w1", "folder": "~/code"})
    check("F3 Set Folder over the agent's folder clears the mark", out.count() == 0)
    cmd(pg, "ws.folder", {"id": "w1"})
    check(
        "F4 Remove Folder drops the folder and keeps the tabs",
        "folder" not in snap(pg)["workspaces"]["wss"][0]
        and snap(pg)["workspaces"]["wss"][0]["tabs"] == ["t1", "t2", "t3", "t4"],
    )
    cmd(pg, "ws.folder", {"id": "w1", "folder": "~/code/tarn"})
    cmd(pg, "tab.go", {"id": "t2"})
    cmd(pg, "tab.new", {"ws": "w1"})
    fresh = snap(pg)["workspaces"]["cur"]
    check(
        "F6 a new tab from a tab outside the folder starts in the workspace folder",
        snap(pg)["workspaces"]["tabs"][fresh]["cwd"] == "~/code/tarn",
    )
    cmd(pg, "tab.close", {"id": fresh})
    cmd(pg, "tab.go", {"id": "t1"})
    cmd(pg, "config.set", {"key": "tab-style", "value": "top"})
    check(
        "F5 with two or more workspaces a top tab starts with its workspace",
        pg.inner_text("#topTabs [data-toptab='t1'] .tw").strip() == "tarn ·"
        and pg.inner_text("#topTabs [data-toptab='t6'] .tw").strip() == "Default ·",
    )
    cmd(pg, "config.reset", {"key": "tab-style"})


def story(base):
    with app_page(base) as (pg, errors, requests):
        s = snap(pg)
        check(
            "E1 the demo opens on the seed: six tabs, three workspaces",
            len(s["workspaces"]["tabs"]) == 6 and len(s["workspaces"]["wss"]) == 3,
        )
        folder_story(pg)

        # type in the shell (Default workspace, tab 6)
        show_pane(pg, "p6")
        pg.locator("[data-pane='p6'] canvas").first.click()
        until(pg, "p6", "%")
        run(pg, "echo hello")
        check("2 typing in the shell runs a command", until(pg, "p6", r"\nhello\s*\n"))
        run(pg, "tarn --help")
        check(
            "E2a tarn --help marks only new as planned",
            until(pg, "p6", r"usage: tarn .*new \(planned\)"),
        )

        # claude through permission and waiting
        pg.evaluate("__tarn.clock.freeze()")
        run(pg, "claude")
        until(pg, "p6", "Type a request")
        run(pg, "update the spec")
        pg.evaluate("__tarn.clock.advance(3000)")
        time.sleep(0.3)
        check(
            "E3 claude asks for permission",
            snap(pg)["registry"]["p6"]["state"] == "permission",
        )
        pg.hover(f"{TAB}[data-tabid='t6']")
        pg.wait_for_selector("#tabcard [data-answer][data-allow='true']")
        pg.click("#tabcard [data-answer][data-allow='true']")
        pg.evaluate("__tarn.clock.advance(6000)")
        time.sleep(0.3)
        reg = snap(pg)["registry"]["p6"]
        check(
            "E4 Allow in the card lets the turn end in waiting",
            reg["state"] == "waiting",
        )

        # open a file from the output in the viewer
        pos = pg.evaluate("__tarn.linkAt('p6', 'docs/spec.md')")
        check("5 the output has a clickable path", pos is not None)
        pg.mouse.move(pos["x"], pos["y"])
        time.sleep(0.2)
        pg.mouse.click(pos["x"], pos["y"])
        pg.wait_for_selector('.leaf[data-kind="viewer"] iframe')
        tabs = pg.evaluate(
            "Object.values(__tarn.viewer().state().panes).flatMap((v) => v.tabs.map((t) => t.path))"
        )
        check(
            "E6 a click on the path opens the file in a viewer beside the terminal",
            any(t.endswith("/docs/spec.md") for t in tabs),
            str(tabs),
        )

        # split, then drag a pane to a zone
        pg.locator("[data-pane='p6'] canvas").first.click()
        pg.keyboard.press("Meta+d")
        pg.wait_for_function(
            "document.querySelectorAll('.tabview:not([hidden]) .leaf[data-kind=term]').length === 2"
        )
        check("7 Cmd+D splits the terminal", pg.locator(TERM).count() == 2)
        before = pg.evaluate(
            "JSON.stringify(__tarn.snapshot().workspaces.tabs.t6.layout)"
        )
        area = pg.locator("#ws").bounding_box()
        dt = pg.evaluate_handle("new DataTransfer()")
        pos = {
            "dataTransfer": dt,
            "clientX": area["x"] + 10,
            "clientY": area["y"] + area["height"] / 2,
        }
        pg.locator(
            '.tabview:not([hidden]) .leaf[data-kind="viewer"] .grip'
        ).dispatch_event("dragstart", {"dataTransfer": dt})
        pg.locator("#ws").dispatch_event("dragover", pos)
        framed = pg.locator("#ws > .drop").count() == 1
        pg.locator("#ws").dispatch_event("drop", pos)
        pg.evaluate("document.dispatchEvent(new Event('dragend'))")
        after = pg.evaluate(
            "JSON.stringify(__tarn.snapshot().workspaces.tabs.t6.layout)"
        )
        check(
            "E8 dragging the viewer to the left edge frames the zone and moves it",
            framed and before != after and pg.locator(TERM).count() == 2,
        )

        # Settings: font size and theme (the moved viewer page reloads first)
        pg.wait_for_function(
            "[...document.querySelectorAll('.viewer-pane iframe')].every("
            "(f) => f.contentDocument?.readyState === 'complete' && f.contentWindow.tarn)"
        )
        pg.keyboard.press("Meta+Comma")
        pg.click("#setNav [data-sec='appearance']")
        pg.fill("#g-font-size", "16")
        pg.press("#g-font-size", "Tab")
        pg.click("[data-theme-pick='Dracula']")
        opts = pg.evaluate(
            "[__tarn.term('p6').options.fontSize, __tarn.term('p6').options.theme.background]"
        )
        check(
            "E9 font-size and theme in Settings reach the terminal",
            opts == [16, "#282a36"],
            str(opts),
        )
        pg.keyboard.press("Escape")

        # Cmd and Ctrl+Alt keys
        n = len(snap(pg)["workspaces"]["tabs"])
        pg.locator("[data-pane='p6'] canvas").first.click()
        pg.keyboard.press("Meta+t")
        pg.keyboard.press("Control+Alt+t")
        check(
            "E10 Cmd+T and its Ctrl+Alt+T fallback open tabs",
            len(snap(pg)["workspaces"]["tabs"]) == n + 2,
        )
        pg.keyboard.press("Meta+1")
        first = snap(pg)["workspaces"]["cur"]
        pg.keyboard.press("Control+Alt+2")
        second = snap(pg)["workspaces"]["cur"]
        check(
            "E11 Cmd+1 and Ctrl+Alt+2 switch tabs",
            first == "t1" and second == "t2",
            f"{first} {second}",
        )
        total = n + 2

        # reload keeps state
        pg.reload()
        ready(pg)
        s = snap(pg)
        check(
            "E12 a reload keeps tabs and settings",
            len(s["workspaces"]["tabs"]) == total
            and s["config"]["font-size"] == 16
            and s["config"]["theme"] == "Dracula",
        )

        # reset the demo from the palette
        pg.keyboard.press("Meta+Shift+p")
        pg.fill("#palette input", "reset demo")
        with pg.expect_navigation():
            pg.keyboard.press("Enter")
        ready(pg)
        s = snap(pg)
        check(
            "E13 Reset demo returns to the seed and the default settings",
            len(s["workspaces"]["tabs"]) == 6
            and s["config"]["font-size"] == 13
            and s["config"]["theme"] == "",
        )

        check(
            "E14 no console errors in the whole walk", not errors, "; ".join(errors[:3])
        )
        check(
            "E15 no request leaves the demo origin",
            all(u.startswith((base, "data:")) for u in requests),
            str([u for u in requests if not u.startswith((base, "data:"))][:3]),
        )
        check("16 no caught errors on the bus", not pg.evaluate("__tarn.errors"))


def readme():
    text = (DEMO / "README.md").read_text()
    section = (
        text.split("Built vs planned", 1)[-1] if "Built vs planned" in text else ""
    )
    check(
        "E17 the README lists what is built and what is planned",
        "CLI" in section
        and "planned" in section.lower()
        and "built" in section.lower(),
    )


if __name__ == "__main__":
    with server() as base:
        story(base)
    readme()
    check.exit()
