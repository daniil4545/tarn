"""Regression checks from the two code reviews of the demo (cr-demo-ui, cr-demo-term).

Each check names the review item. They run on the real index.html; a drag ends with the browser's
own events, not a hand-sent dragend.
Run: nice -n 10 uv run --with playwright python -I demo/test/check_review.py
"""

import json
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from check_a import focus, run, screen, until

from lib import Checks, app_page, cmd, new_pane, server

check = Checks()
REPO = "/Users/you/code/tarn"
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
        dirty_viewer(pg)
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
        pg.wait_for_function("!('t3' in __tarn.snapshot().workspaces.tabs)")
        text = pg.evaluate(f"__tarn.snapshot().vfs.files['{REPO}/docs/spec.md'].text")
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
        state = pg.evaluate(
            "[document.body.className, document.querySelectorAll('#ws > .drop').length]"
        )
        check(
            "R2 a real drag to the area edge leaves no dragging state behind",
            "dragging" not in state[0] and state[1] == 0,
            str(state),
        )
        layout = layout_ids(pg)
        check(
            "R2a the drop moved the viewer to the left edge",
            layout.startswith('{"dir":"row","ratio":0.5,"a":{"viewer"'),
            layout,
        )


def state(pg, pane):
    return pg.evaluate(f"__tarn.snapshot().registry['{pane}']?.state")


def claude_turn(pg, pane, allow):
    """Start a turn in the pane, answer the permission card, return (state at the card, final state)."""
    focus(pg, pane)
    pg.evaluate("__tarn.clock.freeze()")
    if "Type a request" not in screen(pg, pane):
        run(pg, pane, "claude")
        until(pg, pane, "Type a request")
    run(pg, pane, "go")
    pg.evaluate("__tarn.clock.advance(3000)")
    time.sleep(0.2)
    asked = state(pg, pane)
    pg.evaluate(
        f"window.bus.cmd('card.answer', {{ pane: '{pane}', allow: {str(allow).lower()} }})"
    )
    pg.evaluate("__tarn.clock.advance(6000)")
    time.sleep(0.3)
    return asked, state(pg, pane)


def term5_claude_reaches_stop(base):
    for allow in (True, False):
        word = "Allow" if allow else "Deny"
        bad = []
        with app_page(base) as (pg, _e, _r):
            for pane in ("p1", "p2", "p3", "p5", "p6"):
                got = claude_turn(pg, pane, allow)
                if got != ("permission", "waiting"):
                    bad.append(f"{pane}: {got}")
        check(
            f"T5 claude in every seeded tab reaches Stop on {word}",
            not bad,
            "; ".join(bad),
        )
    with app_page(base) as (pg, _e, _r):
        focus(pg, "p6")
        run(pg, "p6", "mkdir -p ~/code/bare/.git")
        pane = new_pane(pg, "~/code/bare")
        got = claude_turn(pg, pane, True)
        check(
            "T5a a repository without docs/spec.md still reaches Stop on Allow",
            got == ("permission", "waiting"),
            str(got),
        )


def tabs(pg):
    return len(ws(pg)["tabs"])


def key_event(pg, **init):
    """Send a keydown to the page body; return whether the page kept it (not default-prevented)."""
    return pg.evaluate(
        """(init) => {
          const e = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init });
          document.body.dispatchEvent(e);
          return !e.defaultPrevented;
        }""",
        init,
    )


def key5_altgraph(base):
    with app_page(base) as (pg, _e, _r):
        before = tabs(pg)
        kept = key_event(
            pg, key="t", code="KeyT", ctrlKey=True, altKey=True, modifierAltGraph=True
        )
        check(
            "K1 an AltGr character is not taken as a shortcut",
            kept and tabs(pg) == before,
        )
        before = tabs(pg)
        kept = key_event(pg, key="t", code="KeyT", ctrlKey=True, altKey=True)
        check(
            "K1a the same chord without AltGr still opens a tab",
            not kept and tabs(pg) == before + 1,
        )


