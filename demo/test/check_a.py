"""Slice A checks: terminal panes, simulated shell, tarn CLI, scripted claude session.

Run: nice -n 10 uv run --with playwright python -I demo/test/check_a.py
Node tests of the shell itself: node --test demo/test/unit
The pages are test/pane.html (real vfs, config, registry, engine; commands of other slices recorded).
"""

import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from lib import Checks, browser_page, server

check = Checks()
REPO = "/Users/daniil/Dev/self-projects/tarn"
PROMPT = "daniil@MacBook ~/Dev/self-projects/tarn (main) %"


def screen(pg, pane):
    return pg.evaluate(f"__tarn.screen('{pane}')")


def until(pg, pane, pattern, timeout=3.0):
    """Wait until the pane screen matches the regex; return the screen."""
    end = time.time() + timeout
    while True:
        text = screen(pg, pane)
        if re.search(pattern, text) or time.time() > end:
            return text
        time.sleep(0.05)


def has(pg, pane, pattern):
    return bool(re.search(pattern, until(pg, pane, pattern)))


def run(pg, pane, line, wait=None):
    pg.keyboard.type(line)
    pg.keyboard.press("Enter")
    if wait:
        until(pg, pane, wait)
    else:
        time.sleep(0.25)


def type_text(pg, text):
    """Type characters that Playwright would insert without keydown (the engine ignores those)."""
    cdp = pg.context.new_cdp_session(pg)
    for ch in text:
        cdp.send("Input.dispatchKeyEvent", {"type": "keyDown", "key": ch, "text": ch})
        cdp.send("Input.dispatchKeyEvent", {"type": "keyUp", "key": ch})


def focus(pg, pane):
    pg.locator(f"[data-pane='{pane}'] canvas").first.click()


def last_prompt_line(pg, pane):
    lines = [ln.rstrip() for ln in screen(pg, pane).split("\n") if "%" in ln]
    return lines[-1] if lines else ""


def calls(pg, name):
    return pg.evaluate(f"window.calls.filter(c => c[0] === '{name}').map(c => c[1])")


def seeded(base):
    with browser_page(base, "test/pane.html", height=1400) as (pg, errors, requests):
        pg.wait_for_function("window.ready")
        for pane, cwd in (
            ("p1", "~/Dev/self-projects/tarn"),
            ("p3", "~/Dev/self-projects/tarn"),
            ("p4", "root@prod:~"),
        ):
            pg.evaluate(f"window.mount('{pane}', '{cwd}')")
        until(pg, "p4", "root@prod:~#")
        text1, text3, text4 = (screen(pg, p) for p in ("p1", "p3", "p4"))
        check(
            "seed p1 shows the claude transcript and its prompt",
            "Done. Changes:" in text1 and "> " in text1,
        )
        check(
            "seed p3 shows git status and the branch prompt",
            "git status -s" in text3 and " M docs/spec.md" in text3 and PROMPT in text3,
        )
        check(
            "seed p4 is a remote login with a root prompt",
            "Welcome to Ubuntu" in text4 and "root@prod:~#" in text4,
        )

        pos = pg.evaluate("__tarn.linkAt('p1', 'docs/spec.md')")
        pg.mouse.move(pos["x"], pos["y"])
        time.sleep(0.2)
        pg.mouse.click(pos["x"], pos["y"])
        time.sleep(0.2)
        check(
            "click on a path opens it in the viewer",
            [(c["path"], c["pane"], c.get("line")) for c in calls(pg, "viewer.open")]
            == [(f"{REPO}/docs/spec.md", "p1", None)],
            str(calls(pg, "viewer.open")),
        )
        pos = pg.evaluate("__tarn.linkAt('p1', 'Sidebar.swift:9')")
        pg.mouse.move(pos["x"], pos["y"])
        time.sleep(0.2)
        pg.mouse.click(pos["x"], pos["y"])
        time.sleep(0.2)
        check(
            "click on path:line carries the line",
            calls(pg, "viewer.open")[-1].get("line") == 9,
            str(calls(pg, "viewer.open")[-1]),
        )
        check(
            "seeded panes: no page errors",
            not errors and not pg.evaluate("__tarn.errors"),
            str(errors),
        )
        check(
            "no request leaves the demo origin",
            all(u.startswith(base) for u in requests),
        )


