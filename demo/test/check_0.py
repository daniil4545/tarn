"""Slice 0 checks: engine spike items 1-9 through term-adapter.js, page boot, shared contracts.

Run: nice -n 10 uv run --with playwright python -I demo/test/check_0.py
Spike item 10 (reserved browser keys) is manual: demo/test/keys.html.
Everything runs on the real index.html; the engine items add bare adapter terminals over the window.
"""

import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from lib import Checks, browser_page, server

check = Checks()

DRAWS = """
window.__draws = 0;
for (const m of ['fillRect', 'fillText', 'clearRect', 'drawImage', 'stroke', 'fill']) {
  const o = CanvasRenderingContext2D.prototype[m];
  CanvasRenderingContext2D.prototype[m] = function (...a) { window.__draws++; return o.apply(this, a); };
}
"""

STAGE = """async () => {
  const { createTerm } = await import('/js/term-adapter.js');
  const host = Object.assign(document.createElement('div'), { id: 'spike-host' });
  host.style.cssText = 'position:fixed;left:0;top:0;z-index:9999;background:#000';
  document.body.append(host);
  window.make = async (opts = {}) => {
    const el = document.createElement('div');
    el.style.cssText = 'width:640px;height:300px';
    host.append(el);
    return createTerm(el, { fontSize: 14, fontFamily: '"JetBrains Mono", monospace', ...opts });
  };
}"""


def engine_page(base, **kwargs):
    """The real page with the bare-adapter stage: `make()` mounts a terminal in an overlay."""
    return browser_page(base, "index.html", **kwargs)


def stage(pg):
    pg.wait_for_selector("html[data-ready=true]")
    pg.evaluate(STAGE)


MAKE = "async () => { const t = await make(); window.t = t; window.got = []; t.onData(d => got.push(d)); return [t.cols, t.rows]; }"


def pressed(pg, key):
    pg.evaluate("got.length = 0")
    pg.keyboard.press(key)
    return pg.evaluate("got.slice()")