def key6_fields_and_modal(base):
    with app_page(base) as (pg, _e, _r):
        cmd(pg, "tab.close", {"id": "t3"})
        count = tabs(pg)
        cmd(pg, "find.open", {})
        pg.locator("#findbar input").click()
        pg.keyboard.press("Meta+z")
        pg.keyboard.press("Meta+d")
        check(
            "K2 terminal keys in the Find field do not undo or split",
            tabs(pg) == count and "t3" not in ws(pg)["tabs"],
        )
        pg.keyboard.press("Escape")
        cmd(pg, "settings.open", {})
        pg.wait_for_selector("#settings:not([hidden])")
        pg.keyboard.press("Meta+t")
        pg.keyboard.press("Meta+n")
        before = ws(pg)
        check("K3 new-tab keys do nothing under the Settings window", tabs(pg) == count)
        pg.keyboard.press("Meta+w")
        pg.wait_for_selector("#settings", state="hidden")
        check(
            "K3a Cmd+W closes Settings and leaves the windows alone", ws(pg) == before
        )


def storage1_bad_data(base):
    bad = {
        "config": ["null", '"x"', "5", "{bad json"],
        "config-written": ['"x"', "{}"],
        "history": ["5", '{"a":1}', "[1,2]"],
        "vfs": ['{"files":null}', "null", '{"x":1}'],
        "sidebar": ["5", "[]"],
        "workspaces": [
            '{"tabs":{},"wss":[null],"cur":null}',
            '{"tabs":{},"wss":{},"cur":null}',
            (
                '{"tabs":{"t1":{"id":"t1","title":"x","cwd":"~"}},'
                '"wss":[{"id":"w1","name":"a","tabs":["t1"]}],"cur":"t1"}'
            ),
            (
                '{"tabs":{"t1":{"id":"t1","title":"x","cwd":"~","layout":{"dir":"row"}}},'
                '"wss":[{"id":"w1","name":"a","tabs":["t1"]}],"cur":"t1"}'
            ),
            (
                '{"tabs":{"t1":{"id":"t1","title":"x","cwd":"~","layout":{"viewer":"v1"}}},'
                '"wss":[{"id":"w1","name":"a","tabs":["t1"]}],"cur":"t1"}'
            ),
        ],
    }
    failed = []
    for part, values in bad.items():
        for value in values:
            init = f"localStorage.setItem('tarn-demo-v1:{part}', {value!r});"
            with app_page(base, init=init) as (pg, errors, _r):
                text = pg.inner_text("#toast")
                if "starting fresh" not in text or errors:
                    failed.append(f"{part}={value}: {text!r} {errors[:1]}")
    check(
        "D1 wrong-shaped saved data gives the seed and a toast",
        not failed,
        "; ".join(failed)[:300],
    )


def open_section(pg, name):
    cmd(pg, "settings.open", {})
    pg.wait_for_selector("#settings:not([hidden])")
    pg.click(f'#setNav [data-sec="{name}"]')


