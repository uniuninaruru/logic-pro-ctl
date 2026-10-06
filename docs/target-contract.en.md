# The target contract — what a track number points at

[日本語](target-contract.md) | [English](target-contract.en.md)

[Back to the specification](specification.md) · [The read contract](observation-contract.en.md) · [The execution contract](execution-contract.en.md) · [README](../README.en.md)

In `track mute 3 on`, **the 3 is a position in the mixer, not an ID**.
After a track is added, deleted or moved, the same number points at a different track.
This page sets out the rules that keep a write from **reaching a different track than the one that was read**.

## 1. Key points

- The track number (`id`) is a position in the mixer order. If the order changes after a read, the number points at another track.
- With **`--expect-name <name>`** the command runs only if the name displayed at that position matches. Otherwise it is `target_mismatch` and **nothing is sent**.
- Always pass the `name` exactly as `track list` / `track get` returned it.
- Where several tracks share a name, the name cannot tell them apart. `identity.name_unique` in `track list` says so.
- The check works **when Logic sends the changed display to the control surface**. A rename, adding a track and deleting a track were confirmed on the real Logic. Reordering is **not confirmed** (§6).

## 2. Usage

```sh
logicctl track list                                   # note the name and identity
logicctl track mute 3 on --expect-name Bass --idempotency-key mute-bass-on-001
```

`--expect-name` works with `track get|select|mute|solo|arm|volume|pan` (not with `track list` or `transport`).
It combines with `--idempotency-key` ([the execution contract](execution-contract.en.md)).

### When it does not match

```json
{"ok": false, "verified": false, "error": "target_mismatch",
 "requested": {"track": 3, "expect_name": "Piano"},
 "observed": {"track": 3, "name": "Bass", "identity_scope": "mixer_position"},
 "message": "トラック 3 の表示名は「Bass」で、期待した「Piano」と違います。…何も送信していません。",
 "execution": {"state": "not_applied"}}
```

- Logic's state is unchanged. The MCU's visible range (the bank) may have moved to reach the position, though.
- What to do next: re-read with `track list` and choose the target again.
- Correcting only the name under the same idempotency key is a different request, so it gives `idempotency_key_conflict`. Use a **new key**.
  (A resend with the same check is `not_applied`, so the same key may run again.)

### When it matches

`result` of the write says what was checked.

```json
"result": {"target": {"track": 3, "name": "Bass", "matched_expected_name": true, "identity_scope": "mixer_position"}}
```

## 3. `identity` in reads

It is attached to each track of `track list` / `track get`.

| Field | Meaning |
|---|---|
| `identity.scope` | `"mixer_position"`: `id` is a position in the mixer |
| `identity.stable_across_reorder` | `false`: changes on reorder, add or delete |
| `identity.name_unique` | `true`: in a complete scan no other track shows the same name / `false`: several tracks show the same name / `null`: not known |

`name_unique` is `null` when:

- the read is `track get` (it reads one track and knows no others), or
- the scan is `complete: false` (an unseen track may share the name).

The displayed name is the short name that fits the MCU's 7-character cell (see also `name_may_be_truncated`).
Names longer than 7 characters are cut. If, say, `Guitar L` and `Guitar R` both display as `Guitar`, they get `name_unique: false` and `--expect-name` cannot tell them apart (how Logic shortens a given name varies; look at the `name` it displays).

## 4. Lifetime of references

| Reference | Points at | Valid until | How a change is detected | Evidence |
|---|---|---|---|---|
| Track number / `id` (MCU) | a position in the mixer | a track is added, deleted or moved | `--expect-name` (when Logic updates the display) | rename: EXP-MCU-022; the rest unconfirmed |
| Displayed name (MCU) | a short name that fits 7 characters | a rename; may be duplicated | comparison only | unit tests, real Logic |
| `observation.session.handshake_generation` | the connection to Logic | Logic reconnects or restarts | `--expect-session` | [the execution contract](execution-contract.en.md) |
| Logic Remote `trackID`, `gindex`, UUID | (identifiers Remote uses) | 4 receptions in one Logic process: `gindex` and UUID stay the same across added tracks; `trackID` follows the position. Reordering, a Logic restart and reopening the song are **unconfirmed** | not used | reception: the open-questions table of [EXP-REMOTE-002](../Research/experiments/EXP-REMOTE-002-offline-state-replay.en.md); static: [SA-REMOTE-STATE-001](../Research/static-analysis/SA-REMOTE-STATE-001.en.md) |

