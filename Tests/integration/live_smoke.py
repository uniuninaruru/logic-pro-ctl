#!/usr/bin/env python3
"""A repeatable spot check of logicctl against the real Logic, on the dedicated test project only.

Usage:
    python3 Tests/integration/live_smoke.py .build/debug/logicctl --test-project

This is NOT part of the automated tests: it needs Logic Pro running with LogicCLI-Test.logicx open, the
virtual MCU surface connected, and it changes (and restores) mute, solo, volume and pan of a few tracks.
It refuses to run on anything that does not look like the test project: the track names must be exactly
the expected ones (override with --expected-names only for another dedicated project). Nothing is
written before that check passes. Every write is undone in a `finally` block; the final state is
compared with the initial one and any difference is reported (record-arm cannot be set from the CLI).

The transcript (every command and its JSON) goes to --out (default Research/raw/live-smoke/, not tracked by Git).
Exit status: 0 all checks passed, 1 a check failed, 2 refused to run (not the test project / not connected).
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

EXPECTED_NAMES = ["Piano", "Audio", "Bass", "Synth", "Trk05", "Trk06", "Trk07", "Trk08", "Trk09", "Trk10", "St Out", "Master"]
SOCKET = os.path.expanduser(os.environ.get("LOGICCTL_SOCKET") or "~/Library/Application Support/logicctl/logicd.sock")


class Smoke:
    def __init__(self, binary: Path, out: Path, expected: list[str]):
        self.binary, self.expected = binary, expected
        self.run_id = datetime.now(timezone.utc).strftime("%H%M%S") + uuid.uuid4().hex[:4]
        out.mkdir(parents=True, exist_ok=True)
        self.transcript = open(out / f"smoke-{self.run_id}.log", "w", encoding="utf-8")
        self.results: list[tuple[str, bool, str]] = []
        self.initial: dict[int, dict] = {}
        self.initial_selected: int | None = None

    # -- plumbing ---------------------------------------------------------
    def key(self, name: str) -> str:
        return f"smoke-{self.run_id}-{name}"

    def cli(self, *args: str, timeout: float = 60) -> dict:
        started = time.time()
        done = subprocess.run([str(self.binary), *args], capture_output=True, text=True, timeout=timeout)
        try:
            reply = json.loads(done.stdout.strip().splitlines()[-1])
        except (IndexError, json.JSONDecodeError):
            reply = {"ok": False, "error": "unparseable_output", "stdout": done.stdout, "stderr": done.stderr}
        self.transcript.write(f"$ logicctl {' '.join(args)}   [{time.time() - started:.2f}s exit={done.returncode}]\n{json.dumps(reply, ensure_ascii=False)}\n")
        self.transcript.flush()
        return reply

    def raw(self, request: dict) -> dict:
        sock = socket.socket(socket.AF_UNIX)
        sock.settimeout(60)
        sock.connect(SOCKET)
        sock.sendall((json.dumps({"id": str(uuid.uuid4()), **request}) + "\n").encode())
        buffer = b""
        while not buffer.endswith(b"\n"):
            buffer += sock.recv(65536)
        reply = json.loads(buffer)
        self.transcript.write(f"RAW {json.dumps(request, ensure_ascii=False)}\n{json.dumps(reply, ensure_ascii=False)}\n")
        return reply

    def check(self, name: str, ok: bool, detail: str = "") -> bool:
        self.results.append((name, bool(ok), detail))
        print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  — {detail}" if detail and not ok else ""))
        return bool(ok)

    def tracks(self) -> list[dict]:
        reply = self.cli("track", "list")
        return reply.get("result") or [] if reply.get("ok") and reply.get("observation", {}).get("complete") else []

    @staticmethod
    def snapshot(tracks: list[dict]) -> dict[int, dict]:
        return {t["id"]: {k: t.get(k) for k in ("name", "mute", "solo", "rec_armed", "selected", "volume_db", "pan_raw")} for t in tracks}

    # -- safety gate ------------------------------------------------------
    def gate(self) -> int:
        status = self.cli("status")
        mcu = (status.get("result") or {}).get("mcu", {})
        if not status.get("ok") or not mcu.get("connected"):
            print("REFUSED: logicd is not connected to Logic's control surface (is Logic running with the test project open?)")
            return 2
        tracks = self.tracks()
        names = [t["name"] for t in tracks]
        if names != self.expected:
            print(f"REFUSED: the track names do not match the dedicated test project.\n  expected {self.expected}\n  found    {names}")
            return 2
        self.initial = self.snapshot(tracks)
        selected = [t["id"] for t in tracks if t.get("selected")]
        self.initial_selected = selected[0] if selected else None
        print(f"Test project recognised ({len(tracks)} strips). Transcript: {self.transcript.name}")
        compat = (status.get("result") or {}).get("compatibility", {})
        print(f"Environment: profile_verified={compat.get('profile_verified')} (a value other than true means an unverified environment)")
        self.compat = compat
        return 0

    # -- the checks -------------------------------------------------------
    def reads(self):
        status = self.cli("status")
        self.check("status reports a compatibility block", "compatibility" in (status.get("result") or {}))
        tracks = self.tracks()
        self.check("track list is complete with 12 strips", len(tracks) == 12)
        self.check("every strip says its id is a mixer position",
                   all(t.get("identity", {}).get("scope") == "mixer_position" for t in tracks))
        self.check("names are unique in a complete scan", all(t.get("identity", {}).get("name_unique") is True for t in tracks))
        got = self.cli("track", "get", "3", "--expect-name", "Bass")
        self.check("track get with the right expected name succeeds", got.get("ok") is True)
        bad = self.cli("track", "get", "3", "--expect-name", "Piano")
        self.check("track get with a wrong expected name is refused", bad.get("error") == "target_mismatch" and "result" not in bad)
        self.check("track 13 does not exist", self.cli("track", "get", "13").get("error") == "no_such_track")

    def toggle(self, kind: str, track: int, name: str):
        key = self.key(f"{kind}{track}")
        on = self.cli("track", kind, str(track), "on", "--expect-name", name, "--idempotency-key", key + "-on")
        self.check(f"{kind} {track} on is verified", on.get("ok") and on.get("verified") and (on.get("observed") or {}).get(kind) is True,
                   json.dumps(on, ensure_ascii=False)[:200])
        replay = self.cli("track", kind, str(track), "on", "--expect-name", name, "--idempotency-key", key + "-on")
        self.check(f"{kind} {track} on resent with the same key is replayed", (replay.get("execution") or {}).get("state") == "replayed")
        off = self.cli("track", kind, str(track), "off", "--expect-name", name, "--idempotency-key", key + "-off")
        self.check(f"{kind} {track} off is verified", off.get("ok") and off.get("verified") and (off.get("observed") or {}).get(kind) is False)

    def values(self):
        for db in (-6.0, 0.0):
            reply = self.cli("track", "volume", "4", str(db), "--expect-name", "Synth", "--idempotency-key", self.key(f"vol{db}"))
            observed = (reply.get("observed") or {}).get("volume_db")
            self.check(f"volume 4 {db} dB is verified", reply.get("ok") and reply.get("verified") and observed is not None and abs(observed - db) <= 0.11,
                       json.dumps(reply, ensure_ascii=False)[:200])
        for pan in (-0.25, 0.0):
            reply = self.cli("track", "pan", "5", str(pan), "--expect-name", "Trk05", "--idempotency-key", self.key(f"pan{pan}"))
            self.check(f"pan 5 {pan} is verified", reply.get("ok") and reply.get("verified"), json.dumps(reply, ensure_ascii=False)[:200])

    def contracts(self):
        key = self.key("conflict")
        self.cli("track", "mute", "6", "on", "--expect-name", "Trk06", "--idempotency-key", key)
        other = self.cli("track", "mute", "6", "off", "--expect-name", "Trk06", "--idempotency-key", key)
        self.check("the same key with different content is refused", other.get("error") == "idempotency_key_conflict")
        self.cli("track", "mute", "6", "off", "--expect-name", "Trk06", "--idempotency-key", self.key("conflict-undo"))

        stale = self.cli("track", "mute", "7", "on", "--expect-session", "999999", "--idempotency-key", self.key("stale"))
        self.check("a stale --expect-session is refused", stale.get("error") == "precondition_failed")
        self.check("...and nothing was sent", next((t for t in self.tracks() if t["id"] == 7), {}).get("mute") is False)

        wait = self.cli("track", "volume", "9", "-3", "--expect-name", "Trk09", "--idempotency-key", self.key("late"), "--deadline-ms", "20")
        self.check("a 20 ms deadline gives timeout / unknown", wait.get("error") == "timeout" and (wait.get("execution") or {}).get("state") == "unknown")
        time.sleep(6)
        after = self.cli("track", "volume", "9", "-3", "--expect-name", "Trk09", "--idempotency-key", self.key("late"))
        self.check("the same key afterwards is replayed, not rerun", (after.get("execution") or {}).get("state") == "replayed" and after.get("verified") is True)
        self.cli("track", "volume", "9", "0", "--expect-name", "Trk09", "--idempotency-key", self.key("late-undo"))

    def slot(self):
        self.cli("track", "get", "1")  # park the bank at the start so the next write has to move it
        replies: dict[str, dict] = {}
        key = self.key("slot")
        request = {"command": "track.volume", "args": {"track": "10", "db": "-3", "expect_name": "Trk10"}, "idempotency_key": key}
        first = threading.Thread(target=lambda: replies.__setitem__("first", self.raw(request)))
        first.start()
        time.sleep(0.4)
        started = time.time()
        status = self.cli("status")
        status_seconds = time.time() - started
        duplicate = self.raw(request)
        first.join()
        self.check("status answers while a long write runs", status.get("ok") and status_seconds < 1.0, f"{status_seconds:.2f}s")
        self.check("a duplicate while the write is running is refused at once", duplicate.get("error") == "request_in_flight", str(duplicate.get("error")))
        self.check("the first write still completes and is verified", replies["first"].get("ok") and replies["first"].get("verified"))
        self.cli("track", "volume", "10", "0", "--expect-name", "Trk10", "--idempotency-key", self.key("slot-undo"))

    # -- restore and compare ---------------------------------------------
    def restore(self):
        tracks = self.tracks()
        if not tracks:
            print("  WARN  could not read the tracks to restore them; check the project by hand")
            return
        now = self.snapshot(tracks)
        for track_id, before in self.initial.items():
            current = now.get(track_id, {})
            name = before["name"]
            guard = ["--expect-name", name]
            n = self.key(f"restore{track_id}")
            if current.get("mute") != before["mute"]:
                self.cli("track", "mute", str(track_id), "on" if before["mute"] else "off", *guard, "--idempotency-key", n + "m")
            if current.get("solo") != before["solo"]:
                self.cli("track", "solo", str(track_id), "on" if before["solo"] else "off", *guard, "--idempotency-key", n + "s")
            if current.get("volume_db") != before["volume_db"] and before["volume_db"] is not None:
                self.cli("track", "volume", str(track_id), str(before["volume_db"]), *guard, "--idempotency-key", n + "v")
            if current.get("pan_raw") != before["pan_raw"] and before["pan_raw"] is not None:
                self.cli("track", "pan", str(track_id), str(before["pan_raw"] / 64), *guard, "--idempotency-key", n + "p")
        if self.initial_selected and not self.snapshot(self.tracks()).get(self.initial_selected, {}).get("selected"):
            self.cli("track", "select", str(self.initial_selected), "--expect-name", self.initial[self.initial_selected]["name"],
                     "--idempotency-key", self.key("restore-select"))

    def compare(self):
        final = self.snapshot(self.tracks())
        differences = [(i, k, self.initial[i][k], final.get(i, {}).get(k))
                       for i in self.initial for k in self.initial[i] if self.initial[i][k] != final.get(i, {}).get(k)]
        self.check("the project is back in its initial state", not differences, f"differences: {differences}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logicctl", type=Path)
    parser.add_argument("--test-project", action="store_true", required=True,
                        help="confirm that Logic has the dedicated LogicCLI-Test.logicx open (required)")
    parser.add_argument("--expected-names", help="comma-separated track names of another dedicated project")
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[2] / "Research" / "raw" / "live-smoke")
    args = parser.parse_args()
    expected = args.expected_names.split(",") if args.expected_names else EXPECTED_NAMES
    smoke = Smoke(args.logicctl.resolve(), args.out, expected)
    refused = smoke.gate()
    if refused:
        return refused
    try:
        print("Reads:"); smoke.reads()
        print("Writes (mute, solo):"); smoke.toggle("mute", 3, "Bass"); smoke.toggle("solo", 2, "Audio")
        print("Writes (volume, pan):"); smoke.values()
        print("Contracts:"); smoke.contracts()
        print("Execution slot:"); smoke.slot()
    finally:
        print("Restoring:"); smoke.restore(); smoke.compare()
        smoke.transcript.close()
    failed = [r for r in smoke.results if not r[1]]
    print(f"\n{len(smoke.results) - len(failed)} passed, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