def shell_basics(base):
    with browser_page(base, "test/pane.html") as (pg, errors, _):
        pg.wait_for_function("window.ready")
        pg.evaluate("window.mount('p6', '~/Dev/self-projects/tarn')")
        until(pg, "p6", re.escape(PROMPT))
        focus(pg, "p6")
        check("prompt shows cwd and git branch", PROMPT in screen(pg, "p6"))

        run(pg, "p6", "echo hello", "hello\n")
        check("typing and Enter run a command", has(pg, "p6", r"\nhello *\n"))

        type_text(pg, "echo 日本")
        pg.keyboard.press("Enter")
        time.sleep(0.25)
        check("wide characters round trip", has(pg, "p6", r"\n日\s?本"))
        type_text(pg, "echo привет")
        pg.keyboard.press("Enter")
        time.sleep(0.25)
        check("cyrillic round trips", has(pg, "p6", r"\nпривет"))

        pg.keyboard.press("ArrowUp")
        time.sleep(0.15)
        check(
            "arrow up recalls the last command",
            last_prompt_line(pg, "p6").endswith("echo привет"),
        )
        pg.keyboard.press("ArrowUp")
        pg.keyboard.press("ArrowUp")
        time.sleep(0.15)
        check(
            "more arrow ups go further back",
            last_prompt_line(pg, "p6").endswith("echo hello"),
        )
        pg.keyboard.press("ArrowDown")
        pg.keyboard.press("ArrowDown")
        pg.keyboard.press("ArrowDown")
        pg.keyboard.press("Control+u")

        pg.keyboard.type("echo one two")
        pg.keyboard.press("Home")
        pg.keyboard.type("X")
        pg.keyboard.press("End")
        pg.keyboard.press("ArrowLeft")
        pg.keyboard.press("ArrowLeft")
        pg.keyboard.type("Y")
        time.sleep(0.15)
        check(
            "Home, End and arrows edit in place",
            last_prompt_line(pg, "p6").endswith("Xecho one tYwo"),
            last_prompt_line(pg, "p6"),
        )
        pg.keyboard.press("Control+u")

        pg.keyboard.type("cd mac")
        pg.keyboard.press("Tab")
        time.sleep(0.15)
        check("Tab completes a path", last_prompt_line(pg, "p6").endswith("cd macos/"))
        pg.keyboard.press("Control+u")
        pg.keyboard.type("c")
        pg.keyboard.press("Tab")
        pg.keyboard.press("Tab")
        check(
            "two Tabs list the candidates", has(pg, "p6", r"cat\s+cd\s+claude\s+clear")
        )
        pg.keyboard.press("Control+u")
        pg.keyboard.type("tarn o")
        pg.keyboard.press("Tab")
        time.sleep(0.15)
        check(
            "Tab completes a subcommand",
            last_prompt_line(pg, "p6").endswith("tarn open"),
        )
        pg.keyboard.press("Control+u")

        pg.keyboard.type("abandoned")
        pg.keyboard.press("Control+c")
        time.sleep(0.2)
        check(
            "Ctrl+C drops the line and draws a new prompt",
            "abandoned^C" in screen(pg, "p6")
            and last_prompt_line(pg, "p6").endswith("%"),
        )

        pg.keyboard.type("echo keep")
        pg.keyboard.press("Control+l")
        time.sleep(0.3)
        lines = screen(pg, "p6").split("\n")
        check(
            "Ctrl+L clears the screen and keeps the line",
            lines[0].rstrip().endswith("echo keep") and not lines[1].strip(),
        )
        pg.keyboard.press("Control+u")

        run(pg, "p6", "echo before")
        run(pg, "p6", "clear")
        check(
            "clear empties the screen",
            screen(pg, "p6").split("\n")[0].rstrip().endswith("%")
            and "before" not in screen(pg, "p6"),
        )

        run(pg, "p6", "nosuchcmd")
        check(
            "unknown command message",
            has(pg, "p6", r"zsh: command not found: nosuchcmd"),
        )
        run(pg, "p6", "cd docs")
        check("cd changes the prompt", has(pg, "p6", r"tarn/docs \(main\) %"))
        run(pg, "p6", "head -n 1 spec.md")
        check("head prints a seeded file", has(pg, "p6", r"# Spec: tarn"))
        run(pg, "p6", "cd ~")
        check(
            "outside a repo the branch is gone",
            last_prompt_line(pg, "p6") == "daniil@MacBook ~ %",
        )

        pg.keyboard.type("x" * 130)
        pg.keyboard.press("Home")
        pg.keyboard.type("Y")
        time.sleep(0.2)
        text = screen(pg, "p6")
        check(
            "a wrapped line edits in place", text.count("x") >= 130 and "% Yx" in text
        )
        pg.keyboard.press("Control+u")
        time.sleep(0.1)
        check(
            "kill line clears every wrapped row", "xxxxxxxxxx" not in screen(pg, "p6")
        )

        run(pg, "p6", "exit")
        check(
            "exit closes the pane",
            calls(pg, "pane.close") == [{"id": "p6", "exited": True}],
            str(calls(pg, "pane.close")),
        )
        check(
            "shell: no page errors",
            not errors and not pg.evaluate("__tarn.errors"),
            str(errors),
        )