def set1_settings_match_app(base):
    with app_page(base) as (pg, _e, _r):
        open_section(pg, "appearance")
        note = pg.inner_text('[data-opt="window-padding-x"] .applies')
        check(
            "O1 window-padding-x says it applies to new windows",
            note == "Applies to new windows.",
            note,
        )
        for bad in ("99", "2.5", ""):
            pg.fill("#g-window-padding-x", bad)
            pg.dispatch_event("#g-window-padding-x", "change")
            err = pg.locator('[data-opt="window-padding-x"] .err').count()
            now = pg.evaluate("__tarn.snapshot().config['window-padding-x']")
            check(
                f"O2 padding {bad!r} shows an error and is not written",
                err == 1 and now == 2,
                str(now),
            )
        pg.fill("#g-font-family", "")
        pg.dispatch_event("#g-font-family", "change")
        conf = pg.text_content("#tarnConf")
        check(
            "O3 an empty font-family is one line", conf.count("font-family") == 1, conf
        )
        pg.fill("#g-font-family", 'My "Mono"')
        pg.dispatch_event("#g-font-family", "change")
        family = pg.evaluate(
            "document.querySelector('.leaf canvas')?.closest('[data-pane]') ? 1 : 0"
        )
        check(
            "O4 a font name with a quote leaves no page error",
            family == 1 and not _e,
            str(_e[:1]),
        )
        pg.click('[data-opt="font-family"] [data-greset]')
        pg.click('#setNav [data-sec="terminal"]')
        pg.select_option("#g-macos-option-as-alt", "left")
        pg.select_option("#g-macos-option-as-alt", "")
        pg.click('#setNav [data-sec="windows"]')
        conf = pg.text_content("#tarnConf")
        check(
            "O5 the empty entry writes an empty value",
            'macos-option-as-alt = ""' in conf,
            conf,
        )


def model1_workspace_rules(base):
    with app_page(base) as (pg, _e, _r):
        focus(pg, "p6")
        run(pg, "p6", "cd ~/code/tarn/docs")
        cmd(pg, "tab.new", {})
        new = ws(pg)
        tab = new["tabs"][new["cur"]]
        pane = tab["focus"]
        focus(pg, pane)
        run(pg, pane, "pwd")
        shown = until(pg, pane, r"/Users/you/code/tarn/docs")
        check(
            "M1 a new tab starts in the folder the focused shell moved to",
            tab["cwd"].endswith("code/tarn/docs")
            and "/Users/you/code/tarn/docs" in shown,
            f"{tab['cwd']}",
        )
    with app_page(base) as (pg, _e, _r):
        cmd(pg, "ws.delete", {"id": "w1"})
        loose = ws(pg)["wss"][0]
        check(
            "M2 deleting a group keeps its tabs ungrouped where they stood",
            loose.get("loose")
            and loose["tabs"] == ["t1", "t2", "t3", "t4"]
            and ws(pg)["wss"][1]["id"] == "w2",
            str(ws(pg)["wss"]),
        )
    with app_page(base) as (pg, _e, _r):
        cmd(pg, "tab.move", {"id": "t2", "ws": "loose", "after": "w1"})
        blocks = [
            (w["id"] if not w.get("loose") else "", w["tabs"]) for w in ws(pg)["wss"]
        ]
        indent = pg.evaluate(
            "['t1', 't2'].map((id) => getComputedStyle(document.querySelector(`.tab[data-tabid=${id}]`)).marginLeft)"
        )
        check(
            "M2a Remove from group puts the tab right below its group, ungrouped and not indented",
            blocks
            == [("w1", ["t1", "t3", "t4"]), ("", ["t2"]), ("w2", ["t5"]), ("", ["t6"])]
            and indent == ["12px", "0px"],
            f"{blocks} {indent}",
        )
    with app_page(base) as (pg, _e, _r):
        cmd(pg, "ws.fold", {"id": "w2"})
        cmd(pg, "tab.go", {"id": "t4"})
        cmd(pg, "tab.step", {"delta": 1})
        s = ws(pg)
        w2 = next(w for w in s["wss"] if w["id"] == "w2")
        check(
            "M3 stepping into a folded workspace unfolds it",
            s["cur"] == "t5" and not w2.get("collapsed"),
            s["cur"],
        )
    with app_page(base) as (pg, _e, _r):
        cmd(pg, "config.set", {"key": "tab-style", "value": "top"})
        sub = pg.text_content(".titlebar .sub")
        check(
            "M4 the title bar subtitle names the workspace in the top style",
            sub == "tarn",
            repr(sub),
        )
    with app_page(base) as (pg, _e, _r):
        cmd(pg, "viewer.open", {"path": "docs/spec.md"})
        pg.wait_for_selector(VIEWER)
        pg.reload()
        pg.wait_for_selector("html[data-ready=true]")
        check(
            "M5 after a reload no viewer pane is left empty",
            pg.locator('.leaf[data-kind="viewer"]').count() == 0
            and '"viewer"' not in json.dumps(ws(pg)["tabs"]),
        )


