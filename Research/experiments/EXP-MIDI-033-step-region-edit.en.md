# EXP-MIDI-033: Add eight notes to a stopped native MIDI region with Step Input

[Machine-readable evidence and source hashes](EXP-MIDI-033-step-region-edit.json)

Native SMFs verify that a 50 ms inter-pair gap added the requested eight notes through a generic CoreMIDI virtual source to the prepared Step Input region at captured 120, 119 and 80 BPM. Each successful pass has order `[60,62,64,67,64,62,60,55]`, channel 0, velocity 90, exact 480-tick spacing and 475-tick durations. Back-to-back input and 20 ms gaps failed sequential placement by grouping notes. Two earlier native keyboard pilot notes remain distinct, and all notes from failed trials were retained. The successful source path followed source creation and then MIDI In OFF→ON; the cause of this ordering effect remains a hypothesis. This is bounded native-region editing evidence from a research prototype.

**日本語要約:** 停止中の既存MIDIリージョンに、ステップ入力経由で仮想MIDI入力8音を追加できた。50 ms間隔では実測の120・119・80 BPMで音高・順序・チャンネル・ベロシティと四分音符の配置をネイティブ書き出しから確認した。0 msと20 msでは音が一部同時位置になり、順次入力に失敗した。先行するキー入力2音と失敗試行の音は残して区別した。入力源の作成後にMIDI入力をOFF→ONにした条件で成功したが、その原因、最大入力速度、任意リージョンの完全ヘッドレス編集は未検証。

