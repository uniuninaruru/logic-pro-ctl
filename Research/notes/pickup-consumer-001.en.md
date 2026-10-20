# PICKUP-CONSUMER-001: where Pickup mode acts on generic controller assignments (Logic 12.4)

[Research guide](../README.md) · [Instruction anchors](../protocol/pickup-consumer-12.4-anchors.tsv) · Live records: [CA002](../experiments/EXP-CA-002-variable-cc-and-pickup.en.md), [CA003](../experiments/EXP-CA-003-value-mode-pickup-ab.en.md), [CA004](../experiments/EXP-CA-004-channel-eq-gain-calibration.en.md)

日本語要約：汎用のコントローラ割り当てで、ピックアップモードが効く処理を Logic 12.4 の複製から静的に特定した。値を適用する 1 つの関数の中で、①直前と同じ値は捨てる、②「スケール」モードかつ設定がオンのときだけピックアップを調べる、③割り当てごとの状態ビット（値が有効・拾った）を持つ、④現在値の周り「範囲の 2%」の帯に、直前か今回のコントローラの値が入れば拾う、という形に見える。この読みは、CA002〜CA004 の実機の結果をすべて説明する。ただし逆コンパイルからの推論で、実行時の確認ではない。

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
| F3 | The Pickup check runs only when the value mode is 2 (Scale) and a small helper returns true. That helper (`FUN_015e0f58`, 200 bytes, one caller) touches exactly the same five guarded globals as `PrefsCSView::change_csPickupMode:` (0xaa3670, the Settings checkbox action) | Value-mode byte read PU003; analyze-function Evidence `ev_a2a9418a…`, `ev_aa8c61d3…` | Observation (shared globals); Inference (helper = global Pickup setting) |
| F4 | Each assignment keeps state bits in its flags byte (+0x39): bit 4 "controller value valid", bit 3 "picked up". The first message after a reset only sets bit 4 and is not applied | Set bit 4 PU005, set bit 3 PU011 | Observation (writes); Inference (meaning) |
| F5 | The tolerance is 0.02 times the value range. The assignment is picked up when the target's current value lies within that band around the previous or the new controller value, which covers both reaching and crossing | 0.02 constant built at PU007–PU010 | Observation (constant); Inference (operands, band test) |
| F6 | A timer clears bit 3 inside the same function. Two other functions clear bits 3 and 4 together: `FUN_00ab573c` (a control-surface refresh path that also references channel-change and offscreen-refresh names) and `FUN_00aba7d4` (called from `ControllerAssignmentsController::syncSelection:`) | PU001, PU012, PU013; whole-copy scan found 78 byte stores to +0x39 and only these two clear both bits | Observation (writes); Inference (triggers) |

## Consistency with the live records

| Live sample | Reading under F2–F5 |
|---|---|
| CA003: Ballad (value 64) after the controller was last at 100, then 80 → ignored | 100 and 80 are both outside the band around 64 |
| CA003: then 64 → applied (no visible change) | The new value is inside the band, so it is picked up |
| CA003: Piano's first 100 applied at once | The previous controller value 64 equals Piano's 64 |
| CA003: 100 → 30 across 64 applied | The band from 30 to 100 contains 64 (crossing) |
| CA003: Pickup off → all applied | The helper of F3 returns false |
| CA004 #1: a repeated 64 ignored | F2: same value as stored, skipped (not Pickup) |

A track-selection change did not reset the state in these runs (Piano and Ballad behaved as the band rule predicts), which agrees with F6 finding resets only in the refresh and Controller Assignments selection paths.

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
