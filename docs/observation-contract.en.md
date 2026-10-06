# The read contract — unknown, partial and stale are never success

[日本語](observation-contract.md) | [English](observation-contract.en.md)

[Back to the specification](specification.md) · [README](../README.en.md)

`logicctl` reads (`status`, `state`, `track list`, `track get`) return not only a value but
**how far that value can be trusted**. An agent can treat an empty list, a `false` or a short
list as established fact. What could not be confirmed is reported as not confirmed.

## 1. Three promises

| Promise | Meaning |
|---|---|
| Unknown is `null` | A value Logic has not reported in this connection is `null`, never `false` or `0` |
| A list is complete only when proven | A scan that could not confirm the end is never an empty or shorter success |
| No stale state | When Logic redoes the connection, the previous connection's names, faders and LEDs are discarded |

## 2. `observation`

A read response carries `observation` next to `result`. Write responses do not.

```json
{
  "ok": true,
  "result": [ ... ],
  "observation": {
    "source": "mcu",
    "scope": "mixer_strips",
    "complete": true,
    "observed_at": "2026-10-02T00:14:16Z",
    "session": {"logic_pid": 37546, "handshake_generation": 4,
                "handshake_at": "2026-10-02T00:14:10Z", "bank_offset": 4},
    "strips": 12, "bank_steps": 4, "attempts": 1,
    "end": "channel_right_and_bank_right_silent"
  }
}
```

| Field | Meaning |
|---|---|
| `source` | The path the value was read through. Currently `mcu` |
| `scope` | What was read: `status`, `mixer_strips` (all strips) or `mixer_strip` (one) |
| `complete` | Whether that scope was read to the end. A `false` result is not the whole truth |
| `observed_at` | When the read finished (UTC) |
| `session` | The connection the values belong to: Logic process, connection generation, connect time, current bank position |
| `strips` / `bank_steps` / `attempts` / `end` | Breakdown of a list scan (list and `state` only) |

When `session.handshake_generation` changes, earlier values belong to another connection.
Together with `observed_at` it is the freshness hint when you store and compare results.

## 3. `null` per track

Each track in `track list` / `track get` / `state` carries two arrays:

| Array | Meaning | Example |
|---|---|---|
| `unknown` | Logic has not reported the value yet; returned as `null` | `["mute", "selected"]` |
| `unavailable` | The strip has no such value; returned as `null` | `["pan"]` on Master |

- `solo`, `selected`, `rec_armed` and `mute` are `true` / `false` only once Logic has reported the LED.
- While any solo exists the mute LEDs blink and the state cannot be told, so `mute` is `null` and listed in `unknown`.
  "A solo exists" is decided from the visible strips' solo LEDs and the global solo indicator.
- `volume_db` is derived from Logic's fader value. Without a value it is `null` and listed in `unknown`.
- `name` is read from the MCU display, so it is **at most 6 characters, ASCII only**.
  With 6 or more characters `name_may_be_truncated: true` is returned.
  It can also be stale, for example right after undoing a rename.
- `id` is a **position in the mixer**; after a track is added, deleted or moved it points at a different track. A name is not an identifier either (names can repeat).
  The `identity` of each track says so. To keep a write from reaching the wrong track, use `--expect-name` ([the target contract](target-contract.en.md)).

`transport.playing` / `transport.recording` in `status` and `state` work the same way.
Until Logic reports the play and record LEDs they are `null`, not `false`.

## 4. When a list or `state` fails

`track list` and `state` are `ok: true` **only when they can prove every strip was read**.

1. Return the bank to the start (Bank Left until nothing moves). If that fails: `bank_home_failed`.
2. Read while stepping with Channel Right.
3. Confirm the end: Channel Right gets no reaction **and a different button (Bank Right) gets none either**.
   Silence alone cannot be told apart from a lost key press.
4. If Logic moved the bank itself (more colour updates than expected, or a move while reading),
   discard what was read for that bank and start over. There is one retry.

If this cannot be proven the result is `ok: false`, `error: "scan_incomplete"`, with what was read in `result`.
`observation.problem` gives the reason.

| `problem` | Meaning |
|---|---|
| `end_not_confirmed` | The end could not be confirmed; the list stops early |
| `bank_moved_externally` | Logic moved the bank during the scan, so the numbering cannot be trusted |

With `bank_home_failed` or `scan_incomplete`, `selected_track` in `state` is `null` and does
**not** mean "nothing selected". Only a complete scan that finds no selection makes `null` mean "none".

Reads take time because each end check waits 0.8 s for silence.
Measured on Logic 12.3.1: `track list` about 4 s, `track get` 1–4 s.

## 5. "Already in that state" for writes

A write that can be skipped is skipped only when the **state Logic reported** equals the request.

- `transport play` / `stop`: wait (up to 1 s) until both the play and record LEDs have been received in this connection.
  If not, `readback_unavailable` and nothing is sent. An extra Stop would move the playhead to the start.
- `track mute n off` etc.: if the LED is unreported the write is not skipped; the LCD text after the press (`Muted` / `--`) confirms it.

## 6. What is confirmed, and its limits

- Verified on Logic 12.3.1 (6682), macOS 27.0, MCU path.
- The completeness proof rests on the observation that neither Channel Right nor Bank Right gets a reaction for 0.8 s.
  If Logic is delayed beyond 0.8 s under load there remains room to mistake that for the end.
- The proof assumes **one** unit on the port. When Logic drove two Mackie Control units on the same port, the two showed every strip, the buttons got no reaction, and the result was a false complete list ([EXP-MCU-029](../Research/experiments/EXP-MCU-029-two-units-on-one-port.en.md)). A whole-display write that lands on different names on display without a handshake in between is now `surface_conflict`, and reads and writes are refused (checked again after each command). A second unit that sends its dump alone later may go undetected.
- One colour update per bank move is an assumption from recorded behaviour (EXP-MCU-020).
  When it does not hold the scan fails safe as `scan_incomplete`.
- Name identity (same names, reordering, deletion) is outside this contract. It is handled in [PLAN-08 of the roadmap](../Research/plans/agent-ready-roadmap.en.md).

Evidence: [EXP-MCU-020](../Research/experiments/EXP-MCU-020-banking.en.md), [EXP-MCU-021](../Research/experiments/EXP-MCU-021-last-strip-db-text.en.md).
Failures are reproduced by tests against a fake surface modelled on real Logic behaviour
(`Tests/LogicCoreTests/MCUObservationTests.swift`).
