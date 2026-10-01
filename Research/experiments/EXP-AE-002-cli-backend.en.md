[日本語](EXP-AE-002-cli-backend.md) | [English](EXP-AE-002-cli-backend.en.md)

# EXP-AE-002: product CLI AppleEvent transport with MCU readback

| Field | Value |
|---|---|
| Date | 2026-10-01, Asia/Tokyo; raw run began 18:30:46 JST |
| Logic version | Creator Studio 12.3.1 (6682), running PID 37546 |
| macOS version | 27.0 (26A5416b), arm64; same environment as EXP-AE-001 |
| Selected developer tools | `/Applications/Xcode.app/Contents/Developer`; full Xcode available for this integration build |
| Logic Remote version | n/a |
| Test project | `/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx` |
| Initial state | `playing=false`, `recording=false`; exactly one scripting document |
| Single action | One `transport play` or `transport stop` request per case; AppleEvent selected explicitly |
| Expected change | Match the requested transport state through MCU feedback; retain recording=false |
| Reproduction count | Two native play/stop pairs, one play no-op, one stop no-op; one MCU comparison pair |
| Final state | `playing=false`, `recording=false` |

## Confirmed result

The shipping Swift CLI/daemon path now performs native AppleEvent play/stop
and independently verifies transport through the MCU backend. This milestone
integrates the event established in [EXP-AE-001](EXP-AE-001-private-command-dispatch.md);
it does not establish a native state-query API. Product `Sources/` has no
runtime dependency on `Research/`, `Tools/`, Python, or `osascript`.

Implementation evidence: `Sources/LogicCore/Backends/AppleEvent/AppleEventTransportBackend.swift`,
`Sources/LogicCore/Backends/MCU/MCUBackend.swift`, and `Sources/logicctl/main.swift`.
Test evidence: `Tests/LogicCoreTests/AppleEventBackendTests.swift` and
`Tests/integration/test_cli_backend_compat.py`.

The native backend permits only Logic 12.3.1/build 6682 and internal commands
3 (play) and 5 (stop), with `aUeV/Spt2`, signed int32 `sPmo=6`, and signed
int32 `sPkc=-3/-5`. It targets the running PID and verifies that Logic has not
restarted while preparing readback. A missing or unknown transport baseline
blocks the write; initialized LED defaults are not treated as observations.

## Live observations and evidence

Raw files, intentionally gitignored:
`Research/raw/20261001T093046Z-appleevent-cli/preflight.json` and `live.json`.

The old daemon, PID 63565, returned a successful status without an AppleEvent
capability. Explicit AppleEvent stop returned exit 1,
`error=daemon_upgrade_required`, `verified=false`. The CLI capability gate
returns before sending the transport request; separate fake-socket capture
below verifies the absence of a mutation on this legacy path.

After stopping the old daemon, the release CLI launched daemon PID 6853.
Its initial status advertised the new capability while MCU was still
disconnected and omitted transport state. A later status established the
MCU connection and both known transport LEDs before live controls began.

Each attempted transport write had a preceding standard scripting check
confirming the same single document and exact test-project path. The native
write itself is sent by `AESendMessage`, without AppleScript. No real music
project, recording command, seek, mixer, or plugin operation was exercised.

| Raw case label | Command/backend | Before → observed playing | Sent | Result |
|---|---|---|---|---|
| `native_stop_noop` | stop/appleevent | false → false | false | verified=true; recording=false |
| `native_play_1` | play/appleevent | false → true | true | verified=true; recording=false |
| `native_play_noop` | play/appleevent | true → true | false | verified=true; recording=false |
| `native_stop_1` | stop/appleevent | true → false | true | verified=true; recording=false |
| `native_play_2` | play/appleevent | false → true | true | verified=true; recording=false |
| `native_stop_2` | stop/appleevent | true → false | true | verified=true; recording=false |
| `default_mcu_play` | play/default MCU | false → true | MCU write | verified=true; recording=false |
| `explicit_mcu_stop` | stop/explicit MCU | true → false | MCU write | verified=true; recording=false |

