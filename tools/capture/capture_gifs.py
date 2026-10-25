"""Short GIFs of the demo for the README: scripted stories recorded as video, then ffmpeg palettegen.

Run: nice -n 10 uv run --with playwright python -I tools/capture/capture_gifs.py [name ...]
Writes docs/assets/gifs/<name>.gif and <name>.mp4. Needs ffmpeg.
"""

import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from capture_lib import TAB, focus, open_page, run, server, show_pane, sync_playwright, until  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parents[2] / "docs" / "assets" / "gifs"
SPEC = "/Users/you/code/tarn/docs/spec.md"
FPS, WIDTH = 12, 960


def glide(pg, x, y, steps=25):
    pg.mouse.move(x, y, steps=steps)


def center(pg, selector):
    b = pg.locator(selector).first.bounding_box()
    return b["x"] + b["width"] / 2, b["y"] + b["height"] / 2


def story_permission(pg):
    """An agent session: working, permission, answered from the card."""
    show_pane(pg, "p6")
    focus(pg, "p6")
    until(pg, "p6", "%")
    time.sleep(0.3)
    run(pg, "claude", delay=40)
    until(pg, "p6", "Type a request")
    time.sleep(0.2)
    run(pg, "update the spec", delay=25)
    pg.wait_for_function("__tarn.snapshot().registry.p6?.state === 'permission'")
    time.sleep(0.3)
    glide(pg, *center(pg, f"{TAB}[data-tabid='t6']"))
    pg.wait_for_selector("#tabcard [data-answer]")
    time.sleep(0.8)
    glide(pg, *center(pg, "#tabcard [data-allow='true']"), steps=12)
    time.sleep(0.4)
    pg.click("#tabcard [data-answer][data-allow='true']")
    pg.wait_for_function("__tarn.snapshot().registry.p6?.state === 'waiting'", timeout=15000)
    time.sleep(1.0)


def story_viewer(pg):
    """A click on a path opens the viewer; edit the file and save."""
    pos = pg.evaluate("__tarn.linkAt('p1', 'docs/spec.md')")
    glide(pg, 700, 500)
    time.sleep(0.5)
    glide(pg, pos["x"], pos["y"])
    time.sleep(0.5)
    pg.mouse.click(pos["x"], pos["y"])
    pg.wait_for_selector('.leaf[data-kind="viewer"] iframe')
    v = pg.frame_locator('.leaf[data-kind="viewer"] iframe')
    v.locator(".mm svg").first.wait_for()
    time.sleep(1.6)
    tab = v.locator(".ftab.on").bounding_box()
    glide(pg, tab["x"] + 60, tab["y"] + 15)
    v.locator(".ftab.on").click()
    pg.keyboard.press("Meta+e")
    v.locator(".cm-content").wait_for()
    time.sleep(0.5)
    v.locator(".cm-content").click()
    pg.keyboard.press("Meta+ArrowDown")
    pg.keyboard.type("\n- [ ] ship the demo GIFs", delay=60)
    time.sleep(0.6)
    pg.keyboard.press("Meta+s")
    time.sleep(1.2)
    pg.keyboard.press("Meta+e")
    time.sleep(1.0)


def story_drag(pg):
    """Drag a viewer to the left edge zone."""
    pg.evaluate("p => window.bus.cmd('viewer.open', {path: p, pane: 'p1'})", SPEC)
    pg.wait_for_selector('.leaf[data-kind="viewer"] .grip')
    time.sleep(1.5)
    gx, gy = center(pg, '.leaf[data-kind="viewer"] .grip')
    glide(pg, gx, gy)
    time.sleep(0.4)
    pg.mouse.down()
    area = pg.locator("#ws").bounding_box()
    glide(pg, gx - 200, gy + 100, steps=15)
    glide(pg, area["x"] + 10, area["y"] + area["height"] / 2, steps=25)
    pg.wait_for_selector("#ws > .drop")
    time.sleep(1.0)
    pg.mouse.up()
    time.sleep(1.5)


def story_split(pg):
    """Split right, then drag the new terminal under the first one: the split turns horizontal."""
    focus(pg, "p1")
    time.sleep(0.8)
    pg.keyboard.press("Meta+d")
    terms = pg.locator('.leaf[data-kind="term"]')
    terms.nth(1).wait_for()
    time.sleep(1.2)
    gx, gy = center(pg, '.leaf[data-kind="term"] >> nth=1 >> .grip')
    glide(pg, gx, gy)
    time.sleep(0.6)
    pg.mouse.down()
    first = terms.nth(0).bounding_box()
    glide(pg, gx - 150, gy + 120, steps=15)
    glide(pg, first["x"] + first["width"] / 2, first["y"] + first["height"] * 0.85, steps=25)
    pg.wait_for_selector("#ws > .drop")
    time.sleep(1.0)
    pg.mouse.up()
    time.sleep(1.5)


STORIES = {
    "agent-permission": story_permission,
    "viewer-edit": story_viewer,
    "viewer-drag": story_drag,
    "terminal-split": story_split,
}


def to_gif(webm, start, name):
    mp4 = OUT / f"{name}.mp4"
    gif = OUT / f"{name}.gif"
    vf = f"fps={FPS},scale={WIDTH}:-1:flags=lanczos"
    base = ["nice", "-n", "10", "ffmpeg", "-y", "-loglevel", "error", "-ss", f"{start:.2f}", "-t", "12", "-i", str(webm)]
    subprocess.run(base + ["-vf", f"scale={WIDTH}:-2", "-an", "-pix_fmt", "yuv420p", "-crf", "30", str(mp4)], check=True)
    pal = webm.with_suffix(".png")
    subprocess.run(base + ["-vf", f"{vf},palettegen=max_colors=96", str(pal)], check=True)
    subprocess.run(base + ["-i", str(pal), "-lavfi", f"{vf} [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=4", str(gif)], check=True)
    print(name, f"{gif.stat().st_size / 1024:.0f} KB gif", f"{mp4.stat().st_size / 1024:.0f} KB mp4")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    want = sys.argv[1:] or list(STORIES)
    with server() as base, sync_playwright() as p:
        for name, story in STORIES.items():
            if name not in want:
                continue
            tmp = pathlib.Path(tempfile.mkdtemp())
            t0 = time.time()
            browser, ctx, pg = open_page(p, base, dpr=1, video_dir=tmp)
            time.sleep(1.0)
            start = time.time() - t0
            story(pg)
            length = time.time() - t0 - start
            video = pg.video
            ctx.close()
            browser.close()
            print(name, f"story {length:.1f}s")
            to_gif(pathlib.Path(video.path()), start, name)
            shutil.rmtree(tmp, ignore_errors=True)