def spike_basics(base):
    with engine_page(base, init=DRAWS) as (pg, errors, _):
        stage(pg)
        cols, rows = pg.evaluate(MAKE)
        check(
            "spike 1 load from static server, terminal draws",
            cols > 40 and pg.locator("#spike-host canvas").count() == 1,
        )

        pg.evaluate(
            "t.write('hello \\x1b[31mred\\x1b[0m привет\\r\\nsee src/main.go:42 now\\r\\n')"
        )
        text = pg.evaluate("t.screenText()").split("\n")
        check(
            "spike 2 screen text: rows x cols with blanks, cyrillic",
            len(text) == rows
            and all(len(r) == cols for r in text)
            and text[0].startswith("hello red привет"),
            f"{len(text)} rows, widths {sorted({len(r) for r in text})}",
        )

        pg.evaluate("window.sel = []; void t.onSelection(s => sel.push(s))")
        a, b = pg.evaluate("[t.cellCentre(0, 1), t.cellCentre(7, 1)]")
        pg.mouse.move(a["x"] - 3, a["y"])
        pg.mouse.down()
        pg.mouse.move(b["x"], b["y"], steps=6)
        pg.mouse.up()
        time.sleep(0.2)
        selected = pg.evaluate("t.getSelection()")
        check(
            "spike 5 selection text and event",
            selected == "see src/" and pg.evaluate("sel.length") > 0,
            repr((selected, pg.evaluate("[sel.length, t.topRow, t.lineCount]"))),
        )

        pg.evaluate(
            """() => { window.acts = [];
              t.addLinkProvider(l => [...l.matchAll(/[\\w./-]+:\\d+/g)].map(m => ({start: m.index, end: m.index + m[0].length, text: m[0]})),
                (text) => acts.push(text)); }"""
        )
        pos = pg.evaluate("t.cellCentre(8, 1)")
        pg.mouse.move(pos["x"], pos["y"])
        time.sleep(0.2)
        pg.mouse.click(pos["x"], pos["y"])
        time.sleep(0.3)
        check(
            "spike 3 link provider reports path:line on click",
            pg.evaluate("acts") == ["src/main.go:42"],
            str(pg.evaluate("acts")),
        )

        pg.evaluate(
            "t.write('\\x1b[2J\\x1b[H'); for (let i = 0; i < 100; i++) t.write('line ' + String(i).padStart(3, '0') + '\\r\\n'); t.write('PROMPT> ')"
        )
        info = pg.evaluate(
            "({row: t.cursorRow, text: t.lineText(t.cursorRow).trimEnd(), count: t.lineCount})"
        )
        check(
            "spike 4 prompt row is readable for jumps",
            info["text"] == "PROMPT>" and info["count"] > 100,
            str(info),
        )
        pg.evaluate("t.scrollToRow(10)")
        time.sleep(1.5)
        top = pg.evaluate("t.topRow")
        check("spike 4 scrollToRow moves the viewport", top == 10, f"top {top}")

        hit = pg.evaluate(
            "(() => { for (let y = 0; y < t.lineCount; y++) if (t.lineText(y).includes('line 042')) return y; return -1 })()"
        )
        check("spike 6 own scan finds text in scrollback", hit > 0, f"row {hit}")

        pg.mouse.click(5, 5)
        check(
            "spike 7 printable, Enter, Backspace, arrows",
            [pressed(pg, k) for k in ("a", "Enter", "Backspace", "ArrowLeft")]
            == [["a"], ["\r"], ["\x7f"], ["\x1b[D"]],
        )
        check(
            "spike 7 Ctrl+C and Tab",
            [pressed(pg, "Control+c"), pressed(pg, "Tab")] == [["\x03"], ["\t"]],
        )
        check("spike 7 Shift+Tab encoded", pressed(pg, "Shift+Tab") == ["\x1b[Z"])
        check("spike 7 Cmd+K does not leak a letter", pressed(pg, "Meta+k") == [])
        check(
            "spike 7 Alt+f is plain f while option-as-alt is off",
            pressed(pg, "Alt+f") == ["f"],
        )
        pg.evaluate("t.optionAsAlt = true")
        check(
            "spike 7 Alt+f sends ESC f with option-as-alt",
            pressed(pg, "Alt+f") == ["\x1bf"],
        )

        cdp = pg.context.new_cdp_session(pg)
        pg.evaluate("got.length = 0")
        for ch, code, vk in (("ж", "Semicolon", 186), ("п", "KeyG", 71)):
            cdp.send(
                "Input.dispatchKeyEvent",
                {
                    "type": "keyDown",
                    "key": ch,
                    "code": code,
                    "text": ch,
                    "windowsVirtualKeyCode": vk,
                },
            )
            cdp.send(
                "Input.dispatchKeyEvent",
                {"type": "keyUp", "key": ch, "code": code, "windowsVirtualKeyCode": vk},
            )
        check(
            "spike 7 Cyrillic keys",
            pg.evaluate("got") == ["ж", "п"],
            str(pg.evaluate("got")),
        )
        check("spike console clean", not errors, str(errors))


def spike_idle(base):
    with engine_page(base, init=DRAWS) as (pg, _, _):
        stage(pg)
        pg.evaluate(
            "import('/js/bus.js').then(m => m.bus.cmd('config.set', {key: 'cursor-style-blink', value: 'false'}))"
        )
        pg.evaluate(
            "async () => { window.ts = []; for (let i = 0; i < 6; i++) { const t = await make({fontSize: 12}); t.write('hi\\r\\n'); ts.push(t); } }"
        )
        time.sleep(1.0)
        before = pg.evaluate("window.__draws")
        time.sleep(3.0)
        idle = pg.evaluate("window.__draws") - before
        check(
            "spike 8 idle: 0 canvas draws in 3 s with 6 panes, blink off",
            idle == 0,
            f"{idle} draws",
        )
        pg.evaluate("ts[0].write('typed')")
        time.sleep(0.3)
        check("spike 8 a write still draws", pg.evaluate("window.__draws") - before > 0)