A reference whose lifetime is unconfirmed is not treated as confirmed. `logicctl` makes a contract only of what it could confirm: **a position and a displayed name while connected**.

## 5. What is guaranteed and what is not

Guaranteed:

- When `--expect-name` does not match, **nothing is sent** (`target_mismatch`; unit tests, real Logic).
- When a write succeeds, `result.target` carries the **name that was checked**.
- Through `logicctl`, an older `logicd` never silently ignores `--expect-name`. `logicctl` asks `status` first and, if the daemon does not support it,
  returns `daemon_upgrade_required` and **sends nothing** (the same for `--idempotency-key`, `--expect-session` and `--deadline-ms`).

Not guaranteed (limits):

- **Swapping two tracks that display the same name** is not detected. Two tracks with one name get `name_unique: false`, and the check passes with that name at either position (confirmed on the real Logic: EXP-MCU-025).
- A change for which Logic does not update the display is not detected. The check only compares with what the surface shows.
- The MCU LCD can show only short ASCII names. Non-ASCII characters may not be displayed ("オーディオ 8" appeared as `8`).
  For the check, use the displayed `name` as it is; it will not equal the original name.
- The song (project) name cannot be read from the MCU. After a switch to another song, tracks with the same names still match.
  A switch that makes Logic reconnect is detected by `--expect-session`. That option confirms the **connection generation** only; it does not detect a reorder, a rename or a swap of same-named tracks inside one connection.
- Hierarchy (folders, stacks), instruments, inserts and plug-ins are outside this contract (the MCU does not expose them).
- A person acting **between** the read and the write cannot be prevented. The check runs just before the write, after the position has been reached.

## 6. Status of confirmation

| Change | Confirmed on the real Logic | Unit test |
|---|---|---|
| Renaming a track (strip on the display) | **Confirmed**: EXP-MCU-022 (`Zed5`; the old name gives `target_mismatch`) | yes |
| Two tracks with the same name | **Confirmed**: EXP-MCU-025 (both `name_unique: false`; the check passes with the shared name) | yes |
| Adding a track | **Confirmed**: EXP-MCU-023 (all three checks against the layout from before the add gave `target_mismatch`). Logic also moves the displayed range itself | yes |
| Deleting a track | **Confirmed**: EXP-MCU-023. A defect that trusted a stale bank position after a delete was found and fixed (below) | yes |
| Reordering tracks | **Not confirmed**: a reorder could not be produced (dragging, the reorder menu; no change in 8 attempts in all) | yes (assuming Logic updates the display) |
| Renaming a strip that is not on the display | Not confirmed (moving the bank should rewrite the display) | — |

Unconfirmed rows are not described as "detected" until they are checked on the real Logic. The unit tests only show that, **if Logic updates the display**,
this check detects the change.

In a real delete, Logic rewrote only a differential of the name row and did not send the signal that announces a bank move (the colour sysex) (MIDI record: EXP-MCU-024).
The earlier `logicd` then trusted the bank position from before the delete and read the non-existent track 13 as `Master`.
Now, if the name row differs from the one recorded when the position was set, the position is not trusted and is established again (confirmed on the real Logic: it gives `no_such_track`).

## 7. Evidence

- `Tests/LogicCoreTests/TargetIdentityTests.swift` (rename, swap, delete, add; nothing sent for every command; duplicate names; truncation; argument validation; relation to idempotency keys)
- `Tests/integration/test_cli_safety_gate.py` (a request with a safeguard is never sent to an older daemon)
- [EXP-MCU-022](../Research/experiments/EXP-MCU-022-rename-reaches-surface.en.md) (real Logic: a rename reaches the surface)
- [EXP-MCU-023](../Research/experiments/EXP-MCU-023-add-delete-reach-surface.en.md) (real Logic: adds and deletes reach it; the stale-bank defect after a delete and its fix)
- [EXP-MCU-024](../Research/experiments/EXP-MCU-024-trace-add-delete.en.md) (real Logic: the MIDI of an add and a delete; a delete sends no colour sysex)
- [EXP-MCU-025](../Research/experiments/EXP-MCU-025-same-name-tracks.en.md) (real Logic: two tracks with one name get `name_unique: false`; the check passes with the shared name)
