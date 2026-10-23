"""Checks the hook invariant of .claude/CLAUDE.md: for any input hook.sh exits 0 within
100 ms and prints nothing, also when the app socket accepts and never reads.

Run: python3 -I plugin/test/hook_test.py
"""

import os
import socket
import subprocess
import sys
import tempfile
import time

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "hooks", "hook.sh")
LIMIT = 0.1


def run(home: str, surface: str | None, payload: bytes) -> tuple[float, int, bytes]:
    env = {"HOME": home, "PATH": "/usr/bin:/bin"}
    if surface is not None:
        env["TARN_SURFACE"] = surface
    start = time.monotonic()
    done = subprocess.run(["sh", HOOK], input=payload, env=env, capture_output=True)
    return time.monotonic() - start, done.returncode, done.stdout + done.stderr


def main() -> int:
    failures = []
    # A short path: a unix socket path is limited to 104 bytes.
    home = tempfile.mkdtemp(dir="/tmp", prefix="th.")
    folder = os.path.join(home, "Library", "Application Support", "tarn")
    os.makedirs(folder)

    cases = [
        ("no surface", None, b'{"hook_event_name":"Stop"}'),
        ("no app", "x", b'{"hook_event_name":"Stop"}'),
    ]
    for name, surface, payload in cases:
        elapsed, code, output = run(home, surface, payload)
        if elapsed > LIMIT or code != 0 or output:
            failures.append(f"{name}: {elapsed * 1000:.0f} ms, exit {code}, output {output!r}")

    # A socket that accepts and never reads, as a hung app does.
    server = socket.socket(socket.AF_UNIX)
    server.bind(os.path.join(folder, "tarn.sock"))
    server.listen(8)
    for name, payload in [("hung app", b'{"hook_event_name":"Stop"}'), ("hung app, garbage", b"\x00not json\n\n")]:
        elapsed, code, output = run(home, "x", payload)
        if elapsed > LIMIT or code != 0 or output:
            failures.append(f"{name}: {elapsed * 1000:.0f} ms, exit {code}, output {output!r}")
    server.close()

    for failure in failures:
        print("FAIL", failure)
    print("ok" if not failures else f"{len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
