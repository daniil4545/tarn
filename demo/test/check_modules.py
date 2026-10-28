"""Modules checks: Settings > Modules, the five switches, greyed rows, Workspaces off and on.

Run: nice -n 10 uv run --with playwright python -I demo/test/check_modules.py
Runs on the real index.html. Switches are clicked in the settings window; state is read through
window.__tarn.
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from lib import Checks, app_page, cmd, server

check = Checks()
ASK = {
    "request": {"kind": "tool", "tool": "Edit", "detail": "docs/spec.md", "options": []},
    "answerable": True,
}


def config(pg, key):
    return pg.evaluate("k => __tarn.snapshot().config[k]", key)


def flip(pg, module):
    """Click a module switch in the open settings window."""
    pg.click(f"#m-{module}")


def groups(pg):
    return pg.evaluate(
        "__tarn.snapshot().workspaces.wss.map((w) => [w.name, w.tabs.length])"
    )


def rows(pg):
    return pg.locator("#sidebar .tab[data-tabid]").count()


def headers(pg):
    return pg.locator("#sidebar .wsh").filter(visible=True).count()


def show_card(pg, tab):
    pg.hover(f"#sidebar .tab[data-tabid={tab}]")
    pg.wait_for_selector("#tabcard", timeout=3000)


def sidebar_checks(pg):
    check(
        "M1 Settings lists Modules first with five rows",
        pg.locator("#setNav [data-sec]").first.inner_text() == "Modules"
        and pg.locator(".modrow").count() == 5,
    )
    titles = pg.locator(".modrow label").evaluate_all(
        "els => els.map((e) => e.firstChild.textContent)"
    )
    check(
        "M2 the rows are Sidebar, File viewer, Workspaces, Permission card, Notifications",
        titles
        == ["Sidebar", "File viewer", "Workspaces", "Permission card", "Notifications"],
        repr(titles),
    )
    check(
        "M3 each row has a detail line and the Agents line shows Claude Code 2.1.311 with three checks",
        pg.locator(".modrow small").count() == 5
        and "Claude Code 2.1.311" in pg.locator(".agent-line").inner_text()
        and pg.locator(".agent-line .chk.ok").count() == 3,
    )
    check(
        "M4 the tab style picker left Tabs: only Row size stays",
        pg.locator("input[name=tabstyle]").count() == 0
        and pg.locator("input[name=tabrows]").count() == 2,
    )
    check(
        "M5 all switches start on and nothing is greyed",
        pg.locator(".modrow input:checked").count() == 5
        and pg.locator(".modrow input:disabled").count() == 0,
    )

    flip(pg, "sidebar")
    check(
        "M6 Sidebar off shows the tabs at the top and hides the sidebar",
        config(pg, "tab-style") == "top"
        and pg.is_visible("#topTabs")
        and not pg.is_visible("#sidebar"),
    )
    check(
        "M7 Sidebar off greys Permission card with 'needs Sidebar', its value kept",
        pg.locator("[data-module=permissionCard] input").is_disabled()
        and pg.locator("[data-module=permissionCard] input").is_checked()
        and "needs Sidebar" in pg.locator("[data-module=permissionCard]").inner_text()
        and not pg.locator("[data-module=workspaces] input").is_disabled(),
    )
    check(
        "M8 Sidebar off: each grouped top tab carries its group name, an ungrouped one none",
        pg.locator("#topTabs .ttab .tw").first.inner_text() == "tarn"
        and pg.locator("#topTabs .ttab .tw").count() == 5,
    )
    flip(pg, "sidebar")
    check(
        "M9 Sidebar on again brings the sidebar and the card row back",
        pg.is_visible("#sidebar")
        and not pg.locator("[data-module=permissionCard] input").is_disabled()
        and "needs" not in pg.locator("[data-module=permissionCard]").inner_text(),
    )


def viewer_checks(pg):
    pg.keyboard.press("Escape")
    cmd(pg, "viewer.cmd", {"name": "tree"})
    pg.wait_for_selector(".tabview:not([hidden]) .leaf[data-kind=viewer]")
    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='modules']")
    flip(pg, "viewer")
    check(
        "M10 File viewer off hides the pane, the sidebar button and keeps the tab",
        pg.locator(".tabview:not([hidden]) .leaf[data-kind=viewer]").count() == 0
        and pg.locator("#sbViewer").count() == 0
        and pg.evaluate("Object.keys(__tarn.viewer().state().panes).length") == 1,
    )
    pg.click("#setNav [data-sec='viewer']")
    check(
        "M11 the File Viewer pane shows the same switch state",
        not pg.locator("#g-file-viewer").is_checked(),
    )
    pg.click("#g-file-viewer")
    check(
        "M12 switching it on in the File Viewer pane brings the pane back",
        config(pg, "file-viewer") is True
        and pg.locator(".tabview:not([hidden]) .leaf[data-kind=viewer]").count() == 1,
    )
    pg.click("#setNav [data-sec='modules']")
    check("M13 the Modules row follows", pg.locator("#m-viewer").is_checked())
    flip(pg, "viewer")
    pg.keyboard.press("Escape")
    pg.keyboard.press("Meta+b")
    check(
        "M14 Cmd+B does nothing while the viewer is off",
        pg.locator(".tabview:not([hidden]) .leaf[data-kind=viewer]").count() == 0,
    )
    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='modules']")
    flip(pg, "viewer")
    pg.keyboard.press("Escape")


def card_checks(pg):
    cmd(pg, "hook", {"pane": "p2", "name": "PermissionRequest", "event": ASK})
    show_card(pg, "t2")
    check(
        "M15 the card has Allow and Deny",
        pg.locator("#tabcard [data-answer]").count() == 2,
    )
    pg.mouse.move(700, 400)
    pg.wait_for_selector("#tabcard", state="detached")
    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='modules']")
    flip(pg, "permissionCard")
    pg.keyboard.press("Escape")
    show_card(pg, "t2")
    check(
        "M16 Permission card off: title and state stay, no buttons",
        pg.locator("#tabcard [data-answer]").count() == 0
        and "Needs permission" in pg.locator("#tabcard").inner_text(),
    )
    pg.mouse.move(700, 400)
    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='modules']")
    flip(pg, "permissionCard")
    pg.keyboard.press("Escape")
    show_card(pg, "t2")
    check(
        "M17 Permission card on again brings the buttons back",
        pg.locator("#tabcard [data-answer]").count() == 2,
    )
    pg.mouse.move(700, 400)


def notification_checks(pg):
    cmd(pg, "hook", {"pane": "p5", "name": "Stop", "event": {}})
    pg.wait_for_selector("#banner", timeout=2000)
    check("M18 a banner shows when an agent needs you", pg.locator("#banner").count() == 1)
    pg.wait_for_selector("#banner", state="detached", timeout=6000)
    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='modules']")
    flip(pg, "notifications")
    pg.keyboard.press("Escape")
    cmd(pg, "hook", {"pane": "p2", "name": "Stop", "event": {}})
    cur = pg.evaluate("__tarn.snapshot().workspaces.cur")
    pg.keyboard.press("Meta+u")
    check(
        "M19 Notifications off: no banner and Cmd+U does nothing",
        pg.locator("#banner").count() == 0
        and pg.evaluate("__tarn.snapshot().workspaces.cur") == cur,
    )
    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='modules']")
    flip(pg, "notifications")
    pg.keyboard.press("Escape")
    pg.keyboard.press("Meta+u")
    check(
        "M20 Notifications on again: Cmd+U jumps to a waiting session",
        pg.evaluate("__tarn.snapshot().workspaces.cur") != cur,
    )


def workspace_checks(pg):
    before = groups(pg)
    order = pg.evaluate("__tarn.snapshot().workspaces.wss.flatMap((w) => w.tabs)")
    check("M21 grouped by default: a header per group, none for the ungrouped tabs", headers(pg) == len([g for g in before if g[0]]))
    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='modules']")
    flip(pg, "workspaces")
    pg.keyboard.press("Escape")
    check(
        "M22 Workspaces off: flat list, no headers, no New Workspace, all tabs in order",
        headers(pg) == 0
        and pg.locator("#wsNewTop, #sidebar button#wsNew").count() == 0
        and pg.locator("#sidebar .tab[data-tabid]").evaluate_all(
            "els => els.map((e) => e.dataset.tabid)"
        )
        == order,
    )
    n = len(order)
    pg.keyboard.press("Meta+t")
    pg.wait_for_function("n => document.querySelectorAll('#sidebar .tab[data-tabid]').length === n + 1", arg=n)
    after = groups(pg)
    check(
        "M23 a new tab is ungrouped (one ungrouped list, no duplicate)",
        after[-1][0] == "" and after[-1][1] == before[-1][1] + 1 and after[:-1] == before[:-1]
        and [g[0] for g in after].count("") == 1,
        repr(after),
    )
    check(
        "M24 the new tab is last in the flat list",
        pg.evaluate(
            "(() => { const s = __tarn.snapshot().workspaces; return s.wss.flatMap((w) => w.tabs).at(-1) === s.cur })()"
        ),
    )
    snap = groups(pg)
    pg.keyboard.press("Meta+Shift+t")
    check("M25 Shift+Cmd+T does nothing", groups(pg) == snap)
    cmd(pg, "tab.move", {"id": "t4", "ws": "w2", "before": "t5"})
    ids = pg.locator("#sidebar .tab[data-tabid]").evaluate_all(
        "els => els.map((e) => e.dataset.tabid)"
    )
    check(
        "M26 a drag reorders across groups and keeps membership",
        ids.index("t4") == ids.index("t5") - 1
        and pg.evaluate(
            "__tarn.snapshot().workspaces.wss.find((w) => w.tabs.includes('t4')).name"
        )
        == "tarn",
        repr(ids),
    )
    pg.keyboard.press("Meta+Comma")
    pg.click("#setNav [data-sec='modules']")
    flip(pg, "workspaces")
    pg.keyboard.press("Escape")
    names = [g[0] for g in groups(pg)]
    check(
        "M27 Workspaces on again: frozen groups return, the new tab stays ungrouped",
        names[:3] == ["tarn", "release", ""]
        and pg.evaluate("__tarn.snapshot().workspaces.wss[0].tabs.includes('t4')")
        and pg.evaluate("__tarn.snapshot().workspaces.wss.at(-1).loose === true")
        and headers(pg) == len(names) - 1,
        repr(names),
    )


def main():
    with server() as base:  # noqa: SIM117 (the page needs the server address)
        with app_page(base) as (pg, errors, requests):
            pg.click("#tbSettings")
            check(
                "M0 the Settings button at the top right of the window opens Settings",
                pg.locator("#settings .setwin").is_visible(),
            )
            pg.click("#setNav [data-sec='modules']")
            sidebar_checks(pg)
            viewer_checks(pg)
            card_checks(pg)
            notification_checks(pg)
            workspace_checks(pg)
            check("M28 no page errors", not errors, "; ".join(errors[:3]))
    check.exit()


main()