def privacy1_no_personal_data(base):
    """The demo is public: no real names, hosts or paths in any file it ships or tests."""
    root = pathlib.Path(__file__).resolve().parent.parent
    words = [
        "dan" + "iil",
        "gal" + "era",
        "self-" + "projects",
        "mac" + "book",
        "ssh " + "prod",
        "gm" + "ail",
    ]
    hits = []
    for path in root.rglob("*"):
        if not path.is_file() or path.name == pathlib.Path(__file__).name:
            continue
        if {"__pycache__", ".ruff_cache"} & set(path.parts) or path.suffix in {
            ".png",
            ".woff2",
            ".wasm",
            ".ttf",
        }:
            continue
        text = path.read_text(errors="ignore").lower()
        hits += [f"{path.relative_to(root)}: {w}" for w in words if w in text]
    check(
        "P1 no personal name, host or path in the demo", not hits, "; ".join(hits[:5])
    )
    with app_page(base) as (pg, _e, _r):
        seeded = pg.evaluate("JSON.stringify(__tarn.snapshot())").lower()
        check(
            "P1a the seed state holds none either",
            not [w for w in words if w in seeded],
        )


def exit1_no_undo_after_exit(base):
    with app_page(base) as (pg, _e, _r):
        focus(pg, "p3")
        run(pg, "p3", "exit")
        pg.wait_for_function("!('t3' in __tarn.snapshot().workspaces.tabs)")
        toast = pg.inner_text("#toast")
        pg.keyboard.press("Meta+z")
        check(
            "X1 a shell that exited is not offered for undo",
            "⌘Z" not in toast and "t3" not in ws(pg)["tabs"],
            toast,
        )


def dirty_viewer(pg, tab="t3"):
    """Open spec.md in a viewer of the tab and type unsaved text into it."""
    cmd(pg, "tab.go", {"id": tab})
    cmd(pg, "viewer.open", {"path": "docs/spec.md", "pane": None})
    pg.wait_for_selector(VIEWER)
    pg.wait_for_function(LOADED)
    frame = pg.frame_locator(f"{VIEWER} iframe").first
    frame.locator(".ftab.on").click()
    pg.keyboard.press("Meta+e")
    frame.locator(".cm-content").click()
    pg.keyboard.type("dirty text")
    frame.locator(".ftab.on .dirty").wait_for()
    time.sleep(0.5)  # the page sends its text in steps


def close_paths_ask(base):
    paths = {
        "tab.close": lambda pg: cmd(pg, "tab.close", {"id": "t3"}),
        "Cmd+W on the last terminal": lambda pg: (
            cmd(pg, "pane.focus", {"id": "p3"}),
            pg.keyboard.press("Meta+w"),
        ),
        "window.close": lambda pg: cmd(pg, "window.close", {}),
    }
    for name, close in paths.items():
        with app_page(base) as (pg, _e, _r):
            dirty_viewer(pg)
            close(pg)
            buttons = pg.locator(".ask-dialog button").all_inner_texts()
            alive = "t3" in ws(pg)["tabs"]
            if buttons:
                pg.click(".ask-dialog button:has-text('Cancel')")
            check(
                f"M1 {name} with a dirty viewer asks first and Cancel keeps the tab",
                buttons == ["Save", "Don't Save", "Cancel"]
                and alive
                and "t3" in ws(pg)["tabs"],
                f"{buttons} alive={alive}",
            )