All four actual native sends had `appleevent_send_status=0` and a received
valid AppleEvent reply. **The reply omitted `errn`**, represented as
`appleevent_reply_error=null`; this is not an observed zero error field. A
successful delivery plus a valid reply without an error parameter and
matching MCU feedback permits success. The two no-ops sent nothing and
reported all AppleEvent status/reply fields as null. A redundant Stop is
avoided because another Stop can move the playhead.

Representative live play response, with request ID and unrelated metadata
omitted:

```json
{
  "command": "transport.play",
  "backend": "appleevent",
  "readback_backend": "mcu",
  "ok": true,
  "verified": true,
  "requested": {"playing": true},
  "observed": {"playing": true, "recording": false},
  "result": {
    "sent": true,
    "command_id": 3,
    "event_class": "aUeV",
    "event_id": "Spt2",
    "appleevent_send_status": 0,
    "appleevent_reply_received": true,
    "appleevent_reply_error": null,
    "logic_version": "12.3.1",
    "logic_build": "6682",
    "target_pid": 37546
  }
}
```

`final_status` confirms the daemon remained connected with playback and
recording both false. Network/IPC traffic was not packet-captured for this
milestone; evidence is the recorded CLI requests, responses, document
checks, and independent MCU state, plus the socket-capture tests below.

### Final merged-build repeat

After incorporating commit `373f9ea` (discard previous-session surface data),
the final release build repeated the same eight transport cases successfully.
Evidence: `Research/raw/20261001T132819Z-appleevent-cli-merged/results.json`.
Daemon PID 16655 targeted the same Logic PID 37546. The first `track list`
after restarting the daemon also returned all 12 nonempty strip names.
Both native play/stop pairs had status 0, valid replies with `errn` absent,
and matching MCU feedback; both native no-ops sent nothing. Final state was
again playing=false and recording=false. Logic itself was not restarted.

Session clearing now also records an internal transport LED baseline. The
continuing counters cannot validate cleared, default-off LEDs through the
snapshot accessor before both LEDs are received again. The daemon retains
its PID/generation, same-batch feedback, and fresh LCD checks.

An earlier repeat preparation using a variable AppleScript application target
could not resolve Logic's document `path` property (`-1728`) and stopped at
the document guard before any daemon restart or transport write. Reproduction
below compiles that guard with the discovered, validated bundle ID instead.

The final hash-gated Ghidra export also completed:
`Research/raw/20261001T093700Z-ghidra-appleevents-hashguard/headless.log`
records the expected program SHA-256, successful export, and
`Discarding changes ... /Logic.arm64`. The installed binary, loose imported
copy, and Ghidra program metadata are checked before fixed anchors are used.

## Automated validation, separate from live coverage

The final merged Swift suite passed **52 tests**, and `swift build -c release`
passed. Injected senders/readback cover unavailable Logic or LED state,
unknown version/build, process replacement, a send/reply error even when
state happens to match, no state change after acknowledgment, recording
remaining active after Stop, missing/malformed replies, asynchronous
feedback, and cached-state/PID regression cases. Descriptor tests inspect
the actual event's PID and int32 parameter types without sending it.

The built CLI passed **8 process tests / 23 cases** against isolated fake
Unix sockets. These capture the wire requests and confirm that:

- Old/missing/false or wrongly typed capabilities send a legacy status
  request only; failed capability status also blocks the write.
- Supported explicit play/stop sends exactly one mutation, with backend
  `appleevent`, on the same connection as the capability probe.
- Wrong/missing response backend and a reported AppleEvent failure cause
  an error without retrying or switching to MCU.
- Default MCU sends the legacy request with no `backend` field; explicit
  MCU skips AppleEvent capability probing.
- Invalid backend/command arguments exit 64 before any socket connection.

