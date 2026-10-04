[日本語](EXP-MCU-026-execution-contract-live.md) | [English](EXP-MCU-026-execution-contract-live.en.md)

# EXP-MCU-026: Checking the execution contract on the real Logic — a missed deadline, a resend with the same key, and a wrong generation

| Item | Value |
|---|---|
| Date | 2026-10-05 (the daemon log is UTC 2026-10-04 15:47) |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx |
| Initial state | `logicd` restarted with the new build and connected (generation 4). Track 2 at 0 dB, not muted |
| One operation | A, B and C below are independent checks, each changing **one condition** |
| Repetitions | 1 each |

## Checks and observations

Behaviour of [docs/execution-contract.en.md](../../docs/execution-contract.en.md) that had so far been confirmed only by tests (with a stand-in counterpart) was checked on the real Logic.

### A. A write with too short a deadline

`track volume 2 -6 --idempotency-key exp026-vol --deadline-ms 30`

| Observation | Value |
|---|---|
| Response | `ok: false`, `error: timeout`, `execution.state: unknown`, message "it may have been executed; the result is unknown" |
| Daemon log | `exec=unknown error=timeout ms=35` (answered right after the 30 ms deadline) |

### B. A resend with the same key

The same request with the same key was sent about 0.8 seconds after A, and again 4 seconds later.

| Observation | Value |
|---|---|
| First resend | `ok: true`, `verified: true`, `execution.state: replayed`, `observed: {fader_value: 9874, volume_db: -6}`. The log has `exec=replayed ms=0` |
| Second resend | the same, `replayed`, `ms=1` |
| Log lines | There is no `completed` line for this key. The only execution line is the one of A (`unknown`) |

- The write of A went on in the background after the response and **seems to have ended confirmed, so the record became `completed`** (the first resend returned a `verified: true` result).
- The resends took 0–1 ms, so nothing was sent to Logic. **No MIDI was recorded**, though, so "sent only once" is an inference from the response time and the number of log lines.
- By the time of the first resend the background write had already finished. `request_in_flight` (the same key still running) did not occur, so that path was not checked on the real Logic.

### C. A write with a wrong generation

`track mute 2 on --expect-session 99999 --idempotency-key exp026-pre` (the current generation is 4)

| Observation | Value |
|---|---|
| Response | `ok: false`, `error: precondition_failed`, `execution.state: rejected`, "expected generation 99999, current 4" |
| Log | `exec=rejected error=precondition_failed ms=0` |
| Result | Track 2 stayed unmuted (checked with `track get 2`) |

### Clean-up

`track volume 2 0` (a new key) put the volume back to 0 dB. `verified: true`. The whole state is as before the experiment.

## Hypothesis

Hypothesis: the execution contract (a missed deadline gives "unknown", a resend with the same key is not run again, a wrong generation is refused before sending) works on the real Logic as it does in the tests.
Confidence: medium to high (one run each; A→B confirmed by the combination of responses and the record).
Evidence: the tables above and `logicd`'s log. It also agrees with the unit tests (`WriteExecutorTests`).
Counterexamples: none.
Not verified: `request_in_flight` (the same key still running), a full queue (`queue_full`), reconciliation across a `logicd` restart, and a matching `--expect-session` with the state changed inside the connection (outside what the contract guarantees).
Next validation experiment: confirm with the MIDI of `logicd --trace` that the write was sent only once. To produce a running same key, resend during a slow write (timing has to be controlled).

## Consequence for logicctl

- No change in behaviour. `--expect-session` in [support-matrix.tsv](../../Research/protocol/support-matrix.tsv) moved from `tested` to `live` (the refusal on a mismatch was confirmed on the real Logic).
