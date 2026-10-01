#!/usr/bin/env python3
"""Exercise the built CLI against an isolated fake daemon; no Logic events.

Usage:
    python3 Tests/integration/test_cli_backend_compat.py .build/debug/logicctl

The daemon listens at a short, private /tmp Unix socket. LOGICD_PATH points
to a nonexistent file, so a failed test can never start the real daemon.
Both subprocess execution and socket operations have bounded timeouts.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from collections.abc import Callable
from typing import Any


CLI_BINARY: Path
Request = dict[str, Any]
Responder = Callable[[Request], dict[str, Any]]


def response(request: Request, **fields: Any) -> dict[str, Any]:
    """A response in the legacy format; newer fields are added deliberately."""
    return {
        "id": request["id"],
        "command": request["command"],
        "ok": True,
        "verified": False,
        **fields,
    }


class FakeDaemon:
    def __init__(self, responder: Responder):
        self.responder = responder
        self.requests: list[Request] = []
        self.connection_count = 0
        self.errors: list[BaseException] = []
        self._stop = threading.Event()
        self._directory = tempfile.TemporaryDirectory(prefix="lctl-", dir="/tmp")
        self.path = str(Path(self._directory.name) / "d.sock")
        self._listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._listener.bind(self.path)
        os.chmod(self.path, 0o600)
        self._listener.listen(4)
        self._listener.settimeout(0.05)
        self._thread = threading.Thread(target=self._serve, daemon=True)

    def __enter__(self) -> FakeDaemon:
        self._thread.start()
        return self

    def __exit__(self, *_: Any) -> None:
        self._stop.set()
        self._thread.join(timeout=3)
        self._listener.close()
        self._directory.cleanup()
        if self._thread.is_alive():
            raise AssertionError("fake daemon did not stop within its bounded timeout")
        if self.errors:
            raise AssertionError(f"fake daemon failed: {self.errors!r}")

    def _serve(self) -> None:
        try:
            while not self._stop.is_set():
                try:
                    connection, _ = self._listener.accept()
                except socket.timeout:
                    continue
                self.connection_count += 1
                with connection:
                    connection.settimeout(1.5)
                    pending = b""
                    while not self._stop.is_set():
                        chunk = connection.recv(4096)
                        if not chunk:
                            break
                        pending += chunk
                        if len(pending) > 65536:
                            raise AssertionError("unexpected oversized fake-daemon request")
                        while b"\n" in pending:
                            line, pending = pending.split(b"\n", 1)
                            request = json.loads(line)
                            self.requests.append(request)
                            reply = self.responder(request)
                            connection.sendall(json.dumps(reply).encode("utf-8") + b"\n")
        except BaseException as error:
            self.errors.append(error)


class CLIBackendCompatibilityTests(unittest.TestCase):
    def run_cli(self, args: list[str], responder: Responder):
        with FakeDaemon(responder) as daemon:
            environment = os.environ.copy()
            environment["LOGICCTL_SOCKET"] = daemon.path
            environment["LOGICD_PATH"] = str(Path(daemon.path).parent / "no-real-daemon")
            completed = subprocess.run(
                [str(CLI_BINARY), *args],
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=4,
                check=False,
            )
        lines = completed.stdout.splitlines()
        self.assertEqual(len(lines), 1, f"expected one JSON stdout line; {completed!r}")
        output = json.loads(lines[0])
        return completed, output, daemon.requests, daemon.connection_count

    def assert_status_only(self, requests: list[Request]) -> None:
        self.assertEqual(len(requests), 1, requests)
        self.assertEqual(requests[0]["command"], "status")
        self.assertEqual(requests[0]["args"], {})
        self.assertNotIn("backend", requests[0], "capability probe must be legacy-compatible")

    def test_old_or_missing_capability_never_sends_transport_write(self):
        status_fields = [
            {},
            {"result": {}},
            {"result": {"capabilities": {}}},
            {"result": {"capabilities": {"appleevent_transport": False}}},
            {"result": {"capabilities": {"appleevent_transport": "true"}}},
            {"result": {"capabilities": {"appleevent_transport": 1}}},
        ]
        for fields in status_fields:
            with self.subTest(status_fields=fields):
                process, output, requests, _ = self.run_cli(
                    ["transport", "play", "--backend", "appleevent"],
                    lambda request: response(request, **fields),
                )
                self.assertEqual(process.returncode, 1)
                self.assertFalse(output["ok"])
                self.assertFalse(output["verified"])
                self.assertEqual(output["error"], "daemon_upgrade_required")
                self.assertEqual(output["backend"], "appleevent")
                self.assert_status_only(requests)

    def test_failed_capability_status_never_sends_transport_write(self):
        process, output, requests, _ = self.run_cli(
            ["transport", "stop", "--backend", "appleevent"],
            lambda request: response(
                request, ok=False, error="status_failed",
                result={"capabilities": {"appleevent_transport": True}},
            ),
        )
        self.assertEqual(process.returncode, 1)
        self.assertEqual(output["error"], "daemon_upgrade_required")
        self.assert_status_only(requests)

    def test_supported_daemon_receives_exactly_one_explicit_transport_write(self):
        for action in ("play", "stop"):
            with self.subTest(action=action):
                def responder(request: Request):
                    if request["command"] == "status":
                        return response(request, result={"capabilities": {"appleevent_transport": True}})
                    return response(
                        request, backend="appleevent", readback_backend="mcu", verified=True,
                        requested={"playing": action == "play"},
                        observed={"playing": action == "play", "recording": False},
                        result={"sent": True, "appleevent_send_status": 0, "appleevent_reply_error": 0},
                    )

                process, output, requests, connections = self.run_cli(
                    ["transport", action, "--backend", "appleevent", "--json"], responder,
                )
                self.assertEqual(process.returncode, 0)
                self.assertTrue(output["ok"] and output["verified"])
                self.assertEqual(output["backend"], "appleevent")
                self.assertEqual(output["readback_backend"], "mcu")
                self.assertEqual(len(requests), 2)
                self.assert_status_only(requests[:1])
                self.assertEqual(requests[1]["command"], f"transport.{action}")
                self.assertEqual(requests[1]["backend"], "appleevent")
                self.assertEqual(requests[1]["args"], {})
                self.assertNotEqual(requests[0]["id"], requests[1]["id"])
                self.assertEqual(connections, 1, "preflight and write use the same daemon connection")

    def test_backend_mismatch_returns_error_without_retry(self):
        for wrong_backend in ("mcu", None):
            with self.subTest(reply_backend=wrong_backend):
                def responder(request: Request):
                    if request["command"] == "status":
                        return response(request, result={"capabilities": {"appleevent_transport": True}})
                    fields = {"backend": wrong_backend} if wrong_backend is not None else {}
                    return response(request, verified=True, **fields)

                process, output, requests, _ = self.run_cli(
                    ["transport", "play", "--backend", "appleevent"], responder,
                )
                self.assertEqual(process.returncode, 1)
                self.assertFalse(output["ok"] or output["verified"])
                self.assertEqual(output["error"], "backend_mismatch")
                self.assertEqual(len(requests), 2)
                self.assertEqual([request["command"] for request in requests], ["status", "transport.play"])

    def test_appleevent_failure_is_reported_without_retry(self):
        def responder(request: Request):
            if request["command"] == "status":
                return response(request, result={"capabilities": {"appleevent_transport": True}})
            return response(
                request, backend="appleevent", readback_backend="mcu", ok=False,
                error="appleevent_permission_denied", observed={"playing": False, "recording": False},
                result={"sent": True, "appleevent_send_status": -1743, "appleevent_reply_error": None},
            )

        process, output, requests, _ = self.run_cli(
            ["transport", "stop", "--backend", "appleevent"], responder,
        )
        self.assertEqual(process.returncode, 1)
        self.assertEqual(output["error"], "appleevent_permission_denied")
        self.assertFalse(output["verified"])
        self.assertIsNone(output["result"]["appleevent_reply_error"])
        self.assertEqual(len(requests), 2)

    def test_default_transport_remains_one_legacy_mcu_request(self):
        for action in ("play", "stop"):
            with self.subTest(action=action):
                process, output, requests, _ = self.run_cli(
                    ["transport", action], lambda request: response(request, backend="mcu", verified=True),
                )
                self.assertEqual(process.returncode, 0)
                self.assertEqual(output["backend"], "mcu")
                self.assertEqual(len(requests), 1)
                self.assertEqual(requests[0]["command"], f"transport.{action}")
                self.assertEqual(set(requests[0]), {"id", "command", "args"})
                self.assertEqual(requests[0]["args"], {})

    def test_explicit_mcu_skips_appleevent_capability_probe(self):
        process, output, requests, _ = self.run_cli(
            ["transport", "play", "--backend", "mcu"],
            lambda request: response(request, backend="mcu", verified=True),
        )
        self.assertEqual(process.returncode, 0)
        self.assertEqual(output["backend"], "mcu")
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0]["backend"], "mcu")
        self.assertEqual(requests[0]["command"], "transport.play")

    def test_invalid_backend_or_command_returns_usage_without_socket_request(self):
        invalid_args = [
            ["transport", "play", "--backend", "unknown"],
            ["transport", "play", "--backend"],
            ["transport", "play", "--backend", "--json"],
            ["transport", "play", "--backend", "mcu", "--backend", "appleevent"],
            ["status", "--backend", "appleevent"],
            ["track", "mute", "1", "on", "--backend", "appleevent"],
            ["transport", "record", "--backend", "appleevent"],
            ["unknown", "--backend", "mcu"],
        ]
        for args in invalid_args:
            with self.subTest(args=args):
                process, output, requests, connections = self.run_cli(
                    args, lambda request: response(request),
                )
                self.assertEqual(process.returncode, 64)
                self.assertFalse(output["ok"])
                self.assertFalse(output["verified"])
                self.assertEqual(output["error"], "usage")
                # Guidance remains on stderr regardless of its human language.
                self.assertIn("logicctl <command>", process.stderr)
                self.assertEqual(requests, [])
                self.assertEqual(connections, 0)


def main() -> int:
    global CLI_BINARY
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logicctl", type=Path, help="the built logicctl executable")
    parser.add_argument("--wait-for-binary", type=float, default=0,
                        help="wait at most this many seconds for the binary to exist (maximum 60)")
    args = parser.parse_args()
    if not 0 <= args.wait_for_binary <= 60:
        parser.error("--wait-for-binary must be between 0 and 60 seconds")
    CLI_BINARY = args.logicctl.resolve()
    deadline = time.monotonic() + args.wait_for_binary
    while not CLI_BINARY.is_file() and time.monotonic() < deadline:
        time.sleep(0.05)
    if not CLI_BINARY.is_file() or not os.access(CLI_BINARY, os.X_OK):
        parser.error(f"logicctl executable is not available: {CLI_BINARY}")
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(CLIBackendCompatibilityTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