These tests use nonexistent `LOGICD_PATH` and short private `/tmp` sockets;
they cannot launch the real daemon or send events to Logic. Permission
denial, send timeout, unavailable readback, unsupported versions, and
replacement-process failures were simulated, **not reproduced live**.

## Reproduction

From the repository, build and run the checks that do not control Logic:

```sh
./scripts/test.sh
swift build -c release
python3 Tests/integration/test_cli_backend_compat.py .build/release/logicctl
```

For the live sequence, open only the dedicated test project. The following
checks its document count/name/path before every transport request, discovers
the bundle ID from CLI status, and finally stops playback. The document check
is an experiment guard; it is not part of the product backend.

```python
import json
from pathlib import Path
import re
import subprocess

cli = str(Path(".build/release/logicctl").resolve())
project = "/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx"

def ctl(*args):
    completed = subprocess.run([cli, *args], text=True, capture_output=True,
                               timeout=20, check=True)
    return json.loads(completed.stdout)

def guarded_transport(action, backend):
    state = ctl("status")
    bundle_id = state["result"]["logic"]["bundle_id"]
    assert re.fullmatch(r"[A-Za-z0-9.-]+", bundle_id)
    assert state["result"]["transport"]["recording"] is False
    # Compile with the discovered app's terminology. A variable application
    # target cannot resolve Logic's document properties at compile time.
    script = f'''tell application id "{bundle_id}"
        with timeout of 10 seconds
            return {{count of documents, name of document 1, path of document 1}}
        end timeout
    end tell'''
    guard = subprocess.run(["/usr/bin/osascript", "-e", script],
                           text=True, capture_output=True, timeout=15, check=True)
    assert guard.stdout.strip() == f"1, LogicCLI-Test, {project}"
    args = ["transport", action]
    if backend is not None:
        args += ["--backend", backend]
    result = ctl(*args)
    assert result["verified"] and not result["observed"]["recording"]
    print(json.dumps(result, sort_keys=True))

# If status lacks capabilities, stop the older daemon, then rerun status to
# launch the new release daemon before executing this sequence.
guarded_transport("stop", "appleevent")
guarded_transport("play", "appleevent")
guarded_transport("play", "appleevent")
guarded_transport("stop", "appleevent")
guarded_transport("play", "appleevent")
guarded_transport("stop", "appleevent")
guarded_transport("play", None)
guarded_transport("stop", "mcu")
assert ctl("status")["result"]["transport"] == {
    "playing": False, "recording": False
}
```

## Hypothesis and remaining unknowns

**Hypothesis:** an external read-only transport-state entry point could
replace MCU readback without changing the confirmed native write event.
**Confidence:** low until such an external entry point and reply schema are
identified. Evidence is limited to the existing internal state/feedback
paths; finding an internal getter alone does not prove CLI reachability.

No cross-version compatibility, native recording behavior, or pure native
transport-state retrieval is confirmed. Mode 4 remains unsuitable as a
read-only status API while its tempo-writing branch is unresolved. This
milestone establishes neither playhead-position stability for repeated
requests nor timing guarantees beyond matching transport readback.

**Next validation experiment:** statically trace Logic Remote's transport
state serialization and external message entry points, record each exact
call site and schema, then test a single candidate query against the
dedicated project with independent MCU state. Do not expose that query or
claim it is read-only until side effects and repeated replies are checked.

## Japanese CLI guidance validation

After localization, the release build, 52 Swift tests, and 8 CLI process tests / 23 cases passed. `Research/raw/20261001T135229Z-japanese-cli/results.json` confirms Japanese help on stderr and an unknown backend returning exit 64 with `error: "usage"` and a Japanese `message`. JSON keys, command names, and error identifiers remain stable.

After the dedicated-project guard, Japanese daemon PID 22345 returned the already-stopped AppleEvent request with a Japanese no-op message, `sent: false`, and `verified: true`. This check sent no transport event. The final playing and recording states remained false.
