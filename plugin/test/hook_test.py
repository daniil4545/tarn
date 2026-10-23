"""Checks the hook invariant of .claude/CLAUDE.md: for any input hook.sh exits 0 within
100 ms and prints nothing, also when the app socket accepts and never reads.

Run: python3 -I plugin/test/hook_test.py
"""

import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOOK = Path(__file__).resolve().parent.parent / "hooks" / "hook.sh"
LIMIT = 0.1
STOP = b'{"hook_event_name":"Stop"}'


def run(home: Path, surface: str | None, payload: bytes) -> str | None:
    """Runs the hook once and describes the failure, or returns None."""
    env = {"HOME": str(home), "PATH": "/usr/bin:/bin"}
    if surface is not None:
        env["TARN_SURFACE"] = surface
    start = time.monotonic()
    # Fixed arguments: our own script under /bin/sh, no user input.
    done = subprocess.run(  # noqa: S603
        ["/bin/sh", str(HOOK)], input=payload, env=env, capture_output=True, check=False
    )
    elapsed = time.monotonic() - start
    output = done.stdout + done.stderr
    if elapsed > LIMIT or done.returncode != 0 or output:
        return f"{elapsed * 1000:.0f} ms, exit {done.returncode}, output {output!r}"
    return None


def main() -> int:
    # A short path: a unix socket path is limited to 104 bytes.
    home = Path(tempfile.mkdtemp(dir="/tmp", prefix="th."))
    folder = home / "Library" / "Application Support" / "tarn"
    folder.mkdir(parents=True)
    failures: list[str] = []
    try:
        for name, surface in [("no surface", None), ("no app", "x")]:
            if failure := run(home, surface, STOP):
                failures.append(f"{name}: {failure}")

        # A socket that accepts and never reads, as a hung app does.
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(folder / "tarn.sock"))
            server.listen(8)
            for name, payload in [("hung app", STOP), ("hung app, garbage", b"\x00not json\n\n")]:
                if failure := run(home, "x", payload):
                    failures.append(f"{name}: {failure}")
    finally:
        shutil.rmtree(home)

    for failure in failures:
        sys.stdout.write(f"FAIL {failure}\n")
    sys.stdout.write("ok\n" if not failures else f"{len(failures)} failed\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