def tarn_cli(base):
    with browser_page(base, "test/pane.html") as (pg, errors, _):
        pg.wait_for_function("window.ready")
        pg.evaluate("window.mount('p6', '~/Dev/self-projects/tarn', 700)")
        until(pg, "p6", re.escape(PROMPT))
        focus(pg, "p6")
        active = pg.evaluate("document.activeElement.tagName")

        run(pg, "p6", "tarn open docs/spec.md:7")
        check(
            "tarn open sends path and line to the viewer",
            calls(pg, "viewer.open")
            == [{"path": f"{REPO}/docs/spec.md", "line": 7, "pane": "p6"}],
            str(calls(pg, "viewer.open")),
        )
        run(pg, "p6", "tarn open nope.md", r"tarn: no such file: nope\.md")
        check(
            "tarn open on a missing file",
            has(pg, "p6", r"tarn: no such file: nope\.md"),
        )
        run(pg, "p6", "tarn new")
        check(
            "tarn new asks for a tab and does not take focus",
            len(calls(pg, "tab.new")) == 1
            and calls(pg, "tab.new")[0]["focus"] is False,
            str(calls(pg, "tab.new")),
        )
        check(
            "agent commands leave focus and input alone",
            pg.evaluate("document.activeElement.tagName") == active
            and last_prompt_line(pg, "p6").endswith("%"),
        )

        run(pg, "p6", "tarn ls", r"\n\d+\s+tarn\s+main\s+\w+\s+\d+[smh]")
        check(
            "tarn ls prints the row format of the spec",
            has(pg, "p6", r"\n1\s+tarn\s+main\s+waiting\s+\d+[smh]"),
            screen(pg, "p6")[:300],
        )
        run(pg, "p6", "tarn ls --json", r'"state": "waiting"')
        check(
            "tarn ls --json carries Session fields",
            has(pg, "p6", r'"seen": false') and has(pg, "p6", r'"pane": "p1"'),
            screen(pg, "p6"),
        )

        run(pg, "p6", "touch scratch.txt")
        run(pg, "p6", "git status -s", r"\?\? scratch\.txt")
        check(
            "git status follows vfs edits",
            has(pg, "p6", r"\?\? scratch\.txt") and has(pg, "p6", r" M docs/spec\.md"),
        )
        check(
            "tarn: no page errors",
            not errors and not pg.evaluate("__tarn.errors"),
            str(errors),
        )


