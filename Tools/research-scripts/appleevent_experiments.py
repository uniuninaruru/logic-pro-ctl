#!/usr/bin/env python3
"""Bounded private AppleEvent experiments with independent MCU readback.

Dry run by default. --send only operates on the explicitly named dedicated
    test project, guarded by appleevent-probe before every send. No record, seek,
file import, or undocumented mode is tested. The matrix ends stopped.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]


def run(argv: list[str]) -> dict:
    try:
        process = subprocess.run(argv, capture_output=True, text=True, timeout=35)
    except subprocess.TimeoutExpired as error:
        def decoded(value):
            return value.decode(errors="replace") if isinstance(value, bytes) else (value or "")
        return {"argv": argv, "timeout_seconds": 35, "error": str(error),
                "stdout": decoded(error.stdout), "stderr": decoded(error.stderr)}
    result = {"argv": argv, "exit": process.returncode, "stdout": process.stdout, "stderr": process.stderr}
    try:
        result["json"] = json.loads(process.stdout)
    except ValueError:
        pass
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["matrix", "play", "stop"], nargs="?", default="matrix")
    parser.add_argument("--send", action="store_true")
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--probe", type=Path, default=ROOT / ".build/appleevent-probe")
    parser.add_argument("--logicctl", type=Path, default=ROOT / ".build/debug/logicctl")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.project.is_absolute() or args.project.name != "LogicCLI-Test.logicx":
        parser.error("--project must be an absolute LogicCLI-Test.logicx path")
    if args.project.resolve().name != "LogicCLI-Test.logicx":
        parser.error("resolved --project must also be named LogicCLI-Test.logicx")

    # Each control changes only one event/parameter variable from mode6/key-3.
    mode = "sPmo=long:6"
    cases = [
        ("unknown_event_id", ["--id", "ZZzz", mode, "sPkc=long:-3"], -1708, False),
        ("unknown_event_class", ["--class", "ZZzz", mode, "sPkc=long:-3"], -1708, False),
        ("missing_mode", ["sPkc=long:-3"], -1701, False),
        ("wrong_mode_type", ["sPmo=text:6", "sPkc=long:-3"], 0, False),
        ("missing_key", [mode], -1701, False),
        ("wrong_key_type", [mode, "sPkc=text:-3"], 0, False),
        ("zero_key_noop", [mode, "sPkc=long:0"], 0, False),
        ("direct_play_1", [mode, "sPkc=long:-3"], 0, True),
        ("direct_play_already_playing", [mode, "sPkc=long:-3"], 0, True),
        ("direct_stop_1", [mode, "sPkc=long:-5"], 0, False),
        ("direct_play_2", [mode, "sPkc=long:-3"], 0, True),
        ("direct_stop_2", [mode, "sPkc=long:-5"], 0, False),
        ("mapped_play_index_11", [mode, "sPkc=long:11"], 0, True),
        ("mapped_stop_index_1", [mode, "sPkc=long:1"], 0, False),
    ]
    if args.action != "matrix":
        playing = args.action == "play"
        cases = [(args.action, [mode, f"sPkc=long:{-3 if playing else -5}"], 0, playing)]
    plan = {"action": args.action, "sent": False, "verified": False,
            "cases": [{"label": label, "parameters_and_options": options, "expected_reply_error": error,
                       "expected_playing": playing} for label, options, error, playing in cases]}
    if not args.send:
        print(json.dumps(plan, ensure_ascii=False, sort_keys=True))
        return 0
    for path in [args.probe, args.logicctl]:
        if not path.is_file():
            parser.error(f"executable not found: {path}")
    output = args.output or ROOT / "Research/raw" / (dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-appleevent-native") / "results.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []

    def state() -> dict:
        record = run([str(args.logicctl), "status"])
        data = record.get("json", {})
        if record.get("exit") != 0 or not data.get("ok") or not data.get("result", {}).get("mcu", {}).get("connected"):
            raise RuntimeError(f"MCU readback unavailable: {record}")
        observed = data.get("result", {}).get("transport")
        if not isinstance(observed, dict) or any(type(observed.get(key)) is not bool for key in ["playing", "recording"]):
            raise RuntimeError(f"transport readback unavailable: {record}")
        return record

    def transport(record: dict) -> dict:
        return record["json"]["result"]["transport"]

    initial = state()
    if transport(initial).get("recording") is not False:
        raise RuntimeError("refusing experiment while recording or recording state unavailable")
    if args.action == "matrix" and transport(initial).get("playing") is not False:
        raise RuntimeError("matrix requires initially stopped transport")
    result = {"action": args.action, "time_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "project": str(args.project), "initial": initial, "records": records, "verified": False}

    def persist() -> None:
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")

    try:
        for label, options, expected_error, expected_playing in cases:
            before = state()
            if transport(before)["recording"]:
                raise RuntimeError("recording became active; experiment stopped before sending")
            sender = run([str(args.probe), "--send", "--project", str(args.project), *options])
            record = {"label": label, "before": before, "sender": sender,
                      "expected_reply_error": expected_error, "expected_playing": expected_playing,
                      "verified": False}
            records.append(record)
            persist()
            after = state()
            deadline = time.monotonic() + 2
            while transport(after).get("playing") != expected_playing and time.monotonic() < deadline:
                time.sleep(0.05)
                after = state()
            reply = sender.get("json", {})
            expected_exit = 0 if expected_error == 0 else 1
            matched = (sender.get("exit") == expected_exit and reply.get("sent") is True
                       and reply.get("send_status") == 0 and reply.get("reply_error") == expected_error
                       and transport(after) == {"playing": expected_playing, "recording": False})
            record.update(after=after, verified=matched)
            persist()
            print(f"{label}: reply={reply.get('reply_error')} transport={transport(after)} verified={matched}", file=sys.stderr)
            if not matched:
                raise RuntimeError(f"experiment mismatch: {label}; inspect {output}")
        result["ok"] = True
        result["verified"] = True
    except (RuntimeError, OSError) as error:
        result.update(ok=False, verified=False, error=str(error))
    finally:
        # Every restoration also runs the native sender's exact project guard.
        # If a user changes documents or readback fails, record failure and stop.
        try:
            if args.action == "matrix":
                restoration_before = state()
                result["restoration_before"] = restoration_before
                if transport(restoration_before)["recording"]:
                    raise RuntimeError("recording became active; native stop restoration skipped")
                restoration = run([str(args.probe), "--send", "--project", str(args.project), mode, "sPkc=long:-5"])
                result["restoration"] = restoration
                persist()
                after = state()
                result["final"] = after
                if restoration.get("exit") != 0 or transport(after) != {"playing": False, "recording": False}:
                    result.update(ok=False, verified=False, restoration_error="native restoration or readback failed")
        except (RuntimeError, OSError) as error:
            result.update(ok=False, verified=False, restoration_error=str(error))
        finally:
            persist()
    last_state = result.get("final") or next((record.get("after") for record in reversed(records) if record.get("after")), None)
    print(json.dumps({"ok": result.get("ok", False), "verified": result["verified"],
                      "backend": "private-appleevent", "readback_backend": "mcu",
                      "case_count": len(records), "output": str(output),
                      "observed": transport(last_state) if last_state else None,
                      "error": result.get("error") or result.get("restoration_error")}, sort_keys=True))
    return 0 if result.get("ok") and result["verified"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError) as error:
        print(json.dumps({"ok": False, "verified": False, "error": str(error)}))
        raise SystemExit(1)
