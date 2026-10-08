# MIDI assignment automation: first verified Channel EQ operation

日本語概要: 最初の完成目標を「Channel EQの値を指定し、割り当て・送信・実際の値まで確認する」に絞る。設定のコピーの取得と比較は実装済み。GUI Learnの自動化、GUIによる復元、プラグイン変更時の識別、値の読み戻しはこれから実証する。

Priority accepted from the human on 2026-10-08. Follow [AGENTS](../../AGENTS.en.md). Test project only; one condition per experiment; preserve unknown-cause state rather than blindly normalizing it. Controller settings are changed inside Logic. Direct CS-file writes are excluded.

## Current evidence and next work

| Area | Established | Next acceptance |
|---|---|---|
| Read-only inventory | [CS reader](../static-analysis/SA-CS-PREFS-001.en.md): bounded framing, hashes, multiset differences; 21 tests | Obtain consistent copied snapshots before/after GUI changes; relate exact observed row to serialized candidates |
| GUI Learn | [CA002](../experiments/EXP-CA-002-variable-cc-and-pickup.en.md): operator created variable CC assignments; official Learn sequence documented | Automate one new named parameter assignment; inspect the resulting Expert row and input port; stop Learn; remove only that new row |
| Restoration | s0b→s2 RDAF multiset restored after GUI deletion of one KC row | Re-create a removed owned row through GUI; verify fields and effect, then return the initial owned state; never overwrite prefs |
| Plug-in identity | Current getter/target models and GUI labels are clues | Bind document, track, slot, plug-in identity, parameter label/unit/range; reject ambiguity and revalidate after replacement, reorder or document change |
| EQ value | [CA002](../experiments/EXP-CA-002-variable-cc-and-pickup.en.md): CC23 samples +24.0 / −24.0 / +0.2 dB, GUI readout | Establish an automation-readable actual value, tied to the same instance; several values and at least two test tracks; preserve initial value |
| Execution | [MCP adapter](../../docs/mcp.md) delegates existing commands to the CLI/logicd core | Add a generic-parameter operation only after target, mapping and readback are proved; reuse shared validation/result handling |

Claude owns GUI/live observations and Learn/restore. Codex owns copied-file interpretation, internal-route mapping and read-only AX discovery. Coordinate GUI/MIDI ownership on the local board before mutation. `Tools/research-scripts/logic-plugin-inspect.swift --pid <observed PID>` reads parameter attribute candidates only; a window index/tree path is **not stable instance identity**. Initial discovery found the test project but no open EQ window, so no automated value provider is established yet.

## Target and assignment record to prove

An approved target needs document identity, track identity, strip type, plug-in slot, actual plug-in identity/version, and parameter identity/label/unit/range. Track names, menu indices, CC number, a window title or AX tree path alone are insufficient. If identifiers are only valid within a live session, explicitly limit their lifetime and invalidate them on replacement or document change.

An assignment inventory needs input-port identity, channel/status/controller number, literal vs variable pattern, assignment target/class, mode, multiplier, range, pickup/resolution and feedback fields. Capture values from Expert View where readable; raw CS candidates supplement evidence. Do not infer target identity or restoration from a matching opaque payload hash alone.

Use Apple's [Easy View Learn sequence, guide 12.3](https://support.apple.com/guide/logicpro/assign-and-delete-controllers-in-easy-view-ctls71c31855/12.3/mac/15.6) and [Expert View, guide 12.3](https://support.apple.com/guide/logicpro/controller-assignments-expert-view-ctls71c3162b/12.3/mac/15.6). Record differences observed in installed 12.4. Use app-specific controls; check the front application before any display-level input batch.

## Result contract to implement after proof

Keep existing product `verified` semantics. The following is a **proposed** extension, not a current endpoint or proof of a new capability:

```json
{
  "verified": false,
  "stages": {
    "delivery": {"state": "confirmed", "scope": "local_midi_send"},
    "assignment": {"state": "confirmed", "scope": "expert_row_and_target"},
    "value": {"state": "unverified", "reason": "readback_unavailable"}
  }
}
```

Local MIDI send success cannot prove Logic acceptance or value change. Assignment confirmation needs current row/target evidence. Value verification needs an observed post-operation value from that exact target with explicit units and tolerance. Preserve evidence provenance and operation timestamps. If identity changes between write/readback, report an uncertain result; do not read a replacement instance and claim success.

Toggle key commands get no automatic retry after an uncertain outcome. [KC002](../experiments/EXP-KC-002-midi-to-key-command-loop-browser.en.md) observed nonzero CC toggling, zero doing nothing. An explicit user-requested second action is a new action, not a retry. No alternative-route fallback after uncertain mutation. Existing idempotency/target/session/deadline checks remain in the shared execution core.

## Numerical accuracy and completion criteria

7-bit CC has at most 128 distinct values; a requested value may not be representable. The observed EQ endpoints suggest a 48/127 ≈ 0.378 dB step **if** the whole mapping is linear. Under that unproved model −6 dB maps near CC48, about −5.86 dB. Do not advertise exact −6 dB or silently relax verification: calibrate the mapping and either report the realized value with an accepted tolerance or reject an unattainable exact request. Pickup may prevent an otherwise delivered value from applying; observed pickup behavior is not a universal synchronization rule.

The first completed demo must:

1. Resolve a natural-language EQ request to one unambiguous test-project track/slot/parameter.
2. Inspect or Learn the required assignment through GUI and verify its current fields.
3. Read the initial actual value; send the planned CC once with explicit resolution/tolerance.
4. Read the same instance's actual value; report delivery, assignment and value independently.
5. Repeat at several values and on two test tracks; test ambiguity and plug-in replacement rejection.
6. Restore reversible owned changes through Logic and record before/after evidence.
7. Expose the verified operation through logicd and a thin MCP/CLI adapter using the same execution contract.

GUI automation, generic plug-in readback and the new product operation are pending. Broad new tool menus or expanded CI are not prerequisites for this milestone.
