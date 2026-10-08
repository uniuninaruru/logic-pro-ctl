# SA-MIDI-ROUTE-001: connect generic MIDI assignments to prior routes

[Research guide](../README.md) · [Machine-readable evidence](SA-MIDI-ROUTE-001.json) · [Current work order](../plans/agent-ready-roadmap.en.md)

**Current focus, 2026-10-08: use generic MIDI assignments as the entry point for parameter and key-command control.** The live evidence through CA003 now covers variable CC pan, volume and one Channel EQ parameter, actual row modes/multipliers, and matched Pickup/crossing tests. Six assignment getters have also been independently located and byte-checked in Logic 12.4. The remaining internal link is input matching/conversion through target resolution to execution; a getter does not prove that link.

日本語要約：MIDI割り当てを主軸に、既存のMCU・Remote・キーコマンド・AppleEvent・リージョンの解析を接続する。可変CCによるパン・音量・Channel EQの実機結果に、現行版の割り当てクラス・命令番号・値モード・倍率・可変値指定の6関数を対応付けた。CA003で固定CCの回転×1.00と可変CCのスケール×1.00、ピックアップの現在値通過を確認し、KC001でキーコマンド2,176件・27グループを取得。受信から対象へ値を適用する内部経路、正確な値変換、対象の寿命は引き続き調査する。

## Scope and identities

| Evidence | Scope |
|---|---|
| Historical Assign templates, parameter candidates and shared command/engine dispatcher | Logic 12.3.1 / 6682; copied ARM64 SHA256 `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| New getter metadata, instructions and `assign` call stubs | Independently verified on both 12.3.1 / 6682 and 12.4 / 6707; current copied ARM64 SHA256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda` |
| CA001–CA003, KC001 and MIDI033 live results | Reported running Logic 12.4 / 6707, macOS 27.0, dedicated `LogicCLI-Test.logicx` |
| Official guides consulted | Version selector 12.3; documented behavior and localization differences are not current runtime proof |
| This work | Offline copied-binary inspection and evidence reconciliation; no live action, preference write or shared Ghidra job |

Addresses below are virtual addresses in the specified copy, not loaded-process addresses. Hashes, exact getter bytes, method metadata and source bindings are in the JSON. Historical command and parameter numbers are retained as candidates for current-version matching.

## How prior research connects

| Existing work | Useful connection | Established evidence and missing link |
|---|---|---|
| [Assign templates and fields, SA-002](SA-002-control-surface-assign-model.en.md) | MCU, Remote and TouchOSC templates use the serialized Assign model. It separates parameter and command assignments | Historical common template initialization and fields; current generic input consumer and numeric class meanings remain untraced |
| [Shared command boundary, SA-004](SA-004-command-and-engine-boundaries.en.md), [Remote key commands](SA-REMOTE-KEYCOMMAND-001.en.md) | MIDI-assigned key commands can be compared with the existing command catalog and GUI/Remote actions | Historical kind 9 command field and dispatcher `0x8663d4`; [KC002](../experiments/EXP-KC-002-midi-to-key-command-loop-browser.en.md) now proves a current learned CC24 action; its numeric command/handler route remains untraced |
| [Private AppleEvent dispatch](appleevent-command-dispatch.en.md) | A second route into the historical shared command dispatcher helps cross-check command identity | Historical dispatch proof; the product AppleEvent backend is still restricted to play/stop IDs 3/5 and its 12.3.1 identity guard |
| Existing MCU backend | Provides an independent pan/volume readback for generic CC writes | CA001/CA002 used MCU values; arbitrary plug-in feedback and stable target identity are not supplied by this observation |
| Remote fader/engine boundary in SA-004 | Offers a narrow candidate for the downstream parameter executor | Historical Remote fader event to engine queue is traced; generic Assign class 5 to that queue is a **Hypothesis**, not a proven edge |
| [AppleEvent target resolution](SA-AE-TARGET-003-target-resolution.en.md), [channel/plugin schema](SA-AE-XML-002-channel-node-schema.en.md) | Existing target/type evidence helps distinguish track, channel strip, plug-in slot and parameter | These old models are comparison material; they do not establish current generic-assignment target resolution or a public state getter |
| [Step MIDI region edit, MIDI033](../experiments/EXP-MIDI-033-step-region-edit.en.md), [position conversion](SA-AE-TIME-001-position-conversion.en.md) | Key commands prepare the editor; generic musical note input then inserts native MIDI content | Current Step input/readback is observed. Musical note input and controller-assignment dispatch are separate routes; old time conversion does not prove their units coincide |

For historical channel-strip Assigns, SA-002 identifies kind 5 with candidates volume 7, pan 10, select 259 and record enable 260. Remote/TouchOSC mute/solo use 9/3 while MCU uses 128/129, so these numbers cannot be treated as a universal parameter namespace. Kind 9 stores a command number at `+0x3e`. This note proves the current getter locations, **not** the current meaning of numeric kinds 5/9 or those parameter candidates.

