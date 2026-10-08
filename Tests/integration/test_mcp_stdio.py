#!/usr/bin/env python3
"""MCP -> real CLI -> isolated fake daemon. No Logic or real daemon events.

Usage: python3 Tests/integration/test_mcp_stdio.py .build/debug/logicmcp .build/debug/logicctl
Reuses the bounded fake socket harness from CLI compatibility tests.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import select
import subprocess
import sys
import unittest

from test_cli_backend_compat import FakeDaemon, response


MCP_BINARY: Path
CLI_BINARY: Path


def request(identifier, method, **params):
    return {"jsonrpc": "2.0", "id": identifier, "method": method, "params": params}


INITIALIZE = request(1, "initialize", protocolVersion="2025-11-25",
                     capabilities={}, clientInfo={"name": "offline-test", "version": "1"})
INITIALIZED = {"jsonrpc": "2.0", "method": "notifications/initialized"}


class MCPStdioTests(unittest.TestCase):
    def test_interactive_handshake_answers_while_stdin_is_open(self):
        env = {**os.environ, "LOGICCTL_PATH": "/nonexistent/logicctl"}
        process = subprocess.Popen([str(MCP_BINARY)], env=env, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            process.stdin.write(json.dumps(INITIALIZE) + "\n")
            process.stdin.flush()
            self.assertTrue(select.select([process.stdout], [], [], 2)[0],
                            "initialize blocked until EOF/full buffer")
            self.assertEqual(json.loads(process.stdout.readline())["result"]["protocolVersion"],
                             "2025-11-25")
            process.stdin.write(json.dumps(INITIALIZED) + "\n" +
                                json.dumps(request(2, "tools/list")) + "\n")
            process.stdin.flush()
            self.assertTrue(select.select([process.stdout], [], [], 2)[0])
            self.assertEqual(len(json.loads(process.stdout.readline())["result"]["tools"]), 4)
        finally:
            process.stdin.close()
            process.wait(timeout=3)
            process.stdout.close()
            process.stderr.close()
        self.assertEqual(process.returncode, 0)

    def test_oversized_message_is_bounded_and_next_line_still_works(self):
        completed = subprocess.run([str(MCP_BINARY)], input="x" * 1_048_577 + "\n" +
                                   json.dumps(request(1, "ping")) + "\n",
                                   text=True, capture_output=True, timeout=5)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        replies = [json.loads(line) for line in completed.stdout.splitlines()]
        self.assertEqual(replies[0]["error"]["code"], -32600)
        self.assertEqual(replies[1], {"jsonrpc": "2.0", "id": 1, "result": {}})

    def exchange(self, daemon, messages):
        env = {**os.environ, "LOGICCTL_PATH": str(CLI_BINARY),
               "LOGICCTL_SOCKET": daemon.path, "LOGICD_PATH": "/nonexistent/logicd"}
        completed = subprocess.run([str(MCP_BINARY)], env=env,
                                   input="".join(json.dumps(m) + "\n" for m in messages),
                                   text=True, capture_output=True, timeout=12)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return [json.loads(line) for line in completed.stdout.splitlines()]

    def test_discovery_and_resource_use_existing_read(self):
        observation = {"complete": False, "session": {"handshake_generation": 3},
                       "source": "fake-daemon"}
        with FakeDaemon(lambda r: response(r, result={"tracks": []},
                                          observation=observation)) as daemon:
            output = self.exchange(daemon, [INITIALIZE, INITIALIZED,
                request(2, "tools/list"), request(3, "resources/list"),
                request(4, "resources/templates/list"),
                request(5, "resources/read", uri="logicctl://tracks/2")])
            self.assertEqual(len(output), 5)  # notification has no response
            self.assertEqual(output[0]["result"]["protocolVersion"], "2025-11-25")
            self.assertEqual({t["name"] for t in output[1]["result"]["tools"]},
                             {"logic_read", "logic_transport", "logic_track", "logic_mixer"})
            self.assertEqual(len(output[2]["result"]["resources"]), 3)
            self.assertEqual(len(output[3]["result"]["resourceTemplates"]), 1)
            content = json.loads(output[4]["result"]["contents"][0]["text"])
            self.assertFalse(content["verified"])
            self.assertEqual(content["observation"], observation)
            self.assertEqual([(r["command"], r["args"]) for r in daemon.requests],
                             [("track.get", {"track": "2"})])

    def test_write_guards_and_failed_readback_survive_mcp(self):
        def respond(r):
            if r["command"] == "status":
                return response(r, result={"capabilities": {
                    "execution_contract": True, "target_expectation": True}})
            return response(r, ok=False, error="verification_failed", backend="mcu",
                            requested={"pan": -0.5}, observed={"pan": 0},
                            execution={"state": "unknown", "replayed": False})

        with FakeDaemon(respond) as daemon:
            output = self.exchange(daemon, [INITIALIZE, INITIALIZED,
                request(2, "tools/call", name="logic_mixer", arguments={
                    "action": "pan", "track": 2, "value": -0.5,
                    "expect_name": "Synth; $(ignored)", "expect_session": 3,
                    "deadline_ms": 1200, "idempotency_key": "mcp-pan-001"})])
            result = output[-1]["result"]
            self.assertTrue(result["isError"])
            payload = result["structuredContent"]
            self.assertEqual(json.loads(result["content"][0]["text"]), payload)
            self.assertFalse(payload["verified"])
            self.assertEqual(payload["error"], "verification_failed")
            self.assertEqual(payload["requested"], {"pan": -0.5})
            self.assertEqual(payload["observed"], {"pan": 0})
            self.assertEqual(payload["execution"]["state"], "unknown")
            sent = daemon.requests[-1]
            self.assertEqual(sent["command"], "track.pan")
            self.assertEqual(sent["args"]["expect_name"], "Synth; $(ignored)")
            self.assertEqual(sent["expect_session"], 3)
            self.assertEqual(sent["deadline_ms"], 1200)
            self.assertEqual(sent["idempotency_key"], "mcp-pan-001")

    def test_existing_daemon_gate_blocks_unsupported_backend(self):
        with FakeDaemon(lambda r: response(r, result={"capabilities": {}})) as daemon:
            output = self.exchange(daemon, [INITIALIZE, INITIALIZED,
                request(2, "tools/call", name="logic_transport", arguments={
                    "action": "play", "backend": "appleevent"})])
            result = output[-1]["result"]
            self.assertTrue(result["isError"])
            self.assertEqual(result["structuredContent"]["error"], "daemon_upgrade_required")
            self.assertFalse(result["structuredContent"]["verified"])
            self.assertEqual([r["command"] for r in daemon.requests], ["status"])


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    MCP_BINARY, CLI_BINARY = (Path(p).resolve() for p in sys.argv[1:])
    for binary in (MCP_BINARY, CLI_BINARY):
        if not binary.is_file():
            raise SystemExit(f"Missing built executable: {binary}")
    unittest.main(argv=[sys.argv[0]])
