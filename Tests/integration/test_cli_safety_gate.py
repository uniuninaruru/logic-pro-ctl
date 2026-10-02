#!/usr/bin/env python3
"""A safeguard the caller asked for is never silently dropped by an older daemon.

Usage:
    python3 Tests/integration/test_cli_safety_gate.py .build/debug/logicctl

An older logicd ignores request fields it does not know and would run the write without the
idempotency key, the session precondition, the deadline or the expected-name check. logicctl
therefore asks `status` for the capability first and sends nothing else when it is missing.
Uses the isolated fake daemon of test_cli_backend_compat.py; no Logic is touched.
"""

from __future__ import annotations

import argparse
import os
import sys
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_cli_backend_compat as compat  # noqa: E402

TRACK_MUTE = ["track", "mute", "3", "on"]
SAFEGUARDS = [
    ("idempotency key", ["--idempotency-key", "mute-3-on"], "execution_contract"),
    ("session precondition", ["--expect-session", "4"], "execution_contract"),
    ("deadline", ["--deadline-ms", "500"], "execution_contract"),
    ("expected name", ["--expect-name", "T03"], "target_expectation"),
]


def capable(*names: str):
    """A daemon that reports these capabilities and answers a write like the real one."""
    def responder(request: compat.Request) -> dict[str, Any]:
        if request["command"] == "status":
            return compat.response(request, result={"capabilities": {name: True for name in names}})
        return compat.response(request, backend="mcu", verified=True)
    return responder


class SafetyGateTests(unittest.TestCase):
    # The CLI runner and the status-only assertion of the existing suite, without its tests.
    run_cli = compat.CLIBackendCompatibilityTests.run_cli
    assert_status_only = compat.CLIBackendCompatibilityTests.assert_status_only

    def test_an_older_daemon_never_receives_a_write_that_asked_for_a_safeguard(self):
        old_daemons = [{}, {"result": {}}, {"result": {"capabilities": {}}},
                       {"result": {"capabilities": {"appleevent_transport": True}}},
                       {"result": {"capabilities": {"execution_contract": "true", "target_expectation": 1}}}]
        for label, option, _ in SAFEGUARDS:
            for fields in old_daemons:
                with self.subTest(safeguard=label, status_fields=fields):
                    process, output, requests, _ = self.run_cli(
                        TRACK_MUTE + option, lambda request: compat.response(request, **fields))
                    self.assertEqual(process.returncode, 1)
                    self.assertFalse(output["ok"] or output["verified"])
                    self.assertEqual(output["error"], "daemon_upgrade_required")
                    self.assertIn("何も送信していません", output["message"])
                    self.assert_status_only(requests)

    def test_a_capable_daemon_gets_one_probe_and_then_the_whole_request(self):
        for label, option, capability in SAFEGUARDS:
            with self.subTest(safeguard=label):
                process, output, requests, connections = self.run_cli(TRACK_MUTE + option, capable(capability))
                self.assertEqual(process.returncode, 0)
                self.assertTrue(output["ok"] and output["verified"])
                self.assertEqual([r["command"] for r in requests], ["status", "track.mute"])
                self.assertEqual(connections, 1)
                write = requests[1]
                if label == "expected name":
                    self.assertEqual(write["args"]["expect_name"], "T03")
                if label == "idempotency key":
                    self.assertEqual(write["idempotency_key"], "mute-3-on")
                if label == "session precondition":
                    self.assertEqual(write["expect_session"], 4)
                if label == "deadline":
                    self.assertEqual(write["deadline_ms"], 500)

    def test_every_capability_a_request_needs_must_be_present(self):
        both = TRACK_MUTE + ["--idempotency-key", "k1", "--expect-name", "T03"]
        for present in (["execution_contract"], ["target_expectation"]):
            with self.subTest(present=present):
                process, output, requests, _ = self.run_cli(both, capable(*present))
                self.assertEqual(output["error"], "daemon_upgrade_required")
                self.assert_status_only(requests)
        process, output, requests, _ = self.run_cli(both, capable("execution_contract", "target_expectation"))
        self.assertTrue(output["ok"])
        self.assertEqual([r["command"] for r in requests], ["status", "track.mute"])

    def test_a_request_without_safeguards_stays_one_legacy_request(self):
        process, output, requests, _ = self.run_cli(TRACK_MUTE, capable())
        self.assertEqual(process.returncode, 0)
        self.assertEqual([r["command"] for r in requests], ["track.mute"])
        self.assertEqual(set(requests[0]), {"id", "command", "args"})
        self.assertEqual(requests[0]["args"], {"track": "3", "state": "on"})

    def test_a_failed_capability_probe_sends_nothing_else(self):
        process, output, requests, _ = self.run_cli(
            TRACK_MUTE + ["--expect-name", "T03"],
            lambda request: compat.response(request, ok=False, error="status_failed",
                                            result={"capabilities": {"target_expectation": True}}))
        self.assertEqual(output["error"], "daemon_upgrade_required")
        self.assert_status_only(requests)

    def test_misuse_is_a_usage_error_before_any_socket_request(self):
        for argv in (["track", "list", "--expect-name", "x"], ["transport", "play", "--expect-name", "x"],
                     ["track", "mute", "3", "on", "--expect-name", ""], ["status", "--idempotency-key", "k"]):
            with self.subTest(argv=argv):
                process, output, requests, connections = self.run_cli(argv, capable("target_expectation"))
                self.assertEqual(process.returncode, 64)
                self.assertEqual(output["error"], "usage")
                self.assertEqual(requests, [])
                self.assertEqual(connections, 0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    options, remaining = parser.parse_known_args()
    compat.CLI_BINARY = Path(options.binary).resolve()
    if not os.access(compat.CLI_BINARY, os.X_OK):
        raise SystemExit(f"not executable: {compat.CLI_BINARY}")
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(SafetyGateTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