## New current-version getter proof

The selected class is exactly `WrappedAssign`. Its 124-entry relative method list is located independently through `__objc_classlist` and chained-fixup membership in each copy. Exact selector metadata binds each implementation address. `LC_FUNCTION_STARTS` bounds the inspected interval; this is not a complete control-flow proof. LLVM disassembly is checked against all interval bytes.

| Selector | 12.3.1 entry | 12.4 entry | Bytes per copy | Read after `assign` |
|---|---|---|---:|---|
| `assignmentClass` | `0x697d24` | `0x69a1a4` | 24 | 32-bit word at `+0x3a` |
| `befehl` | `0x6970f8` | `0x699554` | 24 | Signed 16-bit value at `+0x3e` |
| `valueMode` | `0x698180` | `0x69a600` | 28 | Byte at `+0x4b`, masked with 7 |
| `multiply` | `0x698270` | `0x69a6f0` | 64 | Signed 16-bit value at `+0x4c`, converted to double, multiplied by 0.01, returned as float |
| `valueChangeHasLo7` | `0x697fe0` | `0x69a460` | 76 | Scans stored byte span `+0x80`/`+0x88` for `0xF5` |
| `valueChangeHasHi7` | `0x69802c` | `0x69a4ac` | 76 | Scans the same span for `0xF4` |

Each getter calls the independently decoded Objective-C `assign` stub: historical `0x1b0c500`, current `0x1b14bc0`, each 20 bytes, selector `assign`, imported `_objc_msgSend`. Selected pointers have actual chained-fixup membership. The getter instructions match across versions except their independently rebound `BL` words. Twelve getter intervals total 584 bytes; two call stubs add 40 bytes. All 624 bytes / 156 ARM64 words are checked against the copied binaries.

`0xF5`/`0xF4` are **internal pattern markers**. They are not bytes to send as wire MIDI statuses. The 0.01 constant has IEEE-754 bits `0x3f847ae147ae147b`. This establishes the stored multiplier getter, not the actual scale applied to incoming messages. Numeric value-mode enum meanings, defaults beyond the observed rows, receiver overrides, matching, setters, persistence, target resolution and execution are outside this proof.

Local full proof/reproducer: `Research/raw/review/midi-first-current-getters-001.json` and `.py`. The curated JSON retains the selected metadata, bytes and body hashes so the public result does not rely solely on an ignored raw-file pointer. Both binary hashes were checked before and after extraction.

## Current live anchor: fixed versus variable CC

[CA001](../experiments/EXP-CA-001-generic-cc-fixed-message.en.md) reports a literal `B0 14 40` assignment with no variable placeholder. Eight exact messages moved Synth pan by +1 each; one `B0 14 41` did not move it. GUI and MCU agreed. The later [CA003](../experiments/EXP-CA-003-value-mode-pickup-ab.en.md) readout identifies this row as **Rotate, Multiply 1.00**, resolution 128 steps with global resolution on. At pan +63, two exact messages produced −64 then −63, confirming wrap behavior. The internal input-conversion path remains untraced.

[CA002](../experiments/EXP-CA-002-variable-cc-and-pickup.en.md) reports that learning four changing values produced Lo7 rows for three targets:

| Assignment | Samples sent | Readback | Verification scope |
|---|---|---|---|
| Pan, CC21 | 0, 127, 64, 90, 100 | −64, +63, 0, +26, +36 | MCU; observed samples fit value minus 64 |
| Volume, CC22 | 127, 0, 64, 100, 32, 90 | +6.0, −∞, −6.0, +1.8, −18.0, 0.0 dB | MCU; sampled fader taper, not a complete derived curve |
| Channel EQ Master Gain, CC23 | 127, 0, 64 | +24.0, −24.0, +0.2 dB | GUI; no MCU plug-in readback established |

Pan followed the selected track across Piano, Ballad and Synth. With Pickup on, several unsynchronized values were ignored; reaching the target's current value synchronized the controller and a later value applied. Pickup-off behavior also applied an unsynchronized value, but the reported on/off comparison uses **100 versus 110**, not identical stimuli. CA003 subsequently reads CC21–23 as **Scale, Multiply 1.00** and supplies a matched comparison: the same `[90, 100]` sent to the same unsynchronized Ballad target changed nothing with Pickup on, and produced +26/+36 with it off. In a separate on trial, 90 and 100 were ignored, then 30 applied −34 while crossing the current input-equivalent value 64. Equality is therefore not required in this observed crossing. Exact conversion, rounding, clamping and the Pickup consumer still need tracing; mode labels have not been bound to numeric internal enums.