def spike_dpr(base):
    probe = """async () => {
      const t = await make(); window.t = t;
      t.write('\\x1b[44m' + ' '.repeat(t.cols) + '\\x1b[0m\\r\\n'); t.write('\\x1b[44m' + ' '.repeat(t.cols) + '\\x1b[0m');
      await new Promise(r => setTimeout(r, 400));
      const c = document.querySelector('#spike-host canvas'), ctx = c.getContext('2d');
      const w = Math.floor(c.width / t.cols * (t.cols - 1));
      const h = Math.floor(2 * c.height / t.rows);
      const px = ctx.getImageData(0, 0, w, h).data, colours = new Set();
      for (let i = 0; i < px.length; i += 4) colours.add(px[i] + ',' + px[i + 1] + ',' + px[i + 2]);
      return [...colours];
    }"""
    for dpr in (1, 1.25, 1.5, 2):
        with engine_page(base, dpr=dpr) as (pg, _, _):
            stage(pg)
            colours = pg.evaluate(probe)
            check(f"spike 9 no seams at DPR {dpr}", len(colours) == 1, str(colours))


CONTRACT = """async () => {
  const bus = await import('/js/bus.js');
  const state = await import('/js/state.js');
  const reg = await import('/js/registry.js');
  const schema = await import('/js/keys/schema.js');
  const keymap = await import('/js/keymap.js');
  const out = {};

  bus.bus.handle('t.ok', p => p.x + 1);
  out.cmdResult = bus.bus.cmd('t.ok', {x: 1});
  try { bus.bus.handle('t.ok', () => 0); out.dupHandler = false; } catch { out.dupHandler = true; }
  const toasts = []; bus.bus.on('toast', t => toasts.push(t.text));
  bus.bus.handle('t.boom', () => { throw new Error('x'); });
  bus.bus.cmd('t.boom'); bus.bus.cmd('t.unknown');
  out.failures = [bus.errors.length, toasts.length];
  bus.errors.length = 0;

  const snap = state.snapshot();
  out.frozen = Object.isFrozen(snap) && Object.isFrozen(snap.workspaces.tabs.t1) && Object.isFrozen(snap.registry.p1);
  try { state.register('registry', {}); out.singleWriter = false; } catch { out.singleWriter = true; }

  const run = (start, name, event) => reg.handle({...reg.newSession(0), ...start}, name, event);
  const st = (s, n, e) => run(s, n, e).state;
  out.table = {
    promptFromIdle: st({state: 'idle'}, 'UserPromptSubmit'),
    promptFromWaiting: st({state: 'waiting'}, 'UserPromptSubmit'),
    permFromWorking: st({state: 'working'}, 'PermissionRequest'),
    toolDoneFromPermission: st({state: 'permission'}, 'PostToolUse'),
    toolDoneFromWorking: st({state: 'working'}, 'PostToolUse'),
    toolDoneFromWaiting: st({state: 'waiting'}, 'PostToolUse'),
    stop: st({state: 'working'}, 'Stop'),
    stopBackground: st({state: 'working'}, 'Stop', {background_tasks: [1]}),
    stopFromWaiting: st({state: 'waiting'}, 'Stop'),
    latePermissionPrompt: st({state: 'working', sawPermissionRequest: true}, 'Notification', {notification_type: 'permission_prompt'}),
    permissionPrompt: st({state: 'working'}, 'Notification', {notification_type: 'permission_prompt'}),
    idlePromptIdle: st({state: 'idle'}, 'Notification', {notification_type: 'idle_prompt'}),
    idlePromptWorking: st({state: 'working'}, 'Notification', {notification_type: 'idle_prompt'}),
    subagentStop: st({state: 'working'}, 'Stop', {agent_id: 'a'}),
    subagentPostTool: st({state: 'permission', permissionAgent: null}, 'PostToolUse', {agent_id: 'a'}),
    endClear: st({state: 'working'}, 'SessionEnd', {reason: 'clear'}),
    endOther: st({state: 'permission'}, 'SessionEnd', {reason: 'logout'}),
    endFromWaiting: st({state: 'waiting'}, 'SessionEnd', {reason: 'clear'}),
  };
  out.failed = [run({state: 'working'}, 'StopFailure').failed, run({state: 'waiting', failed: true}, 'UserPromptSubmit').failed];

  out.schema = {
    ok: schema.checkRows([{id: 'a', chords: ['Cmd+D'], when: 'terminal', group: 'g', text: 't', cmd: 'c'}]).length,
    dup: schema.checkRows([
      {id: 'a', chords: ['Cmd+D'], when: 'any', group: 'g', text: 't', cmd: 'c'},
      {id: 'b', chords: ['Cmd+D'], when: 'viewer', group: 'g', text: 't', cmd: 'c'}]).length,
    otherArea: schema.checkRows([
      {id: 'a', chords: ['Cmd+D'], when: 'terminal', group: 'g', text: 't', cmd: 'c'},
      {id: 'b', chords: ['Cmd+D'], when: 'viewer', group: 'g', text: 't', cmd: 'c'}]).length,
    shellInput: schema.checkRows([{id: 'a', chords: ['Ctrl+C'], when: 'any', group: 'g', text: 't', cmd: 'c'}]).length,
    badFallback: schema.checkRows([{id: 'a', chords: ['Cmd+T'], alt: ['Alt+T'], when: 'any', group: 'g', text: 't', cmd: 'c'}]).length > 0,
  };

  window.pings = [];
  bus.bus.handle('ping', p => pings.push(p));
  keymap.installKeys([
    {id: 'p1', chords: ['Cmd+Y'], when: 'terminal', group: 'g', text: 't', cmd: 'ping', payload: 'term'},
    {id: 'p2', chords: ['Cmd+Y'], when: 'viewer', group: 'g', text: 't', cmd: 'ping', payload: 'view'},
    {id: 'p3', chords: ['Cmd+J'], alt: ['Ctrl+Alt+J'], when: 'any', group: 'g', text: 't', cmd: 'ping', payload: 'j'},
  ], {focus: () => 'terminal'});
  return out;
}"""


