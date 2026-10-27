"""Checks the `tarn` CLI against a fake control socket (docs/spec.md 2.2, 11).

Run: python3 -I cli/test/cli_test.py
"""

import json
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

CLI = Path(__file__).resolve().parent.parent / "tarn"
SURFACE = "5A3C9D6E-1111-2222-3333-444455556666"
OK = b'{"ok":true,"version":1}\n'


class Fake:
    """A one-shot unix socket server: keeps each request line, answers with `answer`."""

    def __init__(self, path: Path, answer: bytes, delay: float = 0.0) -> None:
        self.requests: list[dict] = []
        self.answer = answer
        self.delay = delay
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(str(path))
        self.server.listen(4)
        self.server.settimeout(10)
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self) -> None:
        try:
            while True:
                client, _ = self.server.accept()
                with client:
                    line = b""
                    while not line.endswith(b"\n"):
                        chunk = client.recv(65536)
                        if not chunk:
                            break
                        line += chunk
                    self.requests.append(json.loads(line) if line.strip() else {})
                    if self.delay:
                        threading.Event().wait(self.delay)
                    client.sendall(self.answer)
        except OSError:
            return

    def close(self) -> None:
        self.server.close()


def run(
    home: Path, args: list[str], surface: str | None = SURFACE, **extra: str
) -> tuple[int, str, str]:
    env = {"HOME": str(home), "PATH": "/usr/bin:/bin", "PWD": str(home), **extra}
    if surface is not None:
        env["TARN_SURFACE"] = surface
    done = subprocess.run(
        ["/bin/sh", str(CLI), *args],
        env=env,
        capture_output=True,
        text=True,
        check=False,
        cwd=home,
    )
    return done.returncode, done.stdout, done.stderr


def reply(**fields: object) -> bytes:
    fields.setdefault("version", 1)
    fields["ok"] = "error" not in fields
    return json.dumps(fields, sort_keys=True, separators=(",", ":")).encode() + b"\n"


def with_server(home: Path, answer: bytes, args: list[str], **kw: object):
    sock = home / "Library" / "Application Support" / "tarn" / "tarn.sock"
    server = Fake(sock, answer, delay=float(kw.pop("delay", 0)))
    try:
        result = run(home, args, **kw)  # type: ignore[arg-type]
    finally:
        server.close()
        sock.unlink()
    return result, server.requests


