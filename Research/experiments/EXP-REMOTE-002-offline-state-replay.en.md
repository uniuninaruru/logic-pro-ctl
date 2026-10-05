[日本語](EXP-REMOTE-002-offline-state-replay.md) | [English](EXP-REMOTE-002-offline-state-replay.en.md)

# EXP-REMOTE-002: rebuild Logic's mixer state offline from the saved reception (EXP-REMOTE-001)

| Item | Value |
|---|---|
| Date | 2026-10-05 (offline; nothing was connected to or sent to Logic) |
| Logic version | 12.3.1 (6682) (the Logic of the recording) |
| macOS version | 27.0, arm64 |
| Logic Remote version | Not applicable |
| Test project | LogicCLI-Test.logicx (the project of the recording; not touched now) |
| Initial state | The reception of [EXP-REMOTE-001](EXP-REMOTE-001-receive-initial-state.en.md) (`Research/raw/remote-recv/20261005-094234-e1/`, not tracked by Git) |
| The one operation | Feed the recorded frames, in arrival order, to the research state builder `Tools/research-scripts/remote_state.py` |
| Expected change | The state of 12 strips is built, with 0 inconsistencies (identifier mismatches, broken `/ati` and so on) |
| Repetitions | Any number of times on the one recording, with the same result (deterministic). **The recording itself is a single reception** |

## The builder's contract

The same contract is also implemented on the product side in Swift: `Sources/LogicCore/Backends/Remote/RemoteState.swift` (`RemoteStateBuilder`). It only takes decoded messages and returns state; it is not wired to any connection, sending or the CLI. Tests: `Tests/LogicCoreTests/RemoteStateTests.swift` (26; they also check that JSON string keys and archive number keys, and a MAZP-archived `/sti` and a plain one, give the same state, and, when the recording is on this machine, that the real data gives the same numbers as the Python tool).

The port found one mistake in the Python tool, now fixed: track values (`r`, `ip`) were carried over by `track_id` alone, but `track_id` follows position (EXP-REMOTE-001), so after a reorder the values landed on another strip. Now they are carried only while the `track_id` stays with a strip of the same UUID.

The Python version is a research tool that the product (`Sources/`) does not depend on; the Swift version is a pure state builder inside the product. Neither provides connection or sending functionality. Like the [read contract](../../docs/observation-contract.en.md), **it does not treat what it does not know as known.**

