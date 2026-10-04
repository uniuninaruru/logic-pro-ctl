[日本語](EXP-MCU-027-live-smoke.md) | [English](EXP-MCU-027-live-smoke.en.md)

# EXP-MCU-027: First run of the live spot check (`live_smoke.py`)

| Item | Value |
|---|---|
| Date | 2026-10-05 |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (12 strips) |
| Tools | [`Tests/integration/live_smoke.py`](../../Tests/integration/live_smoke.py), `logicctl` (the build at `0a7037d`) |
| Initial state | Twelve track names from `Piano` to `Master`, nothing muted or soloed, volumes 0 dB, pans centred |
| One operation | Run the script once (a fixed command sequence; see the table below) |
| Repetitions | 1 |

## Purpose

The earlier live checks (EXP-CLI-001, EXP-MCU-021 to 026) were done by hand on the spot. This turns the same checks into something that can be **run again**,
so that a later change (a build, macOS, a Logic version) can be tested for regressions by the same procedure.

## Safety

- `--test-project` is required. Also, unless the **track names are as expected** (`Piano`, `Audio`, `Bass`, `Synth`, `Trk05` to `Trk10`, `St Out`, `Master`),
  it **stops with exit status 2 without writing anything**. This was checked by running with wrong expected names (zero write commands).
- Every write carries `--expect-name`. At the end, even after a failure, it restores the state and compares it with the initial one.
- The transcript (commands and JSON) is kept in `Research/raw/live-smoke/` (not tracked by Git).

## Result

All 26 checks passed (about 55 seconds). At the end, names, mute, solo, record-arm, selection, volume and pan matched the initial state.

| Group | Checks |
|---|---|
| Reads (7) | `status` has `compatibility` / `track list` is complete with 12 strips / `identity.scope` is `mixer_position` / names are unique / `track get` with the right name succeeds / with a wrong name `target_mismatch` and no data / track 13 is `no_such_track` |
| Writes (10) | `mute 3` and `solo 2`: ON → resend with the same key `replayed` → OFF / `volume 4` to -6 dB and 0 dB / `pan 5` to -0.25 and 0. All `verified` |
| Contracts (5) | the same key with different content is `idempotency_key_conflict` / a stale `--expect-session` is `precondition_failed` and nothing is sent / a 20 ms deadline is `timeout` and `unknown` / the same key afterwards is `replayed` |
| Execution slot (3) | `status` answers within 1 s during a long write / a same key while running is `request_in_flight` / the first write completes, `verified` |
| Restore (1) | matches the initial state |

## What this script does not check

- Anything that needs GUI actions: rename, add, delete, reorder (EXP-MCU-022 to 025). A regression of the fix that watches the name row (`bankIsKnown`) would not be caught here either.
- Restoring record-arm (it cannot be set from the CLI; a difference is only reported).
- Restarting or reconnecting Logic, and an older `logicd` (covered by the integration test with a stand-in daemon).
- Another macOS or Logic version. In an unverified environment it prints that `profile_verified` is not `true`.

## Hypothesis

Hypothesis: in the verified environment this script passes in full. When the environment or version changes, the checks that fail show the extent of the effect.
Confidence: medium (one run).
Counterexamples: none.
Next validation experiment: run it every time the build or the environment changes. If `Tests/integration/live_smoke.py` fails, read the matching command in `Research/raw/live-smoke/`.
