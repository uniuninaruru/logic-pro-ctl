[日本語](README.md) | [English](README.en.md)

# Research peer (receive-only, Logic Remote)

A small macOS app that **only receives**, used within the approved scope of PLAN-05 ([approval brief](../../Research/plans/PLAN-05-approval-brief.en.md)). It is not part of the product (`Sources/`). Results: [EXP-REMOTE-001](../../Research/experiments/EXP-REMOTE-001-receive-initial-state.en.md).

| Stage | What it does | What it sends |
|---|---|---|
| `e0` | Browse for the `apple-lgremote` advertisement and record it. No invitation | nothing |
| `e1` | Invite under its own name (default `logicctl-research-peer`). A person presses "Connect" in Logic's dialog. Once connected, receive for `--seconds` (at most 120) | only `/protocolVersion = 10` and `/jsonSupport`, once each. Trying to send anything else stops the process |

```sh
Tools/remote-research-peer/build.sh                       # .build/remote-research-peer/LogicctlResearchPeer.app
Tools/remote-research-peer/run.sh e0 --seconds 15
Tools/remote-research-peer/run.sh e1 --seconds 60 --target "<the name found by e0>"
touch Research/raw/remote-recv/<time>-e1/STOP              # stop early
python3 Tools/research-scripts/remote_capture.py report Research/raw/remote-recv/<time>-e1
```

Output goes to `Research/raw/remote-recv/<time>-<stage>/` (not tracked by Git): `events.jsonl` (timed events), `frames/NNNN.bin` (the data as received), `decoded.jsonl` (decoded by the product's `RemoteFrameParser`), `summary.json`.

## Cautions

- **Never use the name of an existing Logic Remote device** (that would be impersonation to avoid the confirmation dialog).
- After "Connect", Logic **registers the name as a control-surface device** and keeps it in its settings (`ControlSurfaceDevicesDict` in `com.apple.mobilelogic`, and `com.apple.logic.pro.cs`). Removal is expected to be done from Logic's Control Surfaces Setup (not done).
- Run the experiment with only the dedicated project `LogicCLI-Test.logicx` open.
- The bundle is signed ad hoc (`codesign -s -`). Logic's and other apps' signatures are not changed.