def closed_window_keys_do_not_throw(base):
    with app_page(base) as (pg, errors, _r):
        for _ in range(6):
            cmd(pg, "tab.close", {})
        rows = pg.evaluate(
            """async () => {
              const mods = await Promise.all(['tabs', 'splits', 'find', 'terminal', 'viewer', 'help']
                .map((n) => import(`/js/keys/${n}.js`)));
              return mods.flatMap((m) => Object.values(m).flat())
                .filter((r) => r.when === 'terminal').map((r) => [r.cmd, r.payload ?? {}]);
            }"""
        )
        for name, payload in rows:
            cmd(pg, name, payload)
            if (
                ws(pg)["cur"] is not None
            ):  # a row such as Cmd+T opened a window: close it again
                cmd(pg, "window.close", {})
        for chord in ("Meta+f", "Meta+g", "Meta+Shift+g", "Meta+k"):
            pg.keyboard.press(chord)
        bus_errors = pg.evaluate("[...__tarn.errors]")
        check(
            "S1 with the window closed no terminal key throws",
            not bus_errors and not errors and len(rows) > 10,
            f"{bus_errors[:3]} {errors[:2]} rows={len(rows)}",
        )


def where(pg):
    """Where the keyboard is: terminal pane id, 'tree' or 'file' (inside a viewer), or other."""
    return pg.evaluate(
        """() => {
          const a = document.activeElement;
          if (a?.tagName === 'IFRAME') {
            const inner = a.contentDocument.activeElement;
            return inner?.closest?.('#vtree') ? 'tree' : 'file';
          }
          return a?.closest?.('[data-pane]')?.dataset.pane ?? 'other';
        }"""
    )


def settle(pg, seconds=0.6):
    time.sleep(seconds)


CMD_B = "Meta+b"


def n_panes(pg):
    return pg.locator('.tabview:not([hidden]) .leaf[data-kind="viewer"]').count()


def n_hidden(pg, tab="t1"):
    return len(ws(pg)["tabs"][tab].get("hidden", []))


def open_file(pg):
    cmd(pg, "viewer.open", {"path": "docs/spec.md"})
    pg.wait_for_function(
        "Object.values(__tarn.viewer().state().panes).some((p) => p.tabs.length)"
    )
    pg.wait_for_function(LOADED)
    settle(pg)


def file_tabs(pg):
    return pg.evaluate(
        "Object.values(__tarn.viewer().state().panes).flatMap((p) => p.tabs.map((t) => t.path))"
    )


def with_file(pg):
    focus(pg, "p1")
    open_file(pg)
    focus(pg, "p1")


def press(pg, key, wait=True):
    pg.keyboard.press(key)
    if wait:
        settle(pg)


