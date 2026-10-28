"""Checks the hook contract of docs/spec.md 2.3.

hook.sh, for any input, exits 0 within 100 ms and prints nothing, also when the app socket
accepts and never reads. permission.sh prints the app's answer, and prints nothing at once
when there is no app or the app closes without an answer.

Run: python3 -I plugin/test/hook_test.py
"""

import contextlib
import json
import os
import select
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HOOKS = Path(__file__).resolve().parent.parent / "hooks"
LIMIT = 0.1
# TARN_HOOK_LIMIT_MS raises the limit of the hung-app cases for a slow machine; default 100 ms.
HUNG_LIMIT = float(os.environ.get("TARN_HOOK_LIMIT_MS", "100")) / 1000
STOP = b'{"hook_event_name":"Stop"}'
ASK = b'{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"make"}}'
ANSWER = b'{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'


def run(
    hook: str, home: Path, surface: str | None, payload: bytes
) -> tuple[float, int, bytes]:
    """Runs a hook once: seconds, exit code, stdout and stderr."""
    env = {"HOME": str(home), "PATH": "/usr/bin:/bin"}
    if surface is not None:
        env["TARN_SURFACE"] = surface
    start = time.monotonic()
    done = subprocess.run(
        ["/bin/sh", str(HOOKS / hook)],
        input=payload,
        env=env,
        capture_output=True,
        check=False,
    )
    return time.monotonic() - start, done.returncode, done.stdout + done.stderr


def silent(
    hook: str, home: Path, surface: str | None, payload: bytes, limit: float = LIMIT
) -> str | None:
    """Describes a run that is slow, fails or prints, or returns None."""
    elapsed, code, output = run(hook, home, surface, payload)
    if elapsed > limit or code != 0 or output:
        return f"{elapsed * 1000:.0f} ms, exit {code}, output {output!r}"
    return None


def read_line(client: socket.socket) -> bytes:
    """Reads up to a newline; a closed connection or the socket timeout ends it early."""
    line = b""
    while not line.endswith(b"\n"):
        chunk = client.recv(65536)
        if not chunk:
            break
        line += chunk
    return line


def serve(server: socket.socket, answer: bytes, received: list[bytes]) -> None:
    """Accepts one hook, keeps its line, writes `answer` later and closes."""
    client, _ = server.accept()
    with client:
        client.settimeout(3)
        received.append(read_line(client))
        # The user answers later than any idle timeout of nc would allow.
        time.sleep(1.5)
        # A hook gone early is the failure the caller reports.
        with contextlib.suppress(BrokenPipeError):
            client.sendall(answer)


def check_answer(socket_path: Path, home: Path, answer: bytes) -> str | None:
    """permission.sh waits for the app and prints exactly what it answers."""
    received: list[bytes] = []
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(socket_path))
        server.listen(1)
        server.settimeout(3)
        thread = threading.Thread(target=serve, args=(server, answer, received))
        thread.start()
        _, code, output = run("permission.sh", home, "x", ASK)
        thread.join(timeout=5)
    socket_path.unlink()
    if not received or not received[0]:
        return f"exit {code}, output {output!r}, nothing sent"
    message = json.loads(received[0])
    if (
        code != 0
        or output != answer
        or message["reply"] is not True
        or message["event"] != json.loads(ASK)
    ):
        return f"exit {code}, output {output!r}, sent {received[0]!r}"
    return None


def check_stop(socket_path: Path, home: Path) -> str | None:
    """Stopping permission.sh, as Claude Code does on Esc, also stops its sender."""
    env = {"HOME": str(home), "PATH": "/usr/bin:/bin", "TARN_SURFACE": "x"}
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(socket_path))
        server.listen(1)
        server.settimeout(3)
        hook = subprocess.Popen(
            ["/bin/sh", str(HOOKS / "permission.sh")],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            env=env,
        )
        hook.stdin.write(ASK)
        hook.stdin.close()
        client, _ = server.accept()
        with client:
            client.settimeout(3)
            read_line(client)
            hook.terminate()
            code = hook.wait(timeout=3)
            # A sender left behind would print this answer into the dead hook's output.
            with contextlib.suppress(BrokenPipeError):
                client.sendall(ANSWER)
        late = hook.stdout.read()
        hook.stdout.close()
    socket_path.unlink()
    if code != 0 or late:
        return f"exit {code}, output after stop {late!r}"
    return None


def check_order(socket_path: Path, home: Path) -> str | None:
    """By the time hook.sh exits, its event is already queued at a live app's socket."""
    names = ["Start", "Pre", "Post", "Stop"]
    received: list[bytes] = []
    try:
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(socket_path))
            server.listen(8)
            server.settimeout(3)
            for name in names:
                payload = json.dumps({"hook_event_name": name}).encode()
                if failure := silent("hook.sh", home, "x", payload):
                    return f"{name}: {failure}"
                if not select.select([server], [], [], 0)[0]:
                    return f"{name}: hook exited before it connected"
                client, _ = server.accept()
                with client:
                    client.settimeout(3)
                    received.append(read_line(client))
    finally:
        socket_path.unlink(missing_ok=True)
    if not all(received):
        return f"received nothing for some event: {received!r}"
    got = [json.loads(line)["event"]["hook_event_name"] for line in received]
    return None if got == names else f"received {got}"


def main() -> int:
    # A short path: a unix socket path is limited to 104 bytes.
    home = Path(tempfile.mkdtemp(dir="/tmp", prefix="th."))
    folder = home / "Library" / "Application Support" / "tarn"
    folder.mkdir(parents=True)
    socket_path = folder / "tarn.sock"
    failures: list[str] = []
    try:
        for hook, payload in [("hook.sh", STOP), ("permission.sh", ASK)]:
            for name, surface in [("no surface", None), ("no app", "x")]:
                if failure := silent(hook, home, surface, payload):
                    failures.append(f"{hook}, {name}: {failure}")

        # A socket file left by a crashed app: nobody listens.
        with socket.socket(socket.AF_UNIX) as stale:
            stale.bind(str(socket_path))
        if failure := silent("permission.sh", home, "x", ASK):
            failures.append(f"permission.sh, stale socket: {failure}")
        socket_path.unlink()

        for name, answer in [("answer", ANSWER), ("closed without answer", b"")]:
            if failure := check_answer(socket_path, home, answer):
                failures.append(f"permission.sh, {name}: {failure}")

        if failure := check_stop(socket_path, home):
            failures.append(f"permission.sh, stopped: {failure}")

        if failure := check_order(socket_path, home):
            failures.append(f"hook.sh, order: {failure}")

        # A socket that accepts and never reads, as a hung app does.
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(socket_path))
            server.listen(8)
            big = (
                b'{"hook_event_name":"PostToolUse","tool_response":"'
                + b"x" * 200_000
                + b'"}'
            )
            cases = [
                ("hung app", STOP),
                ("hung app, garbage", b"\x00not json\n\n"),
                ("hung app, 200 KB", big),
            ]
            for name, payload in cases:
                if failure := silent("hook.sh", home, "x", payload, HUNG_LIMIT):
                    failures.append(f"hook.sh, {name}: {failure}")
    finally:
        shutil.rmtree(home)

    for failure in failures:
        sys.stdout.write(f"FAIL {failure}\n")
    sys.stdout.write("ok\n" if not failures else f"{len(failures)} failed\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