def claude_session(base):
    with browser_page(base, "test/pane.html") as (pg, errors, _):
        pg.wait_for_function("window.ready")
        pg.evaluate("window.mount('p6', '~/Dev/self-projects/tarn')")
        until(pg, "p6", re.escape(PROMPT))
        focus(pg, "p6")
        pg.evaluate("__tarn.clock.freeze()")

        def session():
            return pg.evaluate("__tarn.snapshot().registry.p6 ?? null")

        def state():
            return (session() or {}).get("state")

        def advance(ms):
            pg.evaluate(f"__tarn.clock.advance({ms})")
            time.sleep(0.15)

        run(pg, "p6", "claude")
        until(pg, "p6", r"Type a request")
        check("claude starts without a state change", session() is None)
        run(pg, "p6", "update the spec")
        advance(1)
        check(
            "a request moves the registry to working",
            state() == "working",
            str(session()),
        )
        advance(2900)
        s = session()
        check(
            "the edit waits for permission with an answerable request",
            s["state"] == "permission"
            and s["answerable"] is True
            and s["request"]["tool"] == "Edit",
            str(s),
        )
        check(
            "the question is on the screen",
            has(pg, "p6", r"Do you want to make this edit to docs/spec\.md"),
        )

        pg.evaluate("document.getElementById('toast').hidden = true")
        pg.evaluate("window.bus.cmd('card.answer', {pane: 'p6', allow: true})")
        advance(10)
        check(
            "the card answer returns to working at once",
            state() == "working",
            str(session()),
        )
        check(
            "the edit reached the disk",
            pg.evaluate(
                f"__tarn.snapshot().vfs.files['{REPO}/docs/spec.md'].text.includes('Demo edit 1')"
            ),
        )
        advance(4000)
        s = session()
        check("the turn ends in waiting", s["state"] == "waiting", str(s))
        check(
            "the summary is printed and the claude prompt returns",
            has(pg, "p6", r"Done\. Request: update the spec")
            and has(pg, "p6", r"\n> "),
        )
        check("a turn that ends in the focused pane is seen", s["seen"] is True, str(s))

        run(pg, "p6", "second request")
        advance(3000)
        check("typing y answers in the terminal", state() == "permission")
        pg.keyboard.type("y")
        pg.keyboard.press("Enter")
        time.sleep(0.2)
        check(
            "a terminal answer sends no event", state() == "permission", str(session())
        )
        advance(1300)
        advance(700)
        check(
            "the next tool result clears permission",
            state() == "working",
            str(session()),
        )
        pg.keyboard.press("Control+c")
        time.sleep(0.2)
        check(
            "Ctrl+C aborts the turn and sends Stop",
            state() == "waiting" and has(pg, "p6", "Interrupted by user"),
        )
        before = pg.evaluate("__tarn.snapshot().registry.p6.since")
        advance(20000)
        check(
            "an aborted script leaves nothing running",
            pg.evaluate("__tarn.snapshot().registry.p6.since") == before,
        )

        run(pg, "p6", "third")
        advance(3000)
        pg.keyboard.type("n")
        pg.keyboard.press("Enter")
        time.sleep(0.2)
        advance(2000)
        check(
            "a refused edit ends in waiting and keeps the file",
            state() == "waiting" and has(pg, "p6", "Understood"),
        )
        run(pg, "p6", "/exit")
        check(
            "/exit returns to the shell and idles the session",
            state() == "idle" and has(pg, "p6", r"%\s*$"),
        )
        check(
            "claude: no page errors",
            not errors and not pg.evaluate("__tarn.errors"),
            str(errors),
        )


def two_sessions(base):
    with browser_page(base, "test/pane.html", height=800) as (pg, _errors, _):
        pg.wait_for_function("window.ready")
        pg.evaluate("window.mount('p6', '~')")
        pg.evaluate("window.mount('p3', '~/Dev/self-projects/tarn')")
        until(pg, "p3", "git status")
        pg.evaluate("__tarn.clock.freeze()")
        for pane in ("p6", "p3"):
            focus(pg, pane)
            run(pg, pane, "claude")
            until(pg, pane, "Type a request")
            run(pg, pane, "go")
        pg.evaluate("__tarn.clock.advance(3000)")
        time.sleep(0.2)
        reg = pg.evaluate("__tarn.snapshot().registry")
        check(
            "two panes run independent sessions keyed by pane",
            reg["p6"]["state"] == "permission" and reg["p3"]["state"] == "permission",
        )
        pg.evaluate("window.bus.cmd('card.answer', {pane: 'p3', allow: true})")
        time.sleep(0.2)
        reg = pg.evaluate("__tarn.snapshot().registry")
        check(
            "answering one card leaves the other waiting",
            reg["p3"]["state"] == "working" and reg["p6"]["state"] == "permission",
        )
        focus(pg, "p6")
        pg.evaluate("__tarn.clock.advance(5000)")
        time.sleep(0.2)
        reg = pg.evaluate("__tarn.snapshot().registry")
        check(
            "a turn that ends out of sight is done, not seen",
            reg["p3"]["state"] == "waiting" and reg["p3"]["seen"] is False,
            str(reg["p3"]),
        )


