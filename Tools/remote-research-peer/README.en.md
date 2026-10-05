[日本語](README.md) | [English](README.en.md)

# Research peer (receive-only, Logic Remote)

A small macOS app used within the approved scope of PLAN-05 ([approval brief](../../Research/plans/PLAN-05-approval-brief.en.md)). After two initial messages, it **only receives** and is not part of the product (`Sources/`). Previous results: [EXP-REMOTE-001](../../Research/experiments/EXP-REMOTE-001-receive-initial-state.en.md). Adding manual selection during reception requires checking the scope of the [E3-1 plan](../../Research/plans/PLAN-05-E3-manual-selection.en.md).

| Stage | What it does | What it sends |
|---|---|---|
| `e0` | Browse for the `apple-lgremote` advertisement and record it. No invitation | nothing |
| `e1` | Invite under its own name (default `logicctl-research-peer`). A person presses "Connect" in Logic's dialog. After connection and both successful initial sends, receive for `--seconds` (at most 120) | only `/protocolVersion = 10` and `/jsonSupport = 1`, once each. Trying to send anything else stops the process |

```sh
Tools/remote-research-peer/build.sh                       # build only; no launch or connection
Tools/remote-research-peer/test.sh                        # eight lifecycle cases; no communication
Tools/remote-research-peer/run.sh e0 --seconds 15
Tools/remote-research-peer/run.sh e1 --seconds 60 --target "<the name found by e0>"
touch Research/raw/remote-recv/<time>-e1/STOP              # stop early
python3 Tools/research-scripts/remote_capture.py report Research/raw/remote-recv/<time>-e1
```

Output goes to `Research/raw/remote-recv/<time>-<stage>/` (not tracked by Git): `events.jsonl` (timed events), `frames/NNNN.bin` (the data as received), `decoded.jsonl` (decoded by the product's `RemoteFrameParser`), `summary.json`. On every run, `run.sh` rebuilds our research app and checks that the hashes of its two Swift inputs and builder agree at the two observations before and after compilation. `build-inputs-before.json` and `build-provenance.json` record those inputs, the signed executable, Info.plist, and runner with SHA-256 hashes and sizes, plus the compiler version. Different before/after values prevent launch. This check does not guarantee that the inputs stayed unchanged throughout compilation. The wrapper manages `--out` and `--stage` and rejects additional arguments that override them.

## Ending a run and reading the records

- All communication callbacks, termination, and receive recording use the main serial queue. The terminal state is set before disconnecting; callbacks processed later do not send or append records. A certificate callback after termination receives `false`. The STOP file is polled every 0.5 seconds, so creating the file and establishing the terminal state are not simultaneous.
- A `sent` event means one send API call returned without an error. `sent_initial: true` means both calls met that condition; it does not guarantee acceptance or an ACK from Logic. Serialization or send failure records `send_failed` and ends with `initial_send_failed` and `exit_code: 2`, without entering the receive window.
- `--seconds` starts at the `receive_window` event. Waiting for a baseline or a person's action uses that same time. The limit of 120 seconds does not cover the whole launch; browsing and connection waits precede it. Baseline detection and action markers are operator tasks, not automatic peer features.
- The summary's `exit_code` is the peer's termination result. `run.sh` returns 2 for a missing or invalid summary and returns a nonzero peer result as its own status. The status of `open -W` alone does not establish peer success. A result of 0 does not establish that the baseline arrived or that the experiment succeeded.

For the 2026-10-05 maintenance, an offline build that creates no native peer executed the production lifecycle gate, initial two-send sequence, and frame serialization with a fake transport/recorder across eight cases. Copies with a broken terminal flag or success counter failed the tests. Native callback delivery and actual communication were outside this verification.

## Cautions

- **Never use the name of an existing Logic Remote device** (that would be impersonation to avoid the confirmation dialog).
- After "Connect", Logic **registers the name as a control-surface device** and keeps it in its settings (`ControlSurfaceDevicesDict` in `com.apple.mobilelogic`, and `com.apple.logic.pro.cs`). Removal is expected to be done from Logic's Control Surfaces Setup (not done).
- Run the experiment with only the dedicated project `LogicCLI-Test.logicx` open.
- The bundle is signed ad hoc (`codesign -s -`). Logic's and other apps' signatures are not changed.
