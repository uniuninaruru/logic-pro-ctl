# ASSIGN-IDENTITY-001: how a plug-in parameter assignment finds its plug-in (Logic 12.4, static)

[Research guide](../README.md) · [Instruction anchors](../protocol/assignment-identity-12.4-anchors.tsv) · Related: [PICKUP-CONSUMER-001](pickup-consumer-001.en.md), Codex's [assignment-target-001](assignment-target-001.en.md) and [assignment-parameter-002](assignment-parameter-002.en.md) · Live test plan: [PLAN-CA-005](../plans/PLAN-CA-005-morning-live-tests.en.md)

日本語要約：プラグインのパラメーターに割り当てた CC が、どのプラグインを動かすかを決める処理を、Logic 12.4 の複製から静的に読んだ。割り当てに保存された番号を上位ビットで 4 系統に分け、プラグイン系統（Channel EQ の Master Gain の行が該当）は、割り当てに UUID のキーがあれば UUID で、無ければ「保存された 3 語の識別子が一致する N 番目」で、入れ物の中の要素を探す。差し替えたときの振る舞いは実機で確かめる必要がある（PLAN-CA-005 の T3）。推論であり、実行時の確認ではない。

## Scope and identity

| Item | Value |
|---|---|
| Image | Preserved copy `Research/raw/binaries/Logic12.4-6707.arm64`, sha256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda` |
| Tools | REA 6.7.0 with Ghidra 12.1.4 (one retained session), llvm-objdump |
| Evidence | Static only; Logic was not running. Pseudocode stays in ignored `Research/raw/rea/` |
| Requested by | Codex (leader), board CDEX149, CDEX152, CDEX155 |

## Findings

"Observation" is the bytes and references; "Inference" is a reading of control flow not checked at runtime.

| # | Finding | Anchors / Evidence | Status |
|---|---|---|---|
| I1 | `FUN_015de134` (5,504 bytes, one caller) reads a 32-bit parameter code from the assignment (+0x40) and splits it: code & 0xffffc000 == 0x4000 (family A), code >> 8 == 0x24 (family B), code & 0xffffe000 == 0x2000 below 0x23xx (family C), otherwise a jump table over codes 3–0x306. It contains no indirect call | AI001–AI010; Evidence `ev_e2276d69…` | Observation |
| I2 | Codex decoded the stored codes of the test rows: Channel EQ Master Gain 0x4020 (family A), volume 7 and pan 0x0a (jump table) | Board CDEX153 | Observation (Codex) |
| I3 | Family A calls the resolver `FUN_015df8a8` with the ordinal argument fixed at −1 and only when the assignment's +0xf8 list is not empty | AI004, AI005 | Observation |
| I4 | The resolver picks a container through the context (context +0x788 → a pointer list at +0x150 → a second list at +0x50, with bounds checks) and walks it with an enumerator that calls a block for each element | AI014, AI017; Evidence `ev_f9cc3194…`, `ev_d4db2dab…` | Observation (structure); Inference (what the container is) |
| I5 | When the ordinal is negative and the assignment's +0x1a0 list is not empty, the block compares each element's UUID with the stored key through `CUUIDBase::operator==` | AI011, AI012, AI013, AI014, AI018; Evidence `ev_bc24cf3f…` | Observation (call); Inference (key = the value stored behind +0x1a0) |
| I6 | Otherwise the ordinal is taken from the first +0xf8 entry (+0xc), and the second block selects the N-th element whose three 32-bit words at +0xb4/+0xb8/+0xbc equal the three words stored in that entry | AI015, AI016, AI017, AI019–AI022; Evidence `ev_64140afd…` | Observation (compares); Inference (the words identify the plug-in kind) |
| I7 | The +0xf8 list is written by small init/clear helpers, by Codex's constructor `FUN_015dc8a8`, and by a large update routine `FUN_015e43f0` (10,260 bytes) that is also reached from the control-surface refresh path. So the list may be a refreshed cache of the resolved target rather than an identity captured at learn time | Region scan in `Research/raw/rea/region15d.objdump.txt` | Observation (writes); Inference (role) |

## What this predicts, and what it does not

- If the stored key is used (I5), replacing a plug-in with another instance would not match the old instance's UUID.
- If the descriptor path is used (I6), a different plug-in kind would not match, and a new instance of the same kind in the same order would match.
- Because of I7, the descriptor and ordinal may be refreshed from the current state, which could let the assignment follow a replacement. The live test (PLAN-CA-005 T3a and T3b) decides between these readings.

## Proof limits

- Register flow was read at operand level only; Codex has not yet audited these intervals.
- What the container, the +0x1a0 list and the three words are is inferred from use, not from names or a writer proven end to end.
- The serialized CC 23 row (119 bytes) holds no ASCII four-character codes besides its label, so the three words may be numeric internal ids or not serialized in that row.

## Raw data (not in Git)

`Research/raw/rea/`: `w15de134.objdump.txt`, `r15df8a8.objdump.txt`, `e1a34b1c.objdump.txt`, `cb0x15e01fc.objdump.txt`, `cb0x15e0264.objdump.txt`, `region15d.objdump.txt`, and the REA JSON results `af-*.json`, `rcp-*.json`, `cl-*.json`, `ce-*.json`.