def config_and_keys(base):
    with browser_page(base, "test/pane.html") as (pg, errors, _):
        pg.wait_for_function("window.ready")
        pg.evaluate("window.mount('p6', '~/Dev/self-projects/tarn')")
        until(pg, "p6", re.escape(PROMPT))
        focus(pg, "p6")

        def option(name):
            return pg.evaluate(f"__tarn.term('p6').options.{name}")

        def setting(key, value):
            pg.evaluate(
                "([k, v]) => window.bus.cmd('config.set', {key: k, value: v})",
                [key, value],
            )
            time.sleep(0.3)

        setting("theme", "dracula")
        check("theme reaches the engine", option("theme.background") == "#282a36")
        check(
            "theme reaches the CSS",
            pg.evaluate(
                "getComputedStyle(document.querySelector('.pane')).backgroundColor"
            )
            == "rgb(40, 42, 54)",
        )
        setting("font-size", 18)
        check("font-size reaches the engine", option("fontSize") == 18)
        cols18 = pg.evaluate("__tarn.term('p6').cols")
        setting("font-size", 13)
        check(
            "a smaller font gives more columns",
            pg.evaluate("__tarn.term('p6').cols") > cols18,
        )
        setting("cursor-style", "bar")
        check("cursor-style reaches the engine", option("cursorStyle") == "bar")
        setting("cursor-style-blink", "false")
        check("cursor blink reaches the engine", option("cursorBlink") is False)
        setting("font-family", "Fira Code")
        check("font-family reaches the engine", "Fira Code" in option("fontFamily"))
        cols_before = pg.evaluate("__tarn.term('p6').cols")
        setting("window-padding-x", 40)
        check(
            "window-padding-x pads the pane and refits",
            pg.evaluate(
                "getComputedStyle(document.querySelector('.pane-term')).paddingLeft"
            )
            == "40px"
            and pg.evaluate("__tarn.term('p6').cols") < cols_before,
        )
        setting("window-padding-x", 2)

        pg.keyboard.type("echo one two")
        pg.keyboard.press("Alt+b")
        pg.keyboard.type("X")
        time.sleep(0.15)
        plain = last_prompt_line(pg, "p6")
        pg.keyboard.press("Control+u")
        setting("macos-option-as-alt", "true")
        pg.keyboard.type("echo one two")
        pg.keyboard.press("Alt+b")
        pg.keyboard.type("X")
        time.sleep(0.15)
        check(
            "with option-as-alt off, Alt+b is a plain b",
            plain.endswith("echo one twobX"),
            plain,
        )
        check(
            "with option-as-alt on, Alt+b moved the cursor",
            last_prompt_line(pg, "p6").endswith("echo one Xtwo"),
            last_prompt_line(pg, "p6"),
        )
        pg.keyboard.press("Control+u")

        pg.keyboard.type("keep")
        pg.keyboard.press("Meta+k")
        time.sleep(0.3)
        check(
            "Cmd+K clears the screen",
            screen(pg, "p6").split("\n")[0].rstrip().endswith("keep"),
        )
        pg.keyboard.press("Control+u")
        run(pg, "p6", "echo gone")
        pg.keyboard.press("Control+Alt+k")
        time.sleep(0.3)
        check("Ctrl+Alt+K is the fallback of Cmd+K", "gone" not in screen(pg, "p6"))

        size = option("fontSize")
        pg.keyboard.press("Meta+Equal")
        time.sleep(0.3)
        check("Cmd+= makes the font bigger", option("fontSize") == size + 1)
        pg.keyboard.press("Meta+Minus")
        pg.keyboard.press("Meta+Minus")
        time.sleep(0.3)
        check("Cmd+- makes it smaller", option("fontSize") == size - 1)
        pg.keyboard.press("Meta+Digit0")
        time.sleep(0.3)
        check("Cmd+0 resets it", option("fontSize") == size)
        pg.keyboard.press("Control+Alt+Equal")
        time.sleep(0.3)
        check("Ctrl+Alt+= is the fallback", option("fontSize") == size + 1)
        pg.keyboard.press("Meta+Digit0")

        for i in range(4):
            run(pg, "p6", "cat docs/spec.md")
        for i in range(8):
            run(pg, "p6", "ls")
        top = pg.evaluate("__tarn.term('p6').topRow")
        pg.keyboard.press("Meta+ArrowUp")
        time.sleep(1.2)
        moved = pg.evaluate("__tarn.term('p6').topRow")
        check("Cmd+Up jumps to an earlier prompt", moved < top, f"{top} -> {moved}")
        row = pg.evaluate(
            "(() => { const t = __tarn.term('p6'); return t.lineText(t.topRow) })()"
        )
        check(
            "the jump lands on a prompt line",
            row.startswith("daniil@MacBook"),
            row[:40],
        )
        pg.keyboard.press("Meta+ArrowDown")
        time.sleep(1.2)
        check("Cmd+Down moves forward", pg.evaluate("__tarn.term('p6').topRow") > moved)

        check(
            "config: no page errors",
            not errors and not pg.evaluate("__tarn.errors"),
            str(errors),
        )