| # | Rule | Why |
|---|---|---|
| 1 | **A value not received is `null`.** 0 and `false` appear only when Logic sent them. Each value carries the frame it came in | Deltas carry only changed fields. Reading an absence as 0 / off gets mute and volume wrong |
| 2 | **Four identifiers are kept apart**: `gindex` (the strip's key; the keys of `g` in `/gtFaderData`), position (the order in the latest `/ati`; changes on a reorder), `track_id` (`BgTrackInfoTrackIDKey`; the keys of `t` in `/gtFaderData`), and the UUID. Strip values follow `gindex`. **Nothing is carried over by position** | In EXP-REMOTE-001 `gindex` was in creation order while position and `track_id` followed the current order |
| 3 | `/ati` is treated as **a whole snapshot**. A broken one (schema violation, columns of different length, a repeated `gindex`, `track_id` or UUID) is **refused and the previous state kept**. An identical resend is a "duplicate", not a change | A partly broken table must not break the strip mapping |
| 4 | A changed UUID under the same `gindex` is **another strip**: its values go back to `null`. A strip that leaves `/ati` loses its values and starts from `null` if it comes back | What cannot be shown to be the same is not treated as the same |
| 5 | `/gtFaderData` is **a partial delta**: only the fields present are updated; absent fields keep their value (or `null`). Values for a `gindex` / `track_id` the current `/ati` does not list are kept as **orphans** and reported, and attached if a later `/ati` lists them | No value is lost if arrivals are out of order, and none is attached silently |
| 6 | `/sti` is tied to a strip by its index into the latest `/ati`, and name and `tn` are checked, **again on every new `/ati`**. If they do not match it is left unattached (`gindex` `null`) and reported. `NoTrackSelected` means "no selection", not "unknown" | In the real data `/sti` arrived **before** the first `/ati`. After a reorder an old `/sti` can point at a different strip |
| 7 | Logic sends no end-of-initial-send marker ([SA-REMOTE-STATE-001](../static-analysis/SA-REMOTE-STATE-001.en.md) §3). **`complete` is never `true` (it is `null`).** The number of known fields (coverage) is given instead; full coverage does not mean complete | The receiver cannot know whether more deltas will come |
| 8 | Within one dictionary `/ati` is applied first (the other addresses refer to it). Logic does not define the order of keys within a dictionary | One result for the same content |

## Observations (replaying the recording)

- **0 inconsistencies.** Events: `/ati` applied 1, duplicate 1; strips added 12; `/gtFaderData` applied 1; `/sti` applied 1, duplicate 1; counts applied 2, duplicate 2.
- The rebuilt state: 12 strips. All 36 fader fields (`vL`, `s`, `m`) and all 24 track fields (`r`, `ip`) are known. The counts (`/allTrackCount`, `/trackCount` = 12) agree with `/ati`. `complete` is `null`.
- **`/sti` arrived before the first `/ati`** (frames 456 and 479). It was re-checked when `/ati` arrived and tied to position 3 (`gindex` 116, Trk08); name and `tn` agree.
- **An intermediate state**: at frame 470 there are 0 strips and not one fader value is known (`null`). A client reading values as 0 at that point would wrongly show every strip as unmuted at minimum volume.
- Identifiers: for positions 1 to 12 the `gindex` values are 88, 100, 116, 92, 96, 124, 112, 108, 104, 120, 80, 84 (creation order, not position order). `track_id` follows position (`0x40001` to `0x4000b`, Master `0x8000f`). All 12 UUIDs differ.
- The recording **holds no deltas** (Logic was not operated while receiving). `/gtFaderData` arrived once, and the second `/ati` equalled the first. Deltas, reorders and orphans were checked with synthetic tests only.

### The schema against the recording

[`logic-remote-state-coverage.tsv`](../protocol/logic-remote-state-coverage.tsv) lists, for the 14 addresses the schema defines (`/ati` per column, `/gtFaderData` and `/sti` per field), how many arrived, a summary of the values, the schema result, and whether a change was seen. Strings (track names, UUIDs, locale and so on) are given **as a count only**; no value is listed.

- All 14 addresses arrived and all passed the schema.
- **Everything that arrived more than once had the same content** (`changed_seen` is `no` throughout). Nothing is known about how stable the values are or how they change.
- The ranges seen are narrow: `/ati` `t` 1, 2, 5, 6; `nc` 1, 2, 6; `p` −1, 0. In `/gtFaderData` `vL` has one value (0 dB), `s`, `m` and `ip` only 0, `r` 0 and 64.

[`logic-remote-captured-addresses.tsv`](../protocol/logic-remote-captured-addresses.tsv) lists every address received, folded into 116 patterns with digits as `{n}` (no values). The schema covers 14 of them; `/cs/…` (8 control-surface strips), `/mixer/io/…`, `/mixer/plugins/…`, the meters and others are not in the schema yet.

### `/cs/…` (the control-surface feedback) against the static assignment table

[`logic-remote-cs-feedback.tsv`](../protocol/logic-remote-cs-feedback.tsv) lines up the received `/cs/…` with the default assignment table of the Logic Remote plug-in ([`cs-assign-remote.tsv`](../protocol/cs-assign-remote.tsv), SA-002), folded into templates with the trailing number (the strip) removed.

- **All 33 templates received are in the assignment table.** No address outside the table arrived.
- 5 templates of the table did not arrive: `/cs/mixer/mutereset`, `/cs/mixer/soloreset`, `/cs/mixer/volume`, `/cs/transport/track+`, `/cs/transport/track-`. From their names and table values (`kind` 9 with `flags` 3, `kind` 1) they look like **buttons the Remote sends to Logic, which Logic does not echo** (hypothesis; confidence medium).
- Values: `volume`, `trimvolume` and `mastervolume` are **90/127** at 0 dB, `pan` **64/127** at centre. In the assignment table `param` is 7 for volume and 10 for pan (the MIDI control-change numbers for volume and pan). This matches the top byte 90 of `vL` in `/gtFaderData`. So the `/cs` volume looks like **Logic's 7-bit volume (90 = 0 dB) divided by 127** (hypothesis; confidence medium; one point at 0 dB).
- **The scale differs from the MCU's**: the MCU's 14-bit fader is about 12440 at 0 dB (between −0.4 dB = 12283 and +0.2 dB = 12523 in [`mcu-fader-calibration.tsv`](../protocol/mcu-fader-calibration.tsv); 0.759), which is 97 when cut to 7 bits, not 90. The two routes' values must not be converted into each other by dropping bits.
- The 33 templates received were added to the schema (`logic-remote-state.schema.json`) as `patternProperties`: faders are numbers from 0 to 1, buttons integers, display text strings; only the faders and the bank offset have a range. Every received message passes, and tests show values of the wrong type are refused.
- `/cs` covers only **8 strips** (8 from `/cs/bankLeftOffset` = 0), a different range from `/ati` and `/gtFaderData`, which cover all 12. Sends are 64 addresses with two-digit numbers (8 × 8); which digit is the strip and which the send slot is unconfirmed.

## Tests

`Tools/research-scripts/test_remote_state.py` (37 tests) checks each rule of the contract on synthetic message sequences.

- Zero and absence: an `m` that was never sent stays `null` (not 0); a received 0 is 0; a partial delta does not erase other fields.
- Broken `/ati`: columns of different length, a missing column, and a repeated `gindex`, `track_id` or UUID are refused, and the previous state is kept.
- Duplicates: a resent `/ati` or `/sti`, and `/gtFaderData` with the same value, are not counted as changes.
- Identifiers: values follow `gindex` through a reorder; a new UUID is another strip; a strip that leaves and returns starts from `null`.
- Mismatches: an unknown `gindex` / `track_id` is reported as an orphan and attached by a later `/ati`; a schema-invalid `/gtFaderData` changes nothing.
- Selection: an `/sti` before `/ati` is attached later; an old `/sti` after a reorder is not attached and is reported.
- Completeness: `complete` is `null` even when every field is known.
- `/cs` matching: numbered addresses fold into the table's templates; "in the table but not received" and "received but not in the table" are told apart.
- Real data (only when the recording is on this machine): 0 inconsistencies, 36 / 24 fields, the second `/ati` is a duplicate, and right after the first `/ati` every fader value is `null`.

That the tests catch errors was seen when a version without the selection re-check failed the real-data test (that failure is how the early `/sti` was noticed).

## Boundaries found by independent review and their fixes

The first Swift version (`9ed170a`) passed its 22 existing tests and Python passed 36, but separate synthetic inputs through **binary plist → the product frame decoder → the builder** reproduced four gaps outside those tests.

| Input / boundary | Problem in the first version | Corrected behavior |
|---|---|---|
| Empty `/ati` after resolving a selection | Both versions kept the removed strip's `gindex` / position in the selection | Clear the old binding and report a mismatch. Distinguish this from pending selection before the first `/ati` |
| Missing or incorrectly typed fields inside an `/ati` colour dictionary | Swift replaced the previous valid state with the malformed whole list | Check known required colour keys and data / JSON string types; reject the whole invalid list and preserve the previous state |
| Missing required fields or incorrect types in `/sti` | Swift applied an invalid selection message | Validate required fields, types and known bounds before updating, including `NoTrackSelected`. Preserve the previous selection on rejection |
| Deltas outside known numeric constraints or negative counts | Swift stored `r=2`, `ip=5000` and count `−1` as known values | Reject according to the current schema's enum / bounds. This does not establish new value semantics |

After the fixes, all 26 Swift tests, 37 Python tests and the nine independent cases pass. Integration also passes the full 147-test Swift suite and 70 related Python state/schema/capture tests. The real-data regression uses only the fixed EXP-REMOTE-001 recording, so a new experiment is not compared to the initial capture's fixed expected values. If the reference recording is absent, only those real-data tests skip.

These are **offline checks** with malformed inputs, not live observations that Logic sent those inputs. Continue comparing the saved initial capture to ensure valid reception is still accepted.

**A separate design limit:** An orphan delta carrying only an ID and no UUID cannot distinguish a new strip's early data from a removed strip's late delta when a subsequent `/ati` contains the same ID. Both versions follow the current contract of attaching orphans later. This review did not observe such late deltas in real traffic. UUID checks on lists do not guarantee that this ambiguity is resolved. This state alone is not yet proof of target identity for product writes.

## Hypothesis

Hypothesis: **`BgTrackInfoIndexKey` of `/sti` is the 0-based position in `/ati`.**
Confidence: medium (one value from one reception; index 2 matched Trk08 at position 3 in name and `tn`).
Evidence: this replay.
Counter-example: for another selection (Stereo Out, Master, several tracks) the index and the `/ati` position differ.
Next experiment: change the selection while receiving (an E3 candidate; needs separate approval).

## Unconfirmed

| Item | State |
|---|---|
| Whether deltas (volume, mute, selection changes) build up as this contract says | Synthetic tests only; the real data holds no deltas |
| Whether `gindex` stays the same across a reorder within one session | Unconfirmed (EXP-REMOTE-001 hypothesis 2) |
| How `/ati` is replaced on a song switch (renumbered `gindex`) | Unconfirmed. Rule 4 treats a different UUID as a different strip |
| Stability (whether the same state keeps being sent with the same values) | Unconfirmed; one recording only |
| What the values of `m`, `s`, `r`, `ip` mean | Unresolved (kept as raw values, not interpreted) |

## Reproduce

```sh
python3 Tools/research-scripts/remote_state.py replay Research/raw/remote-recv/<time>-e1 [--at <frame number>]
python3 Tools/research-scripts/remote_state.py coverage Research/raw/remote-recv/<time>-e1 > Research/protocol/logic-remote-state-coverage.tsv
python3 Tools/research-scripts/remote_state.py addresses Research/raw/remote-recv/<time>-e1 > Research/protocol/logic-remote-captured-addresses.tsv
(cd Tools/research-scripts && python3 -m unittest test_remote_state)
```