def main() -> int:
    home = Path(tempfile.mkdtemp(dir="/tmp", prefix="tc."))
    (home / "Library" / "Application Support" / "tarn").mkdir(parents=True)
    sock = home / "Library" / "Application Support" / "tarn" / "tarn.sock"
    failures: list[str] = []

    def check(name: str, ok: bool, detail: object = "") -> None:
        if not ok:
            failures.append(f"{name}: {detail!r}")

    try:
        # open: absolute stays, relative joins PWD, text is JSON-escaped.
        (code, out, err), req = with_server(home, OK, ["open", "/a/b.md"])
        check("open abs", code == 0 and out == "" and err == "", (code, out, err))
        check(
            "open abs request",
            req
            == [{"version": 1, "cmd": "open", "surface": SURFACE, "path": "/a/b.md"}],
            req,
        )
        (code, _, _), req = with_server(home, OK, ["open", "docs/x.md"])
        check("open rel", code == 0 and req[0]["path"] == f"{home}/docs/x.md", req)
        weird = 'a "q" \\ b\ttab\nnl é.md'
        (code, _, _), req = with_server(home, OK, ["open", "/p/" + weird])
        check("open escaping", code == 0 and req[0]["path"] == "/p/" + weird, req)

        # notify: words joined, escaped, control bytes dropped.
        (code, _, _), req = with_server(
            home, OK, ["notify", "done:", 'say "hi"\\n', "\x01x"]
        )
        check(
            "notify words",
            code == 0
            and req[0]["text"] == 'done: say "hi"\\n x'
            and req[0]["cmd"] == "notify",
            req,
        )

        # ls: names the caller, text rows are decoded, --json prints the reply line.
        rows = 'PANE  TITLE\n1     a"b\n'
        (code, out, _), req = with_server(home, reply(text=rows), ["ls"])
        check("ls text", code == 0 and out == rows, (code, out))
        check(
            "ls request",
            req == [{"version": 1, "cmd": "ls", "surface": SURFACE, "json": False}],
            req,
        )
        line = reply(panes=[{"pane": SURFACE, "title": "x\\ny"}])
        (code, out, _), req = with_server(home, line, ["ls", "--json"])
        check(
            "ls json",
            code == 0 and out.encode() == line and req[0]["json"] is True,
            out,
        )
        (code, out, _), _ = with_server(home, reply(text=""), ["ls"])
        check("ls empty", code == 0 and out == "", out)

        # new: options, the command as argv, the pane id printed.
        (code, out, err), req = with_server(
            home, reply(pane=SURFACE), ["new", "--", "sh", "-c", 'a "b" && c']
        )
        check("new prints the pane", (code, out, err) == (0, SURFACE + "\n", ""), out)
        check(
            "new request",
            req
            == [
                {
                    "version": 1,
                    "cmd": "new",
                    "surface": SURFACE,
                    "right": False,
                    "argv": ["sh", "-c", 'a "b" && c'],
                }
            ],
            req,
        )
        (code, _, _), req = with_server(
            home, reply(pane=SURFACE), ["new", "--right", "--cwd", "w", "--", "ls"]
        )
        check(
            "new right cwd",
            code == 0 and req[0]["right"] is True and req[0]["cwd"] == f"{home}/w",
            req,
        )
        # spec: agent-cli B2 - a newline or a carriage return is refused before the socket.
        for arg in ["a\nb", "a\rb"]:
            code, out, err = run(home, ["new", "--", "echo", arg])
            check(
                f"new one line {arg!r}",
                (code, out, err) == (1, "", "tarn: command must be one line\n"),
                err,
            )

        # run: the options and the command line rule of new, cmd "run" (agent-cli 4.5).
        (code, out, err), req = with_server(
            home, reply(pane=SURFACE), ["run", "--right", "--cwd", "w", "--", "echo", "hi"]
        )
        check("run prints the pane", (code, out, err) == (0, SURFACE + "\n", ""), out)
        check(
            "run request",
            req
            == [
                {
                    "version": 1,
                    "cmd": "run",
                    "surface": SURFACE,
                    "right": True,
                    "cwd": f"{home}/w",
                    "argv": ["echo", "hi"],
                }
            ],
            req,
        )
        for arg in ["a\nb", "a\rb"]:
            code, out, err = run(home, ["run", "--", "echo", arg])
            check(
                f"run one line {arg!r}",
                (code, out, err) == (1, "", "tarn: command must be one line\n"),
                err,
            )

        # error replies: decoded text, stderr only, exit 1.
        err_text = 'no such file: /x "y" \\ z\nline'
        (code, out, err), _ = with_server(home, reply(error=err_text), ["open", "/x"])
        check(
            "error reply",
            (code, out, err) == (1, "", f"tarn: {err_text}\n"),
            (code, out, err),
        )
        (code, out, err), _ = with_server(home, reply(error="é\x01"), ["notify", "x"])
        check("error unicode", code == 1 and err == "tarn: é\x01\n", err)
        # spec: agent-cli B5 - the reply's code is the exit code.
        no_pane = reply(error='no pane matched: "code":5', code=4)
        (code, out, err), _ = with_server(home, no_pane, ["ls"])
        check(
            "error code",
            (code, out, err) == (4, "", 'tarn: no pane matched: "code":5\n'),
            (code, out, err),
        )

        # wait: the text line, --json, the timeout request field, the app's exit codes (6, 9, 4).
        done = reply(
            text="error  exit 2  1.5s", state="error", exit_code=2, duration_ms=1500
        )
        (code, out, err), req = with_server(
            home, done, ["wait", SURFACE, "--timeout", "30"]
        )
        check("wait text", (code, out, err) == (0, "error  exit 2  1.5s\n", ""), out)
        check(
            "wait request",
            req
            == [
                {
                    "version": 1,
                    "cmd": "wait",
                    "surface": SURFACE,
                    "pane": SURFACE,
                    "timeout": 30,
                }
            ],
            req,
        )
        (code, out, _), _ = with_server(home, done, ["wait", "--json", SURFACE])
        check("wait json", code == 0 and json.loads(out)["exit_code"] == 2, out)
        for text, status in [
            ("exit code unknown", 6),
            ("no shell integration", 6),
            ("timeout", 9),
        ]:
            (code, out, err), _ = with_server(
                home, reply(error=text, code=status), ["wait", SURFACE]
            )
            check(
                f"wait {text}", (code, out, err) == (status, "", f"tarn: {text}\n"), err
            )
        # the wait outlives TARN_TIMEOUT: the answer comes later than the 1 s bound.
        (code, out, _), _ = with_server(
            home, done, ["wait", SURFACE], delay=2, TARN_TIMEOUT="1"
        )
        check("wait ignores TARN_TIMEOUT", code == 0 and out.startswith("error"), out)
        # --timeout takes ^[0-9]+(\.[0-9]+)?$ only; a bad one sends nothing.
        for bad in [
            ".5",
            "5.",
            ".",
            "-1",
            "1e99",
            "",
            "1.2.3",
            "abc",
            "007",
            "00",
            "01.5",
        ]:
            (code, out, err), req = with_server(
                home, done, ["wait", SURFACE, "--timeout", bad]
            )
            check(
                f"bad timeout {bad!r}",
                (code, out, err) == (1, "", "tarn: bad timeout\n") and req == [],
                (code, err, req),
            )
        for good in ["0", "0.5", "10", "1.5", "99999999999999999999"]:
            (code, _, _), req = with_server(
                home, done, ["wait", SURFACE, "--timeout", good]
            )
            check(f"timeout {good}", code == 0 and len(req) == 1, (code, req))
        code, out, err = run(home, ["wait", SURFACE], surface=None)
        check("wait without surface", (code, err) == (1, "tarn: not in a tarn tab\n"))

        # read: the text as is, the lines request field, a bad --lines sends nothing.
        screen = reply(text='b\n\t"c" \\ é\n')
        (code, out, err), req = with_server(
            home, screen, ["read", SURFACE, "--lines", "2"]
        )
        check("read text", (code, out, err) == (0, 'b\n\t"c" \\ é\n', ""), out)
        check(
            "read request",
            req
            == [
                {
                    "version": 1,
                    "cmd": "read",
                    "surface": SURFACE,
                    "pane": SURFACE,
                    "lines": 2,
                }
            ],
            req,
        )
        (code, _, _), req = with_server(home, screen, ["read", "--lines", "3", SURFACE])
        check("read lines first", code == 0 and req[0]["lines"] == 3, req)
        (code, _, _), req = with_server(home, screen, ["read", SURFACE])
        check("read default", code == 0 and "lines" not in req[0], req)
        (code, out, _), _ = with_server(home, reply(text=""), ["read", SURFACE])
        check("read empty", (code, out) == (0, ""), out)
        for bad in ["0", "-1", "x", "", "1.5", "007", "1e3"]:
            (code, out, err), req = with_server(
                home, screen, ["read", SURFACE, "--lines", bad]
            )
            check(
                f"bad lines {bad!r}",
                (code, out, err) == (1, "", "tarn: bad lines\n") and req == [],
                (code, err, req),
            )
        (code, out, err), _ = with_server(
            home, reply(error=f"no pane matched: {SURFACE}", code=4), ["read", SURFACE]
        )
        check("read no pane", (code, out) == (4, "") and "no pane matched" in err, err)

        # close: the request, nothing on stdout, exit 4 for a foreign pane.
        (code, out, err), req = with_server(home, OK, ["close", SURFACE])
        check("close", (code, out, err) == (0, "", ""), (code, out, err))
        check(
            "close request",
            req
            == [{"version": 1, "cmd": "close", "surface": SURFACE, "pane": SURFACE}],
            req,
        )
        (code, out, err), _ = with_server(
            home, reply(error=f"no pane matched: {SURFACE}", code=4), ["close", SURFACE]
        )
        check("close no pane", (code, out) == (4, "") and "no pane matched" in err, err)

        # client-side errors.
        for name, args, surface in [
            ("open", ["open", "/x"], None),
            ("notify", ["notify", "x"], None),
            ("ls", ["ls"], None),
            ("new", ["new", "--", "ls"], None),
            ("run", ["run", "--", "ls"], None),
            ("read", ["read", SURFACE], None),
            ("close", ["close", SURFACE], None),
        ]:
            code, out, err = run(home, args, surface=surface)
            check(
                f"{name} without surface",
                (code, out, err) == (1, "", "tarn: not in a tarn tab\n"),
                err,
            )
        code, out, err = run(home, ["ls"])
        check(
            "no socket", (code, out, err) == (1, "", "tarn: tarn is not running\n"), err
        )
        with socket.socket(socket.AF_UNIX) as stale:
            stale.bind(str(sock))
        code, out, err = run(home, ["ls"])
        check(
            "stale socket",
            (code, out, err) == (1, "", "tarn: tarn is not running\n"),
            err,
        )
        sock.unlink()
        (code, out, err), _ = with_server(home, b"", ["ls"])
        check(
            "closed without answer",
            (code, out, err) == (1, "", "tarn: no answer from tarn\n"),
            err,
        )
        (code, out, err), _ = with_server(home, b"garbage\n", ["ls"])
        check(
            "garbage", (code, out, err) == (1, "", "tarn: bad answer from tarn\n"), err
        )
        (code, out, err), _ = with_server(home, OK, ["ls"], delay=4, TARN_TIMEOUT="1")
        check(
            "timeout",
            code == 1 and out == "" and err.startswith("tarn: no answer"),
            (code, err),
        )

        # usage.
        for args in [
            [],
            ["bogus"],
            ["ls", "--bogus"],
            ["open"],
            ["open", "a", "b"],
            ["notify"],
            ["new"],
            ["new", "ls"],
            ["new", "--"],
            ["new", "--tab", "--", "ls"],
            ["new", "--cwd"],
            ["run"],
            ["run", "--"],
            ["run", "--tab", "--", "ls"],
            ["run", "--title", "t", "--", "ls"],
            ["wait"],
            ["wait", "a", "b"],
            ["wait", "a", "--timeout"],
            ["wait", "a", "--bogus"],
            ["read"],
            ["read", "a", "b"],
            ["read", "a", "--lines"],
            ["read", "a", "--bogus"],
            ["close"],
            ["close", "a", "b"],
        ]:
            code, out, err = run(home, args)
            check(
                f"usage {args}",
                (code, out) == (1, "") and err.startswith("tarn: usage"),
                (code, err),
            )
    finally:
        shutil.rmtree(home)

    for failure in failures:
        sys.stdout.write(f"FAIL {failure}\n")
    sys.stdout.write("ok\n" if not failures else f"{len(failures)} failed\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
