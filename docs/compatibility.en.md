# Supported environments, and what may be released

[日本語](compatibility.md) | [English](compatibility.en.md)

[Back to the specification](specification.md) · [The read contract](observation-contract.en.md) · [The execution contract](execution-contract.en.md) · [The target contract](target-contract.en.md) · [README](../README.en.md)

This page sets out which environment `logicctl` has **actually been checked on**, how far each operation was checked, and what has to be true before it can be called ready to release.
The machine-readable list is [`Research/protocol/support-matrix.tsv`](../Research/protocol/support-matrix.tsv).

## 1. Key points

- The only environment checked is **Logic 12.3.1 (6682), macOS 27.0, arm64**. Any other is not "known to fail"; it is **unverified**.
- `result.compatibility` of `logicctl status` says whether the current combination was verified. **When it cannot tell it is `null`**, neither `false` nor `true`.
- In an unverified environment commands are not stopped. The report exists so that **a result is not taken as verified**. Writes are still confirmed by reading them back.
- Operations checked on the real Logic and areas covered by static analysis only are kept clearly apart (§4). An area covered by static analysis alone is never written as "supported".

## 2. The verified environment

| Item | Value |
|---|---|
| Logic | 12.3.1 (build 6682) |
| macOS | 27.0 (26A5416b) |
| CPU | arm64 |
| Project used in live tests | `LogicCLI-Test.logicx` only (never a production project) |

## 3. `compatibility` in `status`

```json
"compatibility": {
  "verified_profiles": [{"logic_version": "12.3.1", "logic_build": "6682", "macos": "27.0"}],
  "host_macos": "27.0",
  "logic_build_verified": true,
  "macos_verified": true,
  "profile_verified": true,
  "note": "検証済みの組み合わせです。"
}
```

| Field | Meaning |
|---|---|
| `verified_profiles` | The list of verified combinations |
| `host_macos` | This Mac's macOS (major.minor) |
| `logic_build_verified` | Whether Logic's version and build match one on the list. **`null` when Logic is not running or its version cannot be read** |
| `macos_verified` | Whether macOS (major.minor; the patch version is ignored) is on the list |
| `profile_verified` | Whether **the pair of Logic and macOS** is on the list. `false` even if only one matches. `null` means it cannot be judged |

- A matching build number alone does not make a different version verified (**both** the version and the build must match).
- When `profile_verified` is not `true`, read `note` and treat results as reference values.

## 4. Status by area

The vocabulary:

| Status | Meaning |
|---|---|
| `live` | Checked on the real Logic (dedicated project), and tests exist |
| `tested` | Checked by tests (unit, integration; with a stand-in counterpart). Not checked on the real Logic |
| `static` | Static analysis only. No real traffic or behaviour was checked |
| `unconfirmed` | Tried and not achieved, or not confirmed |
| `not_started` | Not started (including waiting for approval) |
| `other` | Follow another owner's document |

Current counts (rows of [support-matrix.tsv](../Research/protocol/support-matrix.tsv)): `live` 17, `tested` 2, `static` 4, `unconfirmed` 2, `not_started` 2, `other` 1 (28 rows).

**All 11 commands of the MCU path** (`status`, `state`, `transport play`, `transport stop`, `track list`, `track get`, `track select`, `track mute`, `track solo`, `track volume`, `track pan`)
were checked on the real Logic ([EXP-CLI-001](../Research/experiments/EXP-CLI-001-v0.1-dod-transcript.txt)).
**The Logic Remote areas are all static analysis only.** A new connection is not made until the user approves it.

The counts are "rows checked / rows of this table". They are not the share of Logic that is understood.

## 5. Side effects (reads included)

"Reading" does not mean having no effect on the screen or the surface.

| Command | Logic's state | Effect on the MCU surface |
|---|---|---|
| `status` | unchanged | none |
| `track list`, `state` | unchanged | **moves the displayed range (the bank) back to the start and on to the end** |
| `track get` | unchanged | moves the bank to reach the position. **Sends a fader touch to read the dB** (the value is not moved) |
| `track select` | **changes the selection; with automatic record-arm on, the record-arm moves too** | moves the bank to reach the position |
| `track mute`, `solo`, `volume`, `pan` | changes the requested value | moves the bank to reach the position |
| `transport play`, `stop` | changes the play state | none |
| with `--expect-name` | nothing is sent on a mismatch | the bank may still move to reach the position |

Moving the bank can also affect what Logic shows (the mixer view) (EXP-MCU-023 confirmed a case where Logic followed by moving the displayed range).

## 6. Older daemons and older CLIs

- A `logicd` left running from an older build silently ignores the newer options (`--idempotency-key`, `--expect-session`, `--deadline-ms`, `--expect-name`, `--backend appleevent`)
  and would run without the safeguard. Before a request that names one of them, `logicctl` asks `status` whether the daemon supports it and, if not,
  returns `daemon_upgrade_required` **without sending anything** ([the execution contract](execution-contract.en.md); test: `test_cli_safety_gate.py`).
- From an older `logicctl` to a newer `logicd`, a legacy request without the added fields passes as before (compatible).
- There is no **version number** for the wire yet. Which features exist is judged from `capabilities` in `status`.
  Introducing a version number is a task for when a promise of future compatibility becomes necessary.

## 7. Release stages, and what the evidence shows now

The stages (the [plan](../Research/plans/agent-ready-roadmap.en.md) §10), their conditions and the current state. **This page does not decide whether to release**; it lays out the facts for that decision.

| Stage | What can be released | Condition | Now |
|---|---|---|---|
| A: basic operations | The existing transport / mixer CLI | unknown, freshness, list failure, target reference, side effects and compatibility checked | unknown, list failure, freshness: `live`. Target reference: rename, add and delete are `live`, **reordering is unconfirmed**, same names cannot be told apart. Side effects: §5. Compatibility: §3. Execution contract: `live` / `tested` |
| B: broad reads | Full names, per-area state, Remote snapshot / watch | initial, deltas, 0/false, reconnect and song switch checked | **Not met** (Remote is static analysis only; no receive experiment) |
| C: production operations | Verified send / plug-in / automation / region operations, one by one | the shared execution gate, several values and targets, no wrong-target writes, save and reload, limits of Undo | **Not met** (not in this table) |
| D: agent operation | MCP, batch, long jobs, autonomy inside permitted scope | schema discovery, conflict / timeout / duplicate / partial failure, artifact checks | **Not met** (no MCP adapter yet) |

### Checks common to every release

- `swift test`, `python3 Tests/integration/*.py` and the tests in `Tools/research-scripts` all pass.
- On the dedicated test project, `python3 Tests/integration/live_smoke.py .build/debug/logicctl --test-project` passes in full ([EXP-MCU-027](../Research/experiments/EXP-MCU-027-live-smoke.en.md); on a project whose names do not match it stops without writing).
- For every released operation, the document gives the environment, input, unit, precondition, read-back, side effects, failure behaviour and evidence (an experiment record or a test).
- The documents exist in Japanese and English, and the links work.
- `verified: true` only when the state read back matches the request. A value that was not obtained, is stale or partial is never read as 0, false or success.
- Nothing known from static analysis alone is written as "supported". What is unconfirmed is written as unconfirmed.
- An unverified environment and an older daemon are never treated as verified, or as success by another route.

## 8. Limits

- Only one environment has been verified. Another macOS, another Logic version or another CPU may behave differently.
- "Checked once" is not "reproduces every time". Most live checks are one or a few runs (see the "Repetitions" of each experiment record).
- `tested` (tests with a stand-in counterpart) does not guarantee the real behaviour. The stand-in copies behaviour that was checked on the real Logic.