def keys_table(base):
    """Every cell of the Cmd+B / Cmd+W table, with where the keyboard ends up."""
    with app_page(base) as (pg, _e, _r):
        focus(pg, "p1")
        press(pg, CMD_B, False)
        pg.wait_for_function(LOADED)
        settle(pg)
        check(
            "B1 Cmd+B with no pane opens it, keyboard in the tree",
            n_panes(pg) == 1 and where(pg) == "tree",
            where(pg),
        )
        press(pg, CMD_B)
        check(
            "B2 Cmd+B on a shown pane with no file hides it (never closes), keyboard in the terminal",
            n_panes(pg) == 0 and n_hidden(pg) == 1 and where(pg) == "p1",
            f"{n_panes(pg)} {n_hidden(pg)} {where(pg)}",
        )
        press(pg, CMD_B, False)
        pg.wait_for_function(LOADED)
        settle(pg)
        check(
            "B3 Cmd+B on a hidden pane shows it, keyboard in the pane",
            n_panes(pg) == 1 and n_hidden(pg) == 0 and where(pg) in ("tree", "file"),
            where(pg),
        )
        press(pg, "Meta+w")
        check(
            "W1 Cmd+W in a pane with no file closes the pane",
            n_panes(pg) == 0 and n_hidden(pg) == 0,
            f"{n_panes(pg)} {n_hidden(pg)}",
        )
    with app_page(base) as (pg, _e, _r):
        focus(pg, "p1")
        open_file(pg)
        cmd(pg, "viewer.open", {"path": "docs/architecture.md", "background": True})
        pg.wait_for_function(
            "Object.values(__tarn.viewer().state().panes).some((p) => p.tabs.length === 2)"
        )
        settle(pg)
        pg.frame_locator(f"{VIEWER} iframe").first.locator(".ftab.on").click()
        press(pg, "Meta+w")
        check(
            "W2 Cmd+W with files closes the active tab only",
            n_panes(pg) == 1 and len(file_tabs(pg)) == 1,
            str(file_tabs(pg)),
        )
        press(pg, "Meta+w")
        check(
            "W3 Cmd+W on the last tab closes the pane",
            n_panes(pg) == 0 and n_hidden(pg) == 0,
            f"{n_panes(pg)} {n_hidden(pg)}",
        )
    with app_page(base) as (pg, _e, _r):
        with_file(pg)
        press(pg, CMD_B)
        check(
            "B4 Cmd+B on a pane with files hides the whole pane, keyboard in the terminal",
            n_panes(pg) == 0 and n_hidden(pg) == 1 and where(pg) == "p1",
            f"{n_panes(pg)} {n_hidden(pg)} {where(pg)}",
        )
        press(pg, CMD_B, False)
        pg.wait_for_function(LOADED)
        settle(pg)
        check(
            "B5 Cmd+B shows it back with its tabs",
            n_panes(pg) == 1 and f"{REPO}/docs/spec.md" in file_tabs(pg),
            str(file_tabs(pg)),
        )
    with app_page(base) as (pg, _e, _r):
        focus(pg, "p1")
        press(pg, CMD_B, False)
        pg.wait_for_function(LOADED)
        settle(pg)
        frame = pg.frame_locator(f"{VIEWER} iframe").first
        frame.locator("#vtree .tree").focus()
        frame.locator("#vtree .tr", has_text="README.md").first.wait_for()
        for _ in range(8):
            if pg.evaluate(
                "document.querySelector('iframe').contentDocument.activeElement.closest('.tr')?.textContent.includes('README')"
            ):
                break
            pg.keyboard.press("ArrowDown")
        pg.keyboard.press("Enter")
        pg.wait_for_function(
            "Object.values(__tarn.viewer().state().panes).some((p) => p.tabs.length)"
        )
        settle(pg)
        check(
            "T1 Enter on a file in the tree opens it and moves the keyboard to the file",
            where(pg) == "file" and len(file_tabs(pg)) == 1,
            f"{where(pg)} {file_tabs(pg)}",
        )


def keys_fallback_help_hidden_edits(base):
    with app_page(base) as (pg, _e, _r):
        focus(pg, "p1")
        press(pg, "Control+Alt+b", False)
        pg.wait_for_function(LOADED)
        settle(pg)
        opened = n_panes(pg) == 1 and where(pg) == "tree"
        press(pg, "Control+Alt+b")
        check(
            "F1 Ctrl+Alt+B does what Cmd+B does",
            opened and n_panes(pg) == 0 and n_hidden(pg) == 1,
            f"{opened} {n_panes(pg)}",
        )
        for gone in ("Alt+Cmd+B", "Shift+Cmd+E"):
            rows = pg.evaluate(
                "async (c) => { const m = await import('/js/keys/viewer.js'); return m.viewerKeys.filter((r) => r.chords.includes(c)).length }",
                gone.replace("Alt+Cmd+B", "Cmd+Alt+B").replace(
                    "Shift+Cmd+E", "Cmd+Shift+E"
                ),
            )
            check(f"F2 no key row for {gone}", rows == 0)
        cmd(pg, "settings.open", {})
        pg.click('#setNav [data-sec="help"]')
        text = pg.text_content("#settings")
        check(
            "F3 Help lists Toggle Pane with its fallback",
            "Toggle Pane" in text
            and "Ctrl+Alt+B" in text
            and "Focus Files" not in text,
        )
    with app_page(base) as (pg, _e, _r):
        dirty_viewer(pg)
        press(pg, CMD_B)
        hid = n_hidden(pg, "t3")
        cmd(pg, "tab.close", {"id": "t3"})
        buttons = pg.locator(".ask-dialog button").all_inner_texts()
        if buttons:
            pg.click(".ask-dialog button:has-text('Cancel')")
        check(
            "H1 a hidden pane with unsaved text still asks when its tab closes",
            hid == 1
            and buttons == ["Save", "Don't Save", "Cancel"]
            and "t3" in ws(pg)["tabs"],
            f"{hid} {buttons}",
        )
        press(pg, CMD_B, False)
        pg.wait_for_function(LOADED)
        settle(pg)
        dirty = pg.evaluate(
            "Object.values(__tarn.viewer().state().panes).flatMap((p) => p.tabs.map((t) => t.dirty))"
        )
        check(
            "H2 the unsaved text is still there after hide and show",
            True in dirty,
            str(dirty),
        )


