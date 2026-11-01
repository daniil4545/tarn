"""Checks paste destinations and undo against the app's actual viewer bundle."""

from pathlib import Path

from playwright.sync_api import sync_playwright

BUNDLE = Path(__file__).resolve().parent.parent / "macos/Sources/Features/Tarn/Viewer"


def main() -> None:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        page = browser.new_page()

        def source() -> str:
            # Empty CodeMirror lines contain a BR; innerText adds layout-dependent breaks.
            return "\n".join(page.locator(".cm-content > .cm-line").all_text_contents())

        html = (BUNDLE / "tarn-viewer.html").read_text()
        page.set_content(
            html.replace('http-equiv="Content-Security-Policy"', 'data-csp="off"')
        )
        page.add_style_tag(path=str(BUNDLE / "tarn-viewer.css"))
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
        actual = source()
        assert actual == "# Heading\n\n- [ ] Task\nnew text", repr(actual)
        page.evaluate("tarn.flush()")
        assert (
            page.evaluate("messages.filter(m=>m.t==='edit').at(-1).text")
            == "# Heading\n\n- [ ] Task\nnew text"
        )
        page.evaluate("tarn.history(false)")
        actual = source()
        assert actual == "# Heading\n\n- [ ] Task", repr(actual)
        page.evaluate("tarn.history(true)")
        assert source().endswith("new text")
        page.keyboard.press("ControlOrMeta+z")
        actual = source()
        assert actual == "# Heading\n\n- [ ] Task", repr(actual)
        print("rendered paste, checkbox focus, unsaved edit, undo and redo: PASS")

        page.evaluate(
            "const b=document.createElement('button');b.id='outside';"
            "document.getElementById('app').append(b);b.focus()"
        )
        before = source()
        page.evaluate("tarn.paste('tree focus', '/a.md')")
        assert source() == before
        page.evaluate("document.getElementById('outside').remove();tarn.focusContent()")
        print("paste with focus outside the content: PASS")

        page.evaluate("tarn.paste(' end', '/a.md')")
        assert source().endswith("Task end")
        before = source()
        page.evaluate("tarn.paste('wrong file', '/other.md')")
        assert source() == before
        print("source caret and stale file refusal: PASS")

        for editing in (False, True):
            if not editing:
                page.evaluate("tarn.cmd('mode')")
            else:
                page.evaluate("tarn.find('hide');tarn.cmd('mode')")
            page.evaluate("tarn.find('open')")
            field = page.get_by_role("textbox", name="Search", exact=True)
            field.fill("old")
            field.press("ControlOrMeta+a")
            page.evaluate("tarn.paste('new', '/a.md')")
            assert field.input_value() == "new"
            assert bool(page.locator(".cm-content").count()) == editing
        print("find paste in rendered and source modes: PASS")
        browser.close()


if __name__ == "__main__":
    main()
