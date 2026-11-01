"""Checks paste destinations and undo against the app's actual viewer bundle."""

from pathlib import Path

from playwright.sync_api import sync_playwright

BUNDLE = Path(__file__).resolve().parent.parent / "macos/Sources/Features/Tarn/Viewer"


def main() -> None:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        page = browser.new_page()
        html = (BUNDLE / "tarn-viewer.html").read_text()
        page.set_content(
            html.replace('http-equiv="Content-Security-Policy"', 'data-csp="off"')
        )
        page.evaluate(
            "window.messages=[];window.webkit={messageHandlers:{tarn:{postMessage:m=>messages.push(m)}}}"
        )
        page.add_script_tag(path=str(BUNDLE / "tarn-viewer.js"))
        page.evaluate("""() => {
          tarn.setChrome({tabs:[{path:'/a.md',name:'a.md'}],active:0,
            tree:{visible:false,rows:[]},dark:false,conflicts:[]});
          tarn.setDoc({path:'/a.md',rev:1,kind:'md',text:'# Heading\\n\\n- [ ] Task',dir:'/'});
          tarn.focusContent();
        }""")
        page.locator('article input[type="checkbox"]').focus()
        page.evaluate("tarn.paste('\\nnew text', '/a.md')")
        assert (
            page.locator(".cm-content").inner_text()
            == "# Heading\n\n- [ ] Task\nnew text"
        )
        page.evaluate("tarn.flush()")
        assert (
            page.evaluate("messages.filter(m=>m.t==='edit').at(-1).text")
            == "# Heading\n\n- [ ] Task\nnew text"
        )
        page.keyboard.press("ControlOrMeta+z")
        assert page.locator(".cm-content").inner_text() == "# Heading\n\n- [ ] Task"
        print("rendered paste, checkbox focus, unsaved edit and undo: PASS")

        page.evaluate("tarn.paste(' end', '/a.md')")
        assert page.locator(".cm-content").inner_text().endswith("Task end")
        before = page.locator(".cm-content").inner_text()
        page.evaluate("tarn.paste('wrong file', '/other.md')")
        assert page.locator(".cm-content").inner_text() == before
        print("source caret and stale file refusal: PASS")

        for source in (False, True):
            if not source:
                page.evaluate("tarn.cmd('mode')")
            else:
                page.evaluate("tarn.find('hide');tarn.cmd('mode')")
            page.evaluate("tarn.find('open')")
            field = page.get_by_role("textbox", name="Search", exact=True)
            field.fill("old")
            field.press("ControlOrMeta+a")
            page.evaluate("tarn.paste('new', '/a.md')")
            assert field.input_value() == "new"
            assert bool(page.locator(".cm-content").count()) == source
        print("find paste in rendered and source modes: PASS")
        browser.close()


if __name__ == "__main__":
    main()
