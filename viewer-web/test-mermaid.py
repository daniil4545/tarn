"""Renders the five common mermaid diagram kinds with the built bundle, without the app.

Run: uv run --with playwright python -I viewer-web/test-mermaid.py (uses the installed Chrome).
"""
import pathlib
import sys

from playwright.sync_api import sync_playwright

BUNDLE = pathlib.Path(__file__).resolve().parent.parent / "macos/Sources/Features/Tarn/Viewer/tarn-mermaid.js"

DIAGRAMS = {
    "flowchart": "flowchart TD\n  A[Start] --> B{Ok?}\n  B -->|yes| C[Done]\n  B -->|no| A",
    "sequence": "sequenceDiagram\n  Alice->>Bob: Hello\n  Bob-->>Alice: Hi",
    "state": "stateDiagram-v2\n  [*] --> Idle\n  Idle --> Busy: start\n  Busy --> [*]",
    "class": "classDiagram\n  class Animal {\n    +name\n    +eat()\n  }\n  Animal <|-- Dog",
    "er": "erDiagram\n  CUSTOMER ||--o{ ORDER : places\n  ORDER ||--|{ ITEM : contains",
}


def main() -> int:
    failures = []
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome")
        page = browser.new_page()
        page.set_content("<html><body></body></html>")
        page.add_script_tag(path=str(BUNDLE))
        page.evaluate("mermaid.initialize({startOnLoad: false, securityLevel: 'strict', layout: 'dagre'})")
        for name, source in DIAGRAMS.items():
            svg = page.evaluate("([id, src]) => mermaid.render(id, src).then(r => r.svg)", [f"d-{name}", source])
            ok = "<svg" in svg and "Syntax error" not in svg
            print(f"{name}: {'ok' if ok else 'FAIL'} ({len(svg)} bytes)")
            if not ok:
                failures.append(name)
        # The ELK layout is left out on purpose: it must fail with our message, not with a crash.
        error = page.evaluate(
            """async () => {
              try { await mermaid.render('d-elk', '---\\nconfig:\\n  layout: elk\\n---\\nflowchart TD\\n A-->B'); return ''; }
              catch (e) { return String(e); }
            }""")
        print("elk:", error[:120] or "rendered (unexpected)")
        browser.close()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