def frame_of(pg):
    return pg.frame_locator(f"{VIEWER} iframe").first


def open_in_viewer(pg, path, **extra):
    cmd(pg, "viewer.open", {"path": path, **extra})
    pg.wait_for_selector(VIEWER)
    pg.wait_for_function(LOADED)
    settle(pg)


def viewer_follows_app_arrows_and_code(base):
    long_text = "\n\n".join(f"Paragraph {i} of a long document." for i in range(1, 200))
    with app_page(base) as (pg, _e, _r):
        cmd(
            pg,
            "vfs.write",
            {"path": f"{REPO}/docs/long.md", "text": long_text, "by": "shell"},
        )
        focus(pg, "p1")
        open_in_viewer(pg, "docs/long.md", tree=True)
        check(
            "A0 a tree opened with a file has the keyboard in the tree",
            where(pg) == "tree",
            where(pg),
        )
        pg.keyboard.press("ArrowLeft")
        settle(pg, 0.3)
        check(
            "A1 Left in the tree moves the keyboard to the file",
            where(pg) == "file",
            where(pg),
        )
        top = lambda: pg.evaluate(
            "document.querySelector('.viewer-pane iframe').contentDocument.querySelector('#vcontent .scroll').scrollTop"
        )
        pg.keyboard.press("ArrowDown")
        pg.keyboard.press("PageDown")
        settle(pg, 0.3)
        check("A2 Down and Page Down scroll a viewed file", top() > 40, str(top()))
        pg.keyboard.press("ArrowRight")
        settle(pg, 0.3)
        check(
            "A3 Right in a viewed file moves the keyboard to the tree",
            where(pg) == "tree",
            where(pg),
        )
        pg.keyboard.press("Escape")
        settle(pg, 0.3)
        frame_of(pg).locator("#vcontent").focus()
        pg.keyboard.press("ArrowRight")
        settle(pg, 0.5)
        check(
            "A4 Right shows a hidden tree and puts the keyboard in it",
            where(pg) == "tree",
            where(pg),
        )
    with app_page(base) as (pg, _e, _r):
        focus(pg, "p1")
        open_in_viewer(pg, "tools/export.go")
        frame_of(pg).locator(".ftab.on").click()
        pg.keyboard.press("Meta+e")
        settle(pg)
        keywords = frame_of(pg).locator(".cm-content .hljs-keyword").count()
        check(
            "E1 a code file opens in the editor with colors by language",
            keywords > 0,
            str(keywords),
        )
        frame_of(pg).locator(".cm-content").click()
        pg.keyboard.type("// edited")
        time.sleep(0.5)
        pg.keyboard.press("Meta+s")
        settle(pg)
        text = pg.evaluate(
            f"__tarn.snapshot().vfs.files['{REPO}/tools/export.go'].text"
        )
        check("E2 Cmd+S saves a code file", "// edited" in text)
        before = pg.evaluate(
            f"__tarn.snapshot().vfs.files['{REPO}/plugin/hooks/hooks.json'].text"
        )
        cmd(pg, "viewer.open", {"path": "plugin/hooks/hooks.json"})
        settle(pg)
        frame_of(pg).locator(".ftab.on").click()
        pg.keyboard.press("Meta+e")
        frame_of(pg).locator(".cm-content").click()
        pg.keyboard.type("1")
        time.sleep(0.5)
        pg.keyboard.press("Meta+s")
        settle(pg)
        check(
            "E3 a json file edits and saves too",
            "1"
            in pg.evaluate(
                f"__tarn.snapshot().vfs.files['{REPO}/plugin/hooks/hooks.json'].text"
            )
            and "1" not in before,
        )


