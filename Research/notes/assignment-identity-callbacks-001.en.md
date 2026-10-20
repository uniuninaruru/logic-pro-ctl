# ASSIGN-IDENTITY-001: how a plug-in parameter assignment finds its plug-in (Logic 12.4, static)

[Research guide](../README.md) · [Instruction anchors](../protocol/assignment-identity-12.4-anchors.tsv) · Related: [PICKUP-CONSUMER-001](pickup-consumer-001.en.md), Codex's [assignment-target-001](assignment-target-001.en.md) and [assignment-parameter-002](assignment-parameter-002.en.md) · Live test plan: [PLAN-CA-005](../plans/PLAN-CA-005-morning-live-tests.en.md)

日本語要約：プラグインのパラメーターに割り当てた CC が、どのプラグインを動かすかを決める処理を、Logic 12.4 の複製から静的に読んだ。学習時、最後に触ったパラメーターから「プラグインの ID 3 語・同じ ID のプラグインの中での番号・そのインスタンスの UUID」の 32 バイトを作り、割り当ての +0xf8 に保存する。実行時は、割り当ての +0x1a0（固定トラックの識別子。Codex の ASSIGN-TARGET-001）が空なら「ID 3 語が一致する N 番目」で、空でなければ「保存したインスタンス UUID」でプラグインを探す。テスト行は選択トラック方式（0x1000）なので、選ばれているトラックのプラグインが探される。テスト行（CC 23 → Channel EQ Master Gain）の保存データでは +0x1a0 が空なので、前者の探し方になる。昨夜の記述のうち、UUID 比較の鍵（I5）と +0xf8 の書き手（I7）は誤りだったので訂正した。推論であり、実行時の確認ではない。

## Scope and identity