| Field | Recorded value |
|---|---|
| Date/time | Paced source: 2026-10-07 16:04 UTC; final confirmed 80 BPM pass: 16:24 UTC / 2026-10-08 01:24 JST |
| Logic | Status reports 12.4 / 6707; [current identity](../static-analysis/binary-identity-12.4-6707.json) records framework SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda` |
| macOS | Status reports 27.0 |
| Logic Remote | Not used |
| Test project | `LogicCLI-Test.logicx`; saved [Step Input window](../raw/gui/midi-step-input-033/step-settings-before.png) title says `LogicCLI-Test` |
| Initial state | Operator-created region at bar 21; GUI track 31 `Studio Grand` (MCU mixer position 13) / native region `Studio Grand`; two native keyboard pilot notes already inserted; Step Input prepared |
| One operation | Add the eight-note sequence from `logicctl-note-input`, a `MIDISourceCreate` virtual source using `MIDIReceived`, to this native MIDI region |
| Expected change | Eight additional notes in the requested order and attributes, placed by Logic's selected quarter-note Step Input size |
| Repetitions | Six source trials: paced success; back-to-back and 20 ms failures; 50 ms success at actual 120, 119 and 80 BPM; zero-TX timeout is a setup attempt |
| Readback | Native Logic export to SMF for inspection only; no SMF was supplied as input |

## Observations

The live operator reports that transport remained stopped. Saved [setup status](../raw/gui/midi-step-input-033/status-region-created.json), [before](../raw/gui/midi-step-input-033/status-before.json), [during](../raw/gui/midi-step-input-033/status-during.json) and [after](../raw/gui/midi-step-input-033/status-after.json) report both `playing:false` and `recording:false`, but their timestamps are 15:49–15:52 UTC, covering setup and the first failed attempt. They do not independently establish transport state during the successful 16:04 UTC pass. Their top-level `verified:false` status flags are retained in the JSON.

The successful [sender log](../raw/gui/midi-step-input-033/note-tx-rearmed.jsonl) records readiness while source `logicctl-note-input` already exists, 8 successful note-ons and 8 note-offs, no created virtual destination or port connection, and completion with exit 0. The operator reports MIDI In OFF→ON while that source was alive, then starting the source through its gate. The [saved editor state](../raw/gui/midi-step-input-033/rearmed-after-notes-ax.txt) shows MIDI In value 1 and ten visible notes, including the pilots. Earlier attempts with MIDI In already ON before creation of a new source did not insert notes according to the operator; focus and preparation also changed, so the comparison does not isolate a cause.

[Before](../raw/gui/midi-step-input-033/step-before.mid) and [first-attempt after](../raw/gui/midi-step-input-033/step-after.mid) exports are identical 14-byte MIDI headers with zero tracks. They contain no events and are not populated, valid Type-0 SMFs. Treat them as a limited failed-attempt artifact, not complete proof of native region contents.

The two pilots were native System Events keyboard inputs at velocity 80: keycode 0 (`A`, C), then keycode 20 (`3`, quarter-note step) and keycode 1 (`S`, D). The operator reports that an earlier quarter-note AXPress returned 0 but did not change the length; keyboard `3` did. These were keyboard events, with GUI preparation, rather than note clicks. They are independently visible in the [one-pilot](../raw/gui/midi-step-input-033/step-key-one.mid) and [two-pilot](../raw/gui/midi-step-input-033/step-key-two.mid) exports and survive unchanged in the [rearmed native export](../raw/gui/midi-step-input-033/step-rearmed.mid). The eight source notes use velocity 90 and begin after these pilots; the bar-21 region start is not their first onset.

| Note group | Pitch / channel / velocity | Start ticks | Duration ticks |
|---|---|---|---|
| Native-key pilot C | 60 / 0 / 80 | 38400 | 238 |
| Native-key pilot D | 62 / 0 / 80 | 38640 | 475 |
| Eight virtual-MIDI notes | `[60,62,64,67,64,62,60,55]` / 0 / 90 | `[39120,39600,40080,40560,41040,41520,42000,42480]` | 475 each |

The first successful rearmed export is Type 0, one track, PPQ 480, with 10 balanced starts/ends and positive durations. Its track end is 44160 ticks. Saved AX identifies a MIDI region beginning at bar 21 and ending at bar 24. At the exported 4/4 signature, `(21−1)×4×480 = 38400` ticks, agreeing with the first pilot. The first source note is 720 ticks after that region start. The [saved parser](../raw/gui/midi-step-input-033/rearmed-readback.json) and an independent byte parser agree on all note fields and the SMF hash.

The paced sender requested 500 ms onset spacing and 375 ms held-note duration, with Mach timestamps sampled before `MIDIReceived`. Step Input nevertheless produces quarter-note grid intervals and 475-tick durations: the selected step size, rather than a realtime recording clock, defines these exported positions. This is a region-content result; it does not measure receiver latency or establish accurate realtime sender scheduling.

The initial [fast setup log](../raw/gui/midi-step-input-033/note-tx-fast.jsonl) exits 2 with `gate_timeout` and zero transmitted notes. It is a setup attempt, not a fast-input trial.

The completed [fast2 log](../raw/gui/midi-step-input-033/note-tx-fast2.jsonl) sends eight back-to-back note-on/off pairs using `mode:step`, with a 0.25 s delivery grace. All 16 TX statuses are 0 and the process completes with exit 0. The [fast native export](../raw/gui/midi-step-input-033/step-fast.mid) has 18 notes: the original ten are preserved, but all eight additions begin at **42960** and end at **43435**, rather than advancing at `[42960,43440,43920,44400,44880,45360,45840,46320]`. Their pitch multiset is `[55,60,60,62,62,64,64,67]`, channel 0, velocity 90, duration 475. Correct pitches and balanced events therefore coexist with failed sequential placement.

[Independent fast byte analysis](../raw/gui/midi-step-input-033/fast-readback-independent.json) compares note event multisets and uses FIFO pairing for duplicate pitches. The duplicates have identical start/end/velocity here, so note-value counts are unambiguous; this does not establish a general overlapping-note identity algorithm or recover sender sequence from same-onset SMF sorting. It preserves the original 20 note events plus the 16 new events. Fresh [before AX](../raw/gui/midi-step-input-033/ax-fast-state-fast2-before.txt) and [after AX](../raw/gui/midi-step-input-033/ax-fast-state-fast2-after.json) bind the dedicated project URL, show playing/recording controls 0, MIDI In 1, and note count 10→18. These snapshots bound transport at their capture times.

**Hypothesis — rapid pairs were treated as one Step Input group.** Confidence: high for the exported coincidence, low for the internal mechanism. TX log timestamps span approximately 0.51 ms; there is no callback/handler trace or universal grouping threshold. The [20 ms run](../raw/gui/midi-step-input-033/run-gap20.json) and [native export](../raw/gui/midi-step-input-033/step-gap20.mid) preserve all 18 prior notes and add eight more. Sequential placement still fails: C/D share 43440, E/G share 43920, and D/C share 44880. The [50 ms run](../raw/gui/midi-step-input-033/run-gap50.json) and [native export](../raw/gui/midi-step-input-033/step-gap50.mid) preserve all 26 prior notes and add the exact requested sequence, starts `45840 + 480×i`, with all durations 475, channel 0 and velocity 90. Each run has 16 successful TX events, fresh pre/post AX showing play/record controls 0, and the dedicated test project URL. Notes from failed batches were retained, not removed or corrected.

| Source trial | Captured tempo | Added notes / total | Added onset placement | Sequential intent |
|---|---|---|---|---|
| Paced, 500 ms | 120 BPM; earlier setup/AX provenance | 8 / 10 | `39120 + 480×i` | Pass |
| Back-to-back | 120 BPM, pre/post AX | 8 / 18 | All 42960 | Fail |
| 20 ms gap | 120 BPM, pre/post AX | 8 / 26 | Three coincident pairs; five distinct onsets | Fail |
| 50 ms gap | 120 BPM, pre/post AX | 8 / 34 | `45840 + 480×i` | Pass |
| 50 ms gap, file named `bpm80` | **119 BPM**, pre/post AX | 8 / 42 | `49680 + 480×i` | Pass at 119 |
| 50 ms gap, confirmed 80 | **80 BPM**, pre/post AX plus independent capture | 8 / 50 | `53520 + 480×i` | Pass at 80 |

The attempted 80 BPM change initially failed: [direct AX assignment](../raw/gui/midi-step-input-033/tempo80-set.json) requested 80 from 120 but read back 119; native editing briefly read back 80, then reverted to 119 when focus changed. Pre/post AX for [the named `bpm80` run](../raw/gui/midi-step-input-033/run-gap50-bpm80.json) both show 119. Its [native export](../raw/gui/midi-step-input-033/step-gap50-bpm80.mid) was made after tempo returned to 120 and has tempo metadata 500000 µs/quarter. Input-state tempo and export metadata are recorded separately; neither filename nor transient value proves 80 BPM.

A later [bounded tempo adjustment](../raw/gui/midi-step-input-033/tempo80-settled.json) settled at 80, and the [independent before capture](../raw/gui/midi-step-input-033/tempo80-before-independent.txt) shows tempo 80 with play/record controls 0. The distinct [confirmed 80 run](../raw/gui/midi-step-input-033/run-gap50-tempo80-verified.json) has pre/post tempo 80, stopped controls, the dedicated test project URL, and note count 42→50. Its [native export](../raw/gui/midi-step-input-033/step-gap50-tempo80-verified.mid) independently preserves all 42 earlier note-event multisets and adds the eight exact notes at `53520 + 480×i`, all 475 ticks, channel 0 and velocity 90. The final export is Type 0, one track, PPQ 480, 50 balanced notes, final tick 57600 and tempo metadata 750000 µs/quarter (80 BPM). The notes from all earlier failed batches remain in this test region.

| Trial | First-to-last TX span | Sender finish elapsed from its base |
|---|---|---|
| 20 ms gap | 141.746 ms | 392.591 ms |
| 50 ms / 120 BPM | 353.160 ms | 604.114 ms |
| 50 ms / actual 119 BPM | 353.183 ms | 604.271 ms |
| 50 ms / confirmed 80 BPM | 352.287 ms | 603.306 ms |

The finish values include the configured 250 ms delivery grace after the final pair and source/client disposal. They are distinct from TX span; neither is the elapsed GUI operation, receiver-processing latency or native export completion time. Region placement follows the selected quarter-note step across these captured tempos. Each 50 ms run tests only eight notes: this establishes no maximum throughput, universal minimum safe gap, long-stream reliability, tempo-map behavior or fully headless completion.

[Final tempo restoration](../raw/gui/midi-step-input-033/tempo120-final-restored.json) independently reads back 120 after 80. [Step cleanup](../raw/gui/midi-step-input-033/step-restoration.json) reads MIDI In 0 and confirms the newly opened Step Input window was closed. The [settings image](../raw/gui/midi-step-input-033/step-settings-restored.png) visibly restores the earlier eighth-note length and mf velocity. Native GUI selection reads back [`Synth `](../raw/gui/midi-step-input-033/restore-synth-native.txt). Record-arm restoration was not independently verified. The playhead remains `30|4|3|1`; its original position was not restored. [Final save](../raw/gui/midi-step-input-033/save-final.json) guards the exact dedicated test URL, confirms the generic source is absent and existing MCU source remains, and records changed ProjectData SHA/size after saving.

## Current internal-route candidates

The [current static record](../raw/review/current-step-input-033.json) binds these candidates to the current 12.4 / 6707 copied framework hash. It keeps historical 12.3.1 addresses separate.

| ID | Name | Current handler / argument | Exact evidence scope |
|---|---|---|---|
| 922 | `1/4 Note` | `0x7a15f4` / 3 | Static entry and actual fixup-chain bytes |
| 72 | `Toggle MIDI In (Step Record)` | `0xf318c4` / 0 | Static entry and actual fixup-chain bytes |
| 1208 | `Show/Hide Step Input Keyboard` | `0xf57da0` / 36 | Constructor constant/store association; no complete CFG/runtime-registration proof |

After the step trials, [MCU feedback](../raw/gui/midi-step-input-033/state-before-restore.json) reported labels `Pan`/`-`, so the exact-name guarded [Synth restore request](../raw/gui/midi-step-input-033/restore-selected.json) returned `target_mismatch` without sending a write. GUI selection supplied the restoration readback. The cause and connection to virtual-source lifecycles are unisolated and remain a follow-up; musical-note success does not establish that MCU feedback remains healthy.

These candidates provide concrete next mapping targets. GUI checkbox/keyboard actions do not prove that these IDs were dispatched through a CLI, and names/entry bytes do not establish handler effects or arbitrary region targeting. The independent SMF audit read no new handler bodies and performed no GUI or MIDI action. Live operation, restoration and tool changes are separately attributed above.

## Official workflow references and next inventory

The user subsequently required Apple official documentation before future GUI or feature operations. The following pages were checked on 2026-10-08; their guide selector currently offers 12.3 as its newest version, while the captured application is 12.4 / 6707. These references explain documented workflows; they do not retroactively establish that the guide was consulted before every trial, nor verify identical behavior in 12.4.

- [Use step input recording](https://support.apple.com/guide/logicpro/use-step-input-recording-techniques-lgcpb19a8406/mac): prepare an editor region and insertion position, choose note length/velocity, and enter notes through a keyboard. Rest and Step Forward key commands provide additional step operations. Our virtual-source preparation sequence, 50 ms result and exported tick values are live observations, not timing guarantees from the guide.
- [Copy and print key commands](https://support.apple.com/guide/logicpro/copy-and-print-key-commands-lgcpeabb4c40/mac): the Key Commands window's Action menu can copy the command list to the clipboard. This is a concrete next route for a current installed-version inventory; no inventory was copied in EXP-MIDI-033. Parse only fields actually present, retain local raw text, and preserve the existing clipboard when automating this operation.
- [Assign key commands](https://support.apple.com/guide/logicpro/assign-key-commands-lgcp41ff6979/mac): keyboard assignments and MIDI Learn New Assignment are documented routes. Actual assignments, focus, selection and command effects still require current-version readback. Inventory coverage does not prove arbitrary command invocation.

The next shared task is a current 12.4 inventory followed by bounded reversible tests of rest, Step Forward, note value and velocity operations. Claude owns GUI/live discovery after its controller-assignment retest; Codex maps recorded operations to current IDs/functions. Keep the historical 12.3.1 catalog separate and preserve the production AppleEvent sender's existing version/ID guards.

## Hypotheses and limits

**Hypothesis — source creation followed by MIDI In OFF→ON refreshes or enables this input.** Confidence: medium for the observed sequence, low for the general mechanism. The successful pass follows that sequence; earlier source-after-ON attempts failed. Changed focus/preparation is a counterexample to a clean one-variable interpretation. Repeat source-before/source-after conditions with identical region and focus before treating this as a universal source-enumeration requirement.

**Hypothesis — an approximately 99% gate could explain the exported lengths.** Confidence: medium for the numerical fit, low for the actual setting or implementation. `240×0.99 = 237.6` and `480×0.99 = 475.2` agree with 238/475 ticks after rounding. No saved readback or operator observation proves a 99% setting; the rounding rule and other percentages remain untested. Vary one visible gate setting with fixed step size in a later native-export experiment.

[Apple's timestamp contract](../raw/gui/midi-controller-032/timestamp-semantics.md) makes a `MIDIReceived` virtual source responsible for valid Mach host timestamps; zero does not substitute for now in that API. This step-input result does not establish future-batch source buffering, tempo-map handling, absolute realtime latency or 032's deferred strict scheduling C trial.

Only this region, sequence, channel and velocity were targeted. Unintended overlaps were observed in failed batches; intentional chord entry, sustain, other channels, CC and pitch bend were not tested here. Native SMF verifies saved note content; its export provenance and the successful pass's stopped transport are supplied by the live operator. The workflow required GUI region creation, selection, Step Input preparation and export. It remains a research CLI prototype, without an established production MIDI feature or arbitrary headless native-region editor. The 20/50 ms run records report the research-source snapshot SHA-256 `11f4777d51542e22156b753324f22dfbf7b6a978e6de587fe783b20f3e84159d`. This is the supplied source snapshot recorded by the run, not an independently bound executed probe binary or a guarantee that the current source still matches. The independent audit did not build it. The live operator subsequently preserved that exact [executed source snapshot](../raw/gui/midi-step-input-033/probe-source-executed.swift), then changed the published tool default from 0 to the observed 50 ms gap and recompiled help only. That current-source SHA differs by design; it is not substituted for the recorded trial source.

The adjacent JSON records complete raw-file SHA-256/size bindings. Key input/readback hashes are:

| Evidence | SHA-256 |
|---|---|
| [Two-pilot native export](../raw/gui/midi-step-input-033/step-key-two.mid) | `8f73c690c07a9a7709e660ae51fa4dd8111ddf5d4029c6d0f1c178001b05c0a7` |
| [Rearmed native export](../raw/gui/midi-step-input-033/step-rearmed.mid) | `629d7b4f46beb2b3875f131e07225de22ea8fae468f2f937bec08865a436d871` |
| [Fast native export](../raw/gui/midi-step-input-033/step-fast.mid) | `8a708324e328ca1848b582f9560fdc2d6c50892d59faec1913d36f0cfb53784c` |
| [Final confirmed 80 export](../raw/gui/midi-step-input-033/step-gap50-tempo80-verified.mid) | `86a31505552705a8b9228e934a8dfadaeaa7eb5fc660db526f45e38fc28e6d14` |