def viewer_switch(base):
    with app_page(base) as (pg, _e, _r):
        cmd(pg, "settings.open", {})
        pg.click('#setNav [data-sec="modules"]')
        check(
            "V0 Settings Modules has the File viewer switch on",
            pg.is_checked("#m-viewer"),
        )
        pg.uncheck("#m-viewer")
        pg.keyboard.press("Escape")
        shell_pane = new_pane(pg, "~/code/tarn")
        until(pg, shell_pane, "%")
        focus(pg, shell_pane)
        press(pg, CMD_B)
        check(
            "V1 switch off: Cmd+B opens no pane",
            n_panes(pg) == 0 and "off" in pg.inner_text("#toast"),
            pg.inner_text("#toast"),
        )
        cmd(pg, "viewer.open", {"path": "README.md"})
        settle(pg, 0.3)
        check(
            "V2 switch off: a path click opens no pane and says so",
            n_panes(pg) == 0 and "default app" in pg.inner_text("#toast"),
        )
        run(pg, shell_pane, "tarn open README.md")
        shown = until(pg, shell_pane, "viewer is off")
        check(
            "V3 switch off: tarn open answers that the viewer is off",
            "the file viewer is off" in shown and n_panes(pg) == 0,
        )
        pg.evaluate("window.bus.cmd('config.set', {key: 'file-viewer', value: true})")
        cmd(pg, "viewer.open", {"path": "README.md"})
        pg.wait_for_selector(VIEWER)
        pg.evaluate("window.bus.cmd('config.set', {key: 'file-viewer', value: false})")
        settle(pg)
        check(
            "V4 an open pane is hidden with the switch off and keeps its tab",
            n_panes(pg) == 0
            and pg.evaluate("Object.keys(__tarn.viewer().state().panes).length") == 1,
        )
        press(pg, CMD_B)
        settle(pg)
        check("V5 Cmd+B does nothing with the switch off", n_panes(pg) == 0)
        pg.evaluate("window.bus.cmd('config.set', {key: 'file-viewer', value: true})")
        pg.wait_for_function(LOADED)
        settle(pg)
        check(
            "V6 the pane comes back with its file tab when the switch is on",
            n_panes(pg) == 1 and f"{REPO}/README.md" in file_tabs(pg),
            str(file_tabs(pg)),
        )


SUITES = [
    keys_table,
    viewer_follows_app_arrows_and_code,
    viewer_switch,
    keys_fallback_help_hidden_edits,
    close_paths_ask,
    closed_window_keys_do_not_throw,
    exit1_no_undo_after_exit,
    privacy1_no_personal_data,
    model1_workspace_rules,
    key5_altgraph,
    key6_fields_and_modal,
    storage1_bad_data,
    set1_settings_match_app,
    term5_claude_reaches_stop,
    ui1_undo_keeps_later_layout,
    ui3_undo_last_tab,
    ui4_dirty_viewer_asks,
    ui2_real_drag_clears_state,
]

if __name__ == "__main__":
    with server() as base:
        for suite in SUITES:
            try:
                suite(base)
            except Exception as error:  # noqa: BLE001 - a crashed suite is a red check, not a lost report
                check(f"{suite.__name__} ran to the end", False, str(error)[:120])
    check.exit()