def paste_and_notify(base):
    with browser_page(base, "test/pane.html") as (pg, errors, _):
        pg.wait_for_function("window.ready")
        pg.evaluate("window.mount('p6', '~')")
        until(pg, "p6", "ttys001")
        focus(pg, "p6")

        paste = """(text) => {
          const dt = new DataTransfer(); dt.setData('text', text);
          document.querySelector('[data-pane=p6] textarea').dispatchEvent(new ClipboardEvent('paste', {clipboardData: dt, bubbles: true, cancelable: true}));
        }"""
        pg.evaluate(paste, "echo a\necho b")
        time.sleep(0.2)
        check("a multi-line paste asks first", pg.locator(".paste-dialog").is_visible())
        pg.locator(".paste-dialog [data-cancel]").click()
        time.sleep(0.2)
        check(
            "Cancel pastes nothing",
            "echo a" not in screen(pg, "p6")
            and pg.locator(".paste-dialog").count() == 0,
        )
        pg.evaluate(paste, "echo a\necho b")
        pg.locator(".paste-dialog [data-paste]").click()
        time.sleep(0.3)
        check(
            "Paste sends the text; the shell keeps it on one line",
            has(pg, "p6", r"% echo a echo b$|% echo a echo b\s*$"),
        )
        pg.keyboard.press("Control+u")
        pg.evaluate(
            "window.bus.cmd('config.set', {key: 'clipboard-paste-protection', value: false})"
        )
        pg.evaluate(paste, "one\ntwo")
        time.sleep(0.3)
        check(
            "with protection off a multi-line paste goes straight in",
            pg.locator(".paste-dialog").count() == 0 and has(pg, "p6", "one two"),
        )
        pg.keyboard.press("Control+u")

        pg.evaluate(
            "window.bus.cmd('config.set', {key: 'notify-on-command-finish', value: 'always'})"
        )
        pg.evaluate("__tarn.clock.freeze()")
        run(pg, "p6", "sleep 4")
        pg.evaluate("__tarn.clock.advance(4100)")
        time.sleep(0.2)
        check(
            "a command over 3 s ends with a toast",
            "sleep finished in 4 s" in pg.inner_text("#toast"),
            repr(pg.inner_text("#toast")) + re.sub(" +", "_", screen(pg, "p6")),
        )
        pg.evaluate("document.getElementById('toast').textContent = ''")
        run(pg, "p6", "sleep 1")
        pg.evaluate("__tarn.clock.advance(1100)")
        time.sleep(0.2)
        check("a short command gives no toast", pg.inner_text("#toast") == "")
        check(
            "paste: no page errors",
            not errors and not pg.evaluate("__tarn.errors"),
            str(errors),
        )


