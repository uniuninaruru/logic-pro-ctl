# PICKUP-CONSUMER-001: where Pickup mode acts on generic controller assignments (Logic 12.4)

[Research guide](../README.md) · [Instruction anchors](../protocol/pickup-consumer-12.4-anchors.tsv) · Live records: [CA002](../experiments/EXP-CA-002-variable-cc-and-pickup.en.md), [CA003](../experiments/EXP-CA-003-value-mode-pickup-ab.en.md), [CA004](../experiments/EXP-CA-004-channel-eq-gain-calibration.en.md)

日本語要約：汎用のコントローラ割り当てで、ピックアップモードが効く処理を Logic 12.4 の複製から静的に特定した。値を適用する 1 つの関数の中で、①直前と同じ値は捨てる、②「スケール」モードかつ設定がオンのときだけピックアップを調べる、③割り当てごとの状態ビット（値が有効・拾った）を持つ、④対象の現在値が、直前の値と今回の値の間（両側に「範囲の 2% を整数に切り捨てた幅」を足した範囲）に入れば拾う、という形に見える。この読みは、CA002〜CA004 の実機の結果をすべて説明する。ただし逆コンパイルからの推論で、実行時の確認ではない。

## Scope and identity

| Item | Value |
|---|---|
| Image | Preserved copy `Research/raw/binaries/Logic12.4-6707.arm64`, sha256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda` (Logic 12.4 / 6707) |
| Tools | REA 6.7.0 with Ghidra 12.1.4 in one retained session (auto-analysis 2026-10-20 15:51–16:10 UTC; overview Evidence `ev_6b3b4f25eb546758…`, 134,665 procedures, image base 0); llvm-objdump for byte anchors |
| Kind of evidence | Static only. No Logic process was inspected, hooked or run. Pseudocode stays in ignored `Research/raw/rea/`; this note gives addresses, bytes and plain-language readings |
| Apple guide | General Control Surfaces settings (lgcp1fe673ef): in Pickup mode the value does not change until the controller reaches the current value |

## Findings

"Observation" means the bytes or references themselves; "Inference" means a reading of decompiled control flow that has not been checked at runtime.

| # | Finding | Evidence | Status |
|---|---|---|---|
| F1 | The three log messages about scaled values and Pickup ("value … already set - skipping", "last value was not yet valid - is now valid", "lastVal / val to old deviation") are referenced only from one function, `FUN_00ab3184` (5,508 bytes, 0xab3184–0xab4707), which has 7 direct callers | String xrefs 0xab4298, 0xab4340, 0xab43f4 (PU002, PU004, PU006); callers Evidence `ev_37880e3c…` | Observation |
| F2 | In the scaled path a new value equal to the value already stored on the assignment is skipped | Skip message reference PU002 | Inference |
| F3 | The Pickup check runs only when the value mode is 2 (Scale), a numeric operand read from the assignment is not 0x82/0x83 (its meaning is not mapped yet), and a helper (`FUN_015e0f58`, 200 bytes, one caller) returns true. Codex's byte audit ([PICKUP-GLOBAL-004](pickup-global-004.en.md)) shows the helper is a compound applicability check: it first returns false when the global Pickup setting is off (byte 0x26c0b9b bit 5 is a **disable** bit written by `PrefsCSView::change_csPickupMode:`), then tests further per-assignment conditions | Value-mode byte read PU003; Evidence `ev_a2a9418a…`, `ev_aa8c61d3…`; PICKUP-GLOBAL-004 | Observation (bytes, per Codex audit); the remaining per-assignment conditions are not interpreted here |
| F4 | Each assignment keeps state bits in its flags byte (+0x39): bit 4 "controller value valid", bit 3 "picked up". The first message after a reset only sets bit 4 and is not applied | Set bit 4 PU005, set bit 3 PU011 | Observation (writes); Inference (meaning) |
| F5 | Let P be the previously stored value, N the new controller value, V the target's current value and T the tolerance. T is 0.02 times a descriptor range (upper minus lower), converted to float, multiplied and truncated toward zero; for a delta of 127 that gives 2. The assignment is picked up when min(P, N) − T ≤ V ≤ max(P, N) + T, i.e. when V lies between the previous and the new value, widened by T on both sides (exact operands per Codex's audit, CDEX151). Which runtime range feeds the descriptor is not proved | 0.02 constant built at PU007–PU010; band operands in Codex's PICKUP-BAND-005 | Observation (constant, compare structure per audit); Inference (runtime range and units) |
| F6 | A timer clears bit 3 inside the same function. Among the 78 single-byte stores to +0x39 found by a whole-copy pattern scan, only two clear bits 3 and 4 together: in `FUN_00ab573c` (a control-surface refresh path that also references channel-change and offscreen-refresh names) and in `FUN_00aba7d4` (called from `ControllerAssignmentsController::syncSelection:`). Both clear the bits only after a 16-bit field of the object matches a 16-bit selector passed by the caller (Codex's audit); that field's meaning is not known. A third mechanism was found by Codex in the preferences loader (`FUN_00abe67c`, 0xabe810–0xabe81c): it clears bits 0–4 of this byte and zeroes the stored value at +0x62 when an assignment is decoded. The mask-pattern scan above did not catch it, which again shows the list is not exhaustive. Wider stores, copies or other base registers can also change this byte, so this is **not** a complete list of writers | PU001, PU012, PU013 | Observation (these writes); Inference (triggers) |

## Consistency with the live records

| Live sample | Reading under F2–F5 |
|---|---|
| CA003: Ballad (value 64) after the controller was last at 100, then 80 → ignored | 64 is not between 80 and 100 (±2) |
| CA003: then 64 → applied (no visible change) | 64 is between 80 and 64 (±2), so it is picked up |
| CA003: Piano's first 100 applied at once | The previous controller value 64 equals Piano's 64 |
| CA003: 100 → 30 across 64 applied | 64 is between 30 and 100 (crossing) |
| CA003: Pickup off → all applied | The helper of F3 returns false |
| CA004 #1: a repeated 64 ignored | F2: same value as stored, skipped (not Pickup) |

No reset caused by a track-selection change was needed to explain these runs (Piano and Ballad behaved as the band rule predicts). This does not prove that selection changes never reset the state, because F6 is not a complete writer inventory.

## Proof limits and open points

- Semantics come from decompiled flow and must be audited at byte level (anchors file). No runtime trace exists.
- Which of the five globals is the Pickup flag (as opposed to the guard or other settings) is not determined.
- The exact operands of the 0.02 band (assignment range versus parameter range) are not confirmed.
- The triggers of `FUN_00ab573c` and `FUN_00aba7d4` are inferred from names and callers only.

## Predictions to test live (need the human and the GUI)

1. After selecting a row in the Controller Assignments window (syncSelection), the next CC is ignored once.
2. Right after a control-surface refresh or channel change, a jump far from the target is ignored until the band is reached.
3. Sending the same value twice: the second is skipped, even with Pickup off.

## Raw data (not in Git)

`Research/raw/rea/`: `pickup-ab3184.c` (pseudocode), `pickup-ab3184.objdump.txt`, `reset-ab6018.objdump.txt`, `reset-aba940.objdump.txt`, `strb39-all.txt`, and the REA JSON results (`af-*.json`, `xr-*.json`, `ss-*.json`, `rcp-*.json`).
