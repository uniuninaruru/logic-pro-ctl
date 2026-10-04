#!/usr/bin/env python3
"""Serialize cooperating headless jobs; do not bypass Ghidra's own locks."""

import argparse
import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("a command is required after --")
    args.lock.parent.mkdir(parents=True, exist_ok=True)
    with args.lock.open("a+") as lock:
        print(f"Waiting for project lock: {args.lock}", file=sys.stderr, flush=True)
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        print(f"Acquired project lock: pid={os.getpid()}", file=sys.stderr, flush=True)
        child = None
        pending_signal = None

        def forward(signum, _frame):
            nonlocal pending_signal
            if child is None:
                pending_signal = signum
            else:
                try:
                    os.killpg(child.pid, signum)
                except ProcessLookupError:
                    pass

        old_handlers = {s: signal.signal(s, forward) for s in (signal.SIGINT, signal.SIGTERM)}
        try:
            # The command has its own process group. Descendants inherit the lock
            # descriptor so the lock survives an abrupt wrapper exit as well.
            child = subprocess.Popen(command, start_new_session=True, pass_fds=(lock.fileno(),))
            if pending_signal is not None:
                forward(pending_signal, None)
            result = child.wait()
        finally:
            for sig, handler in old_handlers.items():
                signal.signal(sig, handler)
        return result if result >= 0 else 128 - result


if __name__ == "__main__":
    sys.exit(main())