def contracts(base):
    with browser_page(base) as (pg, errors, requests):
        pg.wait_for_selector("html[data-ready=true]")
        check("boot: zero console errors", not errors, str(errors))
        check(
            "boot: every request is same-origin",
            all(u.startswith((base, "data:")) for u in requests),
            str(requests),
        )
        snap_keys = pg.evaluate("Object.keys(__tarn.snapshot())")
        check(
            "__tarn.snapshot has all parts",
            {"workspaces", "registry", "config"} <= set(snap_keys),
            str(snap_keys),
        )
        check(
            "seed keeps ids t1 and w1, t1 is waiting and not seen",
            pg.evaluate(
                "(() => { const s = __tarn.snapshot(); return s.workspaces.tabs.t1 && s.workspaces.wss[0].id === 'w1' && s.registry.p1.state === 'waiting' && s.registry.p1.seen === false })()"
            ),
        )
        check(
            "terminal pane readable through __tarn.screen",
            "Claude Code" in pg.evaluate("__tarn.screen('p1')"),
        )

        r = pg.evaluate(CONTRACT)
        check("bus: command returns handler result", r["cmdResult"] == 2)
        check("bus: second handler for a command is refused", r["dupHandler"])
        check(
            "bus: failing and unknown commands warn and toast, never throw",
            r["failures"] == [2, 2],
            str(r["failures"]),
        )
        check("state: snapshots are frozen", r["frozen"])
        check("state: a part has one writer", r["singleWriter"])
        t = r["table"]
        expected = {
            "promptFromIdle": "working",
            "promptFromWaiting": "working",
            "permFromWorking": "permission",
            "toolDoneFromPermission": "working",
            "toolDoneFromWorking": "working",
            "toolDoneFromWaiting": "working",
            "stop": "waiting",
            "stopBackground": "working",
            "stopFromWaiting": "waiting",
            "latePermissionPrompt": "working",
            "permissionPrompt": "permission",
            "idlePromptIdle": "waiting",
            "idlePromptWorking": "working",
            "subagentStop": "working",
            "subagentPostTool": "permission",
            "endClear": "waiting",
            "endOther": "idle",
            "endFromWaiting": "waiting",
        }
        check(
            "registry: transition table of spec section 8",
            t == expected,
            str({k: v for k, v in t.items() if expected[k] != v}),
        )
        check(
            "registry: failed set by StopFailure, cleared by UserPromptSubmit",
            r["failed"] == [True, False],
            str(r["failed"]),
        )
        s = r["schema"]
        check(
            "keys schema: valid row passes, same chord in overlapping focus fails",
            s["ok"] == 0 and s["dup"] > 0 and s["otherArea"] == 0,
        )
        check(
            "keys schema: shell input chord and non Ctrl+Alt fallback fail",
            s["shellInput"] > 0 and s["badFallback"],
        )

        def press(key, code, **mods):
            pg.evaluate("pings.length = 0")
            pg.evaluate(
                "([key, code, mods]) => document.body.dispatchEvent(new KeyboardEvent('keydown', {key, code, bubbles: true, cancelable: true, ...mods}))",
                [key, code, mods],
            )
            return pg.evaluate("pings.slice()")

        check(
            "keymap: Cmd+Y resolves by focus area",
            press("y", "KeyY", metaKey=True) == ["term"],
        )
        check(
            "keymap: Cyrillic layout still matches by code",
            press("н", "KeyY", metaKey=True) == ["term"],
        )
        check(
            "keymap: fallback chord Ctrl+Alt+J with Option symbol",
            press("∆", "KeyJ", ctrlKey=True, altKey=True) == ["j"],
        )
        check(
            "keymap: plain letters are left to the terminal", press("k", "KeyK") == []
        )

        pg.evaluate("__tarn.clock.freeze()")
        order = pg.evaluate(
            """async () => { const {clock} = await import('/js/clock.js'); const hits = [];
              clock.after(200, () => hits.push('b')); clock.after(100, () => { hits.push('a'); clock.after(50, () => hits.push('c')); });
              __tarn.clock.advance(120); const early = hits.join(''); __tarn.clock.advance(200); return [early, hits.join('')]; }"""
        )
        check(
            "clock: advance fires timers in order, including new ones",
            order == ["a", "acb"],
            str(order),
        )

        pg.evaluate(
            "window.cfg = []; import('/js/bus.js').then(m => m.bus.on('config:changed', e => cfg.push(e.key + '=' + e.value)))"
        )
        pg.evaluate(
            "import('/js/bus.js').then(m => { m.bus.cmd('config.set', {key: 'font-size', value: 16}); m.bus.cmd('config.set', {key: 'font-size', value: 99}); })"
        )
        cfg = pg.evaluate(
            "[cfg, __tarn.snapshot().config['font-size'], __tarn.errors.length]"
        )
        check(
            "config: valid set emits and stores, invalid is refused with an error",
            cfg == [["font-size=16"], 16, 1],
            str(cfg),
        )
        pg.reload()
        pg.wait_for_selector("html[data-ready=true]")
        check(
            "config: value survives reload",
            pg.evaluate("__tarn.snapshot().config['font-size']") == 16,
        )
        pg.evaluate("import('/js/bus.js').then(m => m.bus.cmd('config.reset'))")
        check(
            "config: reset restores defaults",
            pg.evaluate("__tarn.snapshot().config['font-size']") == 13,
        )


with server() as base:
    spike_basics(base)
    spike_idle(base)
    spike_dpr(base)
    contracts(base)
check.exit()