def selection_and_urls(base):
    with browser_page(base, "test/pane.html") as (pg, errors, _):
        pg.wait_for_function("window.ready")
        pg.context.grant_permissions(["clipboard-read", "clipboard-write"])
        pg.evaluate("window.mount('p6', '~/Dev/self-projects/tarn')")
        until(pg, "p6", re.escape(PROMPT))
        focus(pg, "p6")
        run(pg, "p6", "echo https://example.com/demo")

        def select_word():
            a = pg.evaluate("__tarn.term('p6').cellCentre(0, 1)")
            b = pg.evaluate("__tarn.term('p6').cellCentre(5, 1)")
            pg.mouse.move(a["x"] - 3, a["y"])
            pg.mouse.down()
            pg.mouse.move(b["x"], b["y"], steps=5)
            pg.mouse.up()
            time.sleep(0.4)

        pg.evaluate("navigator.clipboard.writeText('untouched')")
        select_word()
        check(
            "copy-on-select none leaves the clipboard alone",
            pg.evaluate("navigator.clipboard.readText()") == "untouched",
        )
        pg.evaluate(
            "window.bus.cmd('config.set', {key: 'copy-on-select', value: 'clipboard'})"
        )
        pg.mouse.click(5, 5)
        time.sleep(0.4)
        select_word()
        check(
            "copy-on-select clipboard copies the selection",
            pg.evaluate("navigator.clipboard.readText()") == "daniil",
        )

        pg.evaluate("window.open = (url) => { window.opened = url }")
        pos = pg.evaluate("__tarn.linkAt('p6', 'https://example.com/demo')")
        pg.mouse.move(pos["x"], pos["y"])
        time.sleep(0.2)
        pg.mouse.click(pos["x"], pos["y"])
        time.sleep(0.2)
        check(
            "a plain click on a URL does nothing",
            pg.evaluate("window.opened ?? null") is None,
        )
        pg.keyboard.down("Meta")
        pg.mouse.click(pos["x"], pos["y"])
        pg.keyboard.up("Meta")
        time.sleep(0.2)
        check(
            "Cmd+click on a URL opens it",
            pg.evaluate("window.opened") == "https://example.com/demo",
        )
        pg.evaluate(
            "window.opened = null; window.bus.cmd('config.set', {key: 'link-url', value: false})"
        )
        pg.mouse.move(pos["x"] + 40, pos["y"] + 40)
        pg.mouse.move(pos["x"], pos["y"])
        pg.keyboard.down("Meta")
        pg.mouse.click(pos["x"], pos["y"])
        pg.keyboard.up("Meta")
        time.sleep(0.2)
        check(
            "link-url off: Cmd+click does nothing", pg.evaluate("window.opened") is None
        )
        check(
            "selection: no page errors",
            not errors and not pg.evaluate("__tarn.errors"),
            str(errors),
        )


def dispose(base):
    with browser_page(base, "test/pane.html") as (pg, errors, _):
        pg.wait_for_function("window.ready")
        pg.evaluate(
            "window.disposed = []; void window.bus.on('pane:disposed', d => disposed.push(d.pane))"
        )
        pg.evaluate("window.mount('p6', '~').then(p => { window.pane6 = p })")
        until(pg, "p6", "ttys001")
        focus(pg, "p6")
        pg.evaluate("__tarn.clock.freeze()")
        run(pg, "p6", "claude")
        run(pg, "p6", "go")
        pg.evaluate("__tarn.clock.advance(3000)")
        time.sleep(0.2)
        check(
            "the session exists before dispose",
            pg.evaluate("'p6' in __tarn.snapshot().registry"),
        )
        pg.evaluate("window.pane6.dispose()")
        time.sleep(0.2)
        check(
            "dispose frees the pane and the registry record",
            pg.evaluate("disposed") == ["p6"]
            and not pg.evaluate("'p6' in __tarn.snapshot().registry"),
            str(
                pg.evaluate(
                    "[disposed, Object.keys(__tarn.snapshot().registry), __tarn.errors]"
                )
            ),
        )
        pg.evaluate("__tarn.clock.advance(30000)")
        time.sleep(0.2)
        check(
            "a disposed pane's script sends no more events",
            not pg.evaluate("'p6' in __tarn.snapshot().registry"),
        )
        check(
            "dispose: no page errors",
            not errors and not pg.evaluate("__tarn.errors"),
            str(errors),
        )


if __name__ == "__main__":
    with server() as base:
        for suite in (
            seeded,
            shell_basics,
            tarn_cli,
            claude_session,
            two_sessions,
            config_and_keys,
            paste_and_notify,
            selection_and_urls,
            dispose,
        ):
            suite(base)
    check.exit()