| Item | Value |
|---|---|
| Image | Preserved copy `Research/raw/binaries/Logic12.4-6707.arm64`, sha256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda` |
| Tools | REA 6.7.0 with Ghidra 12.1.4 (one retained session), llvm-objdump; anchors checked with `Tools/research-scripts/binary_anchors.py` (75 of 75 hold) |
| Saved data | Read-only parse of the copied preferences snapshot `Research/raw/cs-diff/s2.bin` (header length valid); the live file was not opened |
| Evidence | Static only; Logic was not running. Pseudocode stays in ignored `Research/raw/rea/` |
| Requested by | Codex (leader), board CDEX149, CDEX152, CDEX155; I8–I15 are own-initiative work in the same lane |

## Findings

"Observation" is the bytes and references; "Inference" is a reading of control flow not checked at runtime.

### Resolver (runtime side)

| # | Finding | Anchors | Status |
|---|---|---|---|
| I1 | `FUN_015de134` (5,504 bytes, one caller) reads a 32-bit parameter code from the assignment (+0x40) and splits it: code & 0xffffc000 == 0x4000 (family A), code >> 8 == 0x24 (family B), code & 0xffffe000 == 0x2000 below 0x23xx (family C), otherwise a jump table over codes 3–0x306. It contains no indirect call | AI001–AI010 | Observation |
| I2 | Codex decoded the stored codes of the test rows: Channel EQ Master Gain 0x4020 (family A), volume 7 and pan 0x0a (jump table) | Board CDEX153 | Observation (Codex) |
| I3 | Family A calls the resolver `FUN_015df8a8` with the ordinal argument fixed at −1, and only when the assignment's +0xf8 list is not empty | AI004, AI005 | Observation |
| I4 | The resolver takes a track-like object (type byte +0x69 must be 0x11) and picks its container through the context (+0x788 → list at +0x150 indexed from the object's +0x335 → list at +0x50 indexed by its +0x320), then walks the container with an enumerator that calls a block for each element | AI014, AI017 | Observation (structure); Inference (what the container is) |
| I5 | **Corrected.** When the ordinal is negative and the +0x1a0 list is not empty, the first block compares each element's UUID (element +0x10) with the UUID stored at +0x10 of the first +0xf8 entry. The +0x1a0 bytes are not passed to the block: the register that held its begin pointer is overwritten before the block captures are stored, and the capture at +0x30 is the +0xf8 entry. A non-empty +0x1a0 therefore only selects this path. If no element matches, a second enumeration mode is tried; there is no fall-back to I6 | AI011, AI012, AI052–AI058 | Observation (operands). The earlier reading "key = +0x1a0" (CLDE105) was wrong |
| I6 | Otherwise the ordinal is taken from the first +0xf8 entry (+0xc), and the second block selects the N-th element whose three 32-bit words at +0xb4/+0xb8/+0xbc equal the entry's words at +0/+4/+8 | AI015–AI017, AI019–AI022 | Observation |

### Learn side (where the stored identity comes from)

| # | Finding | Anchors | Status |
|---|---|---|---|
| I7 | **Corrected.** `FUN_015e43f0` does not write an assignment's +0xf8 list. Its two stores at +0xf8 initialise a guarded static object at 0x2640518. The only constant-id writer of list 6 found is the learn path in I11; the other list setters take the id as a variable and are reached from label, message and constructor paths | AI023–AI025; scan `Research/raw/rea/list-writers.tsv` (43 call sites) | Observation (stores, call sites); the variable-id setters were not traced one by one |
| I8 | The assignment keeps byte lists at +0x68 + id × 0x18 (begin, end, capacity), resized by `FUN_015dc49c(assign, id, size)`; Codex proved this accessor first in [ASSIGN-TARGET-001](assignment-target-001.en.md). List 6 is +0xf8, list 0xd is +0x1a0 | AI026, AI027 | Observation |
| I9 | `FUN_017ee1ec` builds a "touched parameter" record: kind 5 at +0; the plug-in element's words +0xb4/+0xb8 at +0x1c and +0xbc at +0x24; at +0x28 the element's ordinal among elements with the same three words (`FUN_00abb4fc`); the element's UUID (+0x10) copied by `CUUID::operator=` to +0x2c; the parameter index (< 0x4000) at +0x40. It is reached from `CLgPluginController::extParValueChangedByUser:forCallID:` through `FUN_003e64cc` | AI028–AI039 | Observation (stores, calls); Inference (record role, from the caller name) |
| I10 | `FUN_00abb4fc` walks the same container as the resolver with the block `FUN_00abb704`, which counts elements with the same three words that come before the given element. This is the inverse of I6 | AI049–AI051 | Observation |
| I11 | `FUN_017ee3ac` (called from `TouchedParamHistoryWrapper::info` and eight other places) applies a kind-5 record to an assignment: selector +0x3e = 0x1000, 0x20 bytes from record +0x1c into list 6, code +0x40 = record parameter index + 0x4000. So the +0xf8 entry is {three words, ordinal, instance UUID}, and family A codes are 0x4000 + plug-in parameter index (Master Gain 0x4020 → index 0x20) | AI040–AI048 | Observation (stores); Inference (that this is the Learn step) |
| I12 | +0x1a0 is the pinned-track payload: Codex's ASSIGN-TARGET-001 shows that `FUN_015e6d44` stores 16 bytes from a context +0x788 → +0x1e0 entry when the selector mode is 0xb ("pinned to track"), and that the target worker reads it in that mode; selector 0x1000 is the selected-track mode (`setTrackTypeSelectedTrack`). New here: `FUN_015e6c70` is a second writer (16 bytes from the object passed in), used by I13. So +0x1a0 identifies a track, not a plug-in | AI059–AI063; ASSIGN-TARGET-001 | Observation (writes); the mode names are Codex's |
| I13 | `FUN_00abb778`, applied to every assignment by `FUN_0088016c` through `FUN_00aba310`, acts only on assignments whose +0x1a0 is not empty. It resolves the plug-in by its instance UUID, recomputes the ordinal and writes it back to the +0xf8 entry when it changed. If the instance is not found on the stored track, it tries every track and stores the track where it is found in +0x1a0. Inference: this keeps a fixed-track assignment attached to the same plug-in instance after it moves. What triggers `FUN_0088016c` is not known | AI064–AI069 | Observation (calls, stores); Inference (purpose, trigger) |
| I14 | The three words are plug-in IDs: the plug-in menu passes the same element fields to `_MAAEGetPlugInNicknameForIDs` | AI070 | Observation (call); Inference (field names) |

### Saved test row (read-only check of the copied snapshot)

| # | Finding | Status |
|---|---|---|
| I15 | The CC 23 row (B0 17, label "Master  Gain", 119-byte payload) stores class 5, selector 0x1000, code 0x4020 and the lists 1 (the message B0 17 F5), 3 (the text "Master  Gain"), 6 (0x20 bytes: words 0x454d4147, 0, 0xec; ordinal 0; a 16-byte UUID, not reproduced here) and 0x10 (16 bytes). List 0xd (+0x1a0) is absent. The Master Fader row (class 5, selector 0x5000, code 7) has no list 6. Under I5/I6 the CC 23 row is resolved by the three words and ordinal 0, not by its stored instance UUID | Observation (bytes, using the payload-offset k ↔ Assign 0x38 + k mapping and the list ids of I8); Inference (resolution path) |

Read as a four-character code, the first word is `EMAG`. Hypothesis (low): an Emagic-era manufacturer code for Logic's own plug-ins. This replaces an earlier proof-limit line that said the row held no four-character code.

## What this predicts for the CC 23 row

- If Channel EQ is replaced by a different plug-in, the IDs no longer match, so CC 23 should move nothing, unless another Channel EQ is on the same channel strip (that one would become ordinal 0).
- If Channel EQ is replaced by a new Channel EQ, the IDs and ordinal 0 match, so CC 23 should control the new instance. The stale UUID inside the entry is not used on this path.
- If a second Channel EQ is inserted before the original, CC 23 should move the earlier one. The enumerator walks the container's slot vector in ascending index, one section at a time (mode 0: +0x4c entries after the first +0x4a; mode 1: the +0x4e entries after those), and the ordinal counts within one section (AI071–AI075). This holds if both instances sit in the same section and the slot index follows the on-screen order (Inference, medium).
- Selector 0x1000 is the selected-track mode (I12), so the search uses the plug-ins of the track that is selected when CC 23 arrives. Keep the Synth track selected during these tests. With another track selected, CC 23 should act on that track's first Channel EQ, if it has one.

## Proof limits

- Register flow was read at operand level only; Codex has not audited I5 (corrected) or I7–I15 yet.
- The triggers of `FUN_0088016c` and of `FUN_017ee3ac` are inferred from names and callers, not from a proven end-to-end path. How the GUI and the session bind the selected-track mode still needs the live gate.
- I15 relies on the field mapping of the decoder (Codex, CDEX157: it decodes into a temporary buffer and constructs the assignment from it), so the offsets are the decoder's, not proven memory offsets.

## Raw data (not in Git)

`Research/raw/rea/`: `r15df8a8.objdump.txt`, `cb0x15e01fc.objdump.txt`, `cb0x15e0264.objdump.txt`, `region15d.objdump.txt`, `x0x17ee1ec.objdump.txt`, `x0x17ee3ac.objdump.txt`, `x0xabb4fc.objdump.txt`, `x0xabb704.objdump.txt`, `x0xabb778.objdump.txt`, `scan-b4b8bc.txt`, `list-writers.tsv`, `callsites-learn.txt`, and the REA JSON results `rcp-*.json`, `cl-*.json`, `ce-*.json`, `xr-*.json`.
