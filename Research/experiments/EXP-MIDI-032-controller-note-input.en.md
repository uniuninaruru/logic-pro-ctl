# EXP-MIDI-032: Record eight notes from a generic CoreMIDI virtual source

[Machine-readable evidence and source hashes](EXP-MIDI-032-controller-note-input.json)

A and B recorded the exact eight-note pitch order, channel and velocity through a generic CoreMIDI virtual source. B's exported notes closely follow its actual packet timestamps, but the sender failed its planned durations and onset spacing. This establishes the observed research path for these notes; it does not establish accurate musical scheduling or a production CLI MIDI feature. C was not run and is deferred under the user's shift to command-driven region editing.

**日本語要約:** 汎用CoreMIDI仮想入力から8音の音高・順序・チャンネル・ベロシティを記録できた。Bの実送信時刻と書き出し結果の相対誤差は1ms未満だが、予定した音長と間隔は送信側で大きくずれた。小節同期、テンポマップ対応、製品CLI機能、未実施のCの成功は主張しない。

| Field | Recorded value |
|---|---|
| Date/time | A: 2026-10-07 15:15 UTC / 2026-10-08 00:15 JST; B: 15:36 UTC / 00:36 JST |
| Logic | Status reports 12.4 / 6707; [installed identity model](../static-analysis/binary-identity-12.4-6707.json) records framework SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda` |
| macOS | Status reports 27.0 |
| Logic Remote | Not used |
| Test project | `LogicCLI-Test.logicx`, operator-supplied provenance; no independent GUI/project inspection in this curation |
| Initial state | Selected MCU mixer position 13, label `StdGrn`; arm command verifies already armed and sends no REC press; transport initially stopped; fixed 120 BPM visible in saved AX text |
| One operation | Record the eight-note sequence from `logicctl-note-input`, a `MIDISourceCreate` virtual source using `MIDIReceived`, with existing MCU controls |
| Expected change | A native recorded region containing pitches `[60,62,64,67,64,62,60,55]`, channel 0, note-on velocity 90, planned 500 ms onset spacing and 375 ms durations |
| Repetitions | One A and one B; timestamp and logging conditions differ, so this is not a clean one-variable causal isolation |
| Readback | Native Logic export to SMF for inspection only; no SMF was supplied as note input |

## Observations

The saved sender readiness records show a generic virtual source, no virtual destination and no created port connection. Existing MCU select/arm controls targeted position 13. Recording was started with the MCU REC button (`90 5F 7F`, `90 5F 00`) through `debug.mcu`; that write remains `verified:false`. Independent [A recording status](../raw/gui/midi-controller-032/recording-readback.json) and [B recording status](../raw/gui/midi-controller-032/recording-readback-b.json) report both `playing:true` and `recording:true`.

The immediate stop replies verify the requested `playing:false` while still reporting `recording:true`. Later independent [A state](../raw/gui/midi-controller-032/state-after-record.json) and [B status](../raw/gui/midi-controller-032/state-after-record-b-status.json) confirm both `playing:false` and `recording:false`. The transient stop reply is retained; settled transport status is the stopping evidence.

No network or IPC mechanism beyond these existing controls is claimed. The note-input path is the generic CoreMIDI virtual source. Native MIDI exports appear only after recording as readback. Their export provenance is supplied by the live operator; this offline curation did not observe the GUI, and the guarded `export-b.txt` message alone would not establish a completed export.

| Result | A | B |
|---|---|---|
| Exact pitch order | `[60,62,64,67,64,62,60,55]` | Same |
| Channel / note-on velocity | 0 / 90 for all 8 | Same |
| Starts / ends | 8 / 8, balanced, positive durations | Same |
| Native export | Type 0, one track, PPQ 480 | Same |
| Source timestamp | 0; invalid as a substitute for now in `MIDIReceived` | Mach host time sampled before `MIDIReceived` |
| First-aligned onset mismatch | 17.972750 ms against post-call log proxy | 0.903875 ms against packet timestamps |
| Duration mismatch | Maximum 194.669667 ms against post-call log proxy | Maximum 0.745833 ms against packet timestamps |
| Planned musical timing | Not established; confounded | Failed: maximum TX duration deviation 147.636917 ms, first-aligned onset drift 122.129042 ms |

A's sixth note, pitch 62, has duration 190 export ticks versus 376.882881 ticks predicted by its post-call log. Zero packet timestamps and post-call TX logging prevent attributing that difference to Logic. See the [A audit](../raw/gui/midi-controller-032/readback-report.md) and [comparison](../raw/gui/midi-controller-032/readback-comparison.json).

B's sub-1 ms comparisons are relative timing agreement between the actual packet timestamp and exported note positions/durations. They are not receiver-processing latency, absolute onset synchronization or agreement with the requested musical plan. B's final note-off is 186.468833 ms later than its planned offset when measured from the gate baseline; that value includes the unlogged dispatch-base/startup gap. Duration deviations do not depend on first-onset alignment. The longest measured `MIDIReceived` call is only 0.034584 ms, so those call durations do not account for the large sender timing deviation; its cause remains unproven. See the [B audit](../raw/gui/midi-controller-032/readback-report-b.md) and [comparison](../raw/gui/midi-controller-032/readback-comparison-b.json).

The absolute first onsets—A at 22573 ticks and B at 10195 ticks—were aligned away. This experiment therefore does not verify a chosen start bar, transport-to-input synchronization or absolute recording latency. Millisecond conversion uses the observed fixed 120 BPM and PPQ 480 (960 ticks/s); it does not exercise a tempo map. No arbitrary jitter pass threshold was declared.

## Apple timestamp contract

Apple documents that virtual sources created with `MIDISourceCreate` submit generated input through [`MIDIReceived`](https://developer.apple.com/documentation/coremidi/midireceived%28_%3A_%3A%29), whose specific contract makes the source responsible for proper timestamps and does not treat zero as now. [`MIDITimeStamp`](https://developer.apple.com/documentation/coremidi/miditimestamp) uses Mach host ticks. Nanoseconds must be converted with the timebase ratio or `AudioConvertNanosToHostTime`; [Apple's architectural guidance](https://developer.apple.com/documentation/apple-silicon/addressing-architectural-differences-in-your-macos-code) warns against assuming Mach ticks equal nanoseconds.

Apple explicitly describes future-delivery scheduling for [`MIDISend`](https://developer.apple.com/documentation/coremidi/midisend%28_%3A_%3A_%3A%29) to destinations. That promise does not establish how Logic handles a future-timestamped source batch through `MIDIReceived`. The local SDK paths and line evidence are in the [timestamp semantics note](../raw/gui/midi-controller-032/timestamp-semantics.md). Strict zero-leeway sender scheduling and a possible future batch were not live-validated in C.

## Hypotheses and next scope

**Hypothesis — proper timestamps improve correspondence to actual input timing.** Confidence: medium. Apple’s API contract and the A/B readback difference support it; changed logging and timestamp conditions prevent a one-variable causal proof.

**Hypothesis — B's large planned-timing deviation occurs before the API call.** Confidence: high for location, low for cause. Packet timestamps already differ from the plan, while API calls are short. The missing dispatch-base log prevents precise attribution to scheduler behavior or startup overhead.

C is **deferred, not pending execution and not validated**. The latest user direction favors command-driven edits to an existing native MIDI region with stopped transport, rather than another real-time sender trial. Native region editing/MIDI Step Input is a separate unobserved operation here; this document asserts no capability or result for it.

## Evidence and limitations

The [machine-readable record](EXP-MIDI-032-controller-note-input.json) binds each raw evidence file to its current SHA-256 and records that all four TX-log/native-export hashes match the audit inputs. It also retains the source-script snapshot identities already recorded by the audits: A `636aabcf3fcc0509a13c21ca1b66572e40add63f4762ca7c6db90ead7ddfbeb3`, B `598e359043a663a1d5588ac4980510d889a08ddf900c71235f09b242199f0530`. These are source snapshots, not independently identified executed probe binaries; current source was not read or rehashed during curation.

| Raw readback input | SHA-256 |
|---|---|
| [A TX log](../raw/gui/midi-controller-032/note-tx.jsonl) | `79455858228428bab6d5979fe8290c20f73680105db49f02401587fc0127e7c5` |
| [A native export](../raw/gui/midi-controller-032/recorded-notes.mid) | `c3a524be53d2ead2234baaa8fac5dfbdd170599015f7f25715241f55086a51a2` |
| [B TX log](../raw/gui/midi-controller-032/note-tx-b.jsonl) | `0acc4c6e0b9adbc76bfeb8c4b393bad3f1e6073046cef77f43a77e264a04c658` |
| [B native export](../raw/gui/midi-controller-032/recorded-notes-b.mid) | `648812be5537dda196f213c8a13d92a6b7c726736f752decf2a81d7213f5fc17` |

Only this eight-note sequence on channel 0, velocity 90 and one selected software-instrument target was observed. Chords, overlapping notes, sustain, other channels, CC/pitch-bend, throughput, tempo maps and deterministic bar synchronization were not established. Installed on-disk identity is separate from a loaded-process image hash and from historical 12.3.1 function addresses. The result is research evidence, not a production CLI MIDI-input or region-editing feature.