No value-feedback MIDI returned to `logicctl-cc` in CA001/CA002 (device-query SysEx was separate). CA003 reads pan/volume feedback format None; single dot/line on CC21 also yielded no messages in one trial, then was restored to None. This proves the observed absence on that port and those targets, not a universal lack of feedback. The generic input-to-target effect is now observed; its internal consumer is still missing. CA002 reports restored Synth pan/volume/EQ and Pickup on, with experimental rows retained; live-slot/probe ownership remains with Claude.

## Official guide reconciliation

The [assignment overview](https://support.apple.com/guide/logicpro/controller-assignments-overview-ctls71c31487/mac) describes Learn for channel-strip and plug-in parameters in Easy view, with more assignment classes in Expert view. This motivates broad coverage; it does not prove every visible control is assignable.

The [English MIDI Input page](https://support.apple.com/guide/logicpro/expert-view-midi-input-parameters-ctls71c30fbf/mac) describes Lo7/Hi7 as variable value placeholders and placeholder-free input as **1**. The [Japanese page](https://support.apple.com/ja-jp/guide/logicpro/ctls71c30fbf/mac) instead says **0**. Both were checked on 2026-10-08 with guide selector 12.3. Preserve this localization discrepancy; do not silently substitute one text for a runtime measurement. English 1 is consistent with CA001's unit steps, and CA003's Rotate ×1.00/wrap behavior; the internal consumer is still unresolved.

The [Value page](https://support.apple.com/guide/logicpro/expert-view-value-parameters-ctls71c308ee/mac) distinguishes incoming value use, range scaling, relative changes and Multiply. These documented choices guide the next tests; the getter proof does not assign enum numbers to their labels. [General settings](https://support.apple.com/guide/logicpro/general-settings-lgcp1fe673ef/mac) documents Pickup. CA002 supplies the current generic-row observation and the limitations above.

For key commands, use Apple's [MIDI assignment procedure](https://support.apple.com/guide/logicpro/assign-key-commands-lgcp41ff6979/mac) and [copy-to-clipboard inventory procedure](https://support.apple.com/guide/logicpro/copy-and-print-key-commands-lgcpeabb4c40/mac). [KC001](../experiments/EXP-KC-001-key-command-inventory.en.md) obtained **2,176 commands in 27 groups**, including Pattern/Session Player region operations, Loop Browser and Step Input Keyboard. CP932 preserves command names; some modifier glyphs were already replaced by `?`. The copied list lacks the Control Surface column and numeric command IDs. [KC002](../experiments/EXP-KC-002-midi-to-key-command-loop-browser.en.md) learned CC24 for Loop Browser, verified toggles for values 127/1/64 and no response to 0, then deleted the row and verified no later effect. This proves one named command, not all 2,176. The historical Loop Browser catalog candidate is ID748/handler `0xf50328` on12.3.1; its current internal record/dispatch remains to be checked. The inventory alone does not prove ID mapping or execution. Editor focus and region/track selection remain part of an operation's prerequisites.

## Bounded next work and implementation boundary

| Owner | Next evidence unit | Completion condition |
|---|---|---|
| Claude, GUI/live | Capture one learned key-command row in Expert view, then one reversible Pattern-region command; reuse CA003 and KC001/KC002 | Named rows/settings and before/after readback; preserve clipboard, restore reversible state, announce live-slot release |
| Codex, copied binary | Rebind only relevant setters/parser/matcher and Pickup consumer from current metadata/xrefs | Byte-supported input pattern → decoded value → conversion or synchronization predicate; identify version and separate guessed edges |
| Both | Bind the observed Loop Browser MIDI action to its current internal command record | Current label/assignment/message and action → current command record/handler; no candidate-only capability claim |
| Codex, targets/readback | Compare selected-track assignment binding and plug-in target with prior target/schema work | Prove current binding/availability; associate units, range and reliable readback before product writes |

Historical setter leads (`setValueChange:` `0x697edc`, `setValueMode:` `0x69819c`, `setMultiply:` `0x6982b0`) are **index leads only** until independently rebound and checked on 12.4. Trace the functions relevant to the observed rows; do not expand unrelated bodies.

For production, the eventual operation contract needs assignment/input identity, target identity and focus, input/value conversion, operation preconditions, an observed result and cleanup. Musical Step input still uses editor preparation followed by note events; MIDI033's 50 ms gap succeeded for an eight-note sequence at observed 120/119/80 BPM, not an arbitrary-duration maximum-speed guarantee. Current static Step-related IDs 72/922/1208 remain record/constructor evidence with `runtime_id_execution_verified: false`.

This note adds no product command. Generic Learn, arbitrary parameter writes, generic MIDI key-command dispatch and headless Step preparation are not exposed by it. Existing MCU operations and the guarded AppleEvent backend retain their tested scope.

External implementation comparison: [logic-pro-mcp and fork review](../notes/logic-pro-mcp-reference-001.en.md) identifies reusable API/state/readback patterns and separates timed MIDI recording from native region editing. No external code was run.
