# ASSIGN-IDENTITY-008: independent audit of UUID and ordinal selection

[Research guide](../README.md) · [JSON](assignment-identity-audit-008.json) · [Instruction anchors](../protocol/assignment-identity-audit-12.4-anchors.tsv) · Audited claims: I5/I6 of [Claude's identity callbacks](assignment-identity-callbacks-001.en.md) · Input mapping: [ASSIGN-FIELDS-007](assignment-fields-007.en.md)

日本語要約：Claudeが訂正したUUID照合と、ID・順番による照合を、別に抽出した命令で確認した。UUIDは固定トラック用データから読まれるのではなく、プラグイン識別用リスト6の末尾16バイトから読まれる。固定トラック用リスト13は、この関数では照合方式を選ぶ条件になる。保存コピーのEQはリスト13がないので、IDと順番による経路に入ると予測される。同じEQインスタンスを維持する保証にはならない。

## Scope

Preserved Logic **12.4 / 6707**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. Root re-extracted the resolver `[0x15df8a8, 0x15dfc90)` (**1000 bytes**) and callbacks `0x15e01fc` (**104 bytes**) and `0x15e0264` (**136 bytes**) using independent Mach-O segment reads and LLVM disassembly. The resolver's `LC_FUNCTION_STARTS` interval is longer than the earlier REA-defined 944-byte body; neither boundary is treated as a whole-program proof.

This audit checks I5/I6 at operand and normal-control-flow level. It does not independently validate every Learn-side claim in the earlier note. Whole bodies, extraction scripts and their hashes remain local under `Research/raw/rea/codex-assignment-identity-008/`; the JSON is redacted. No engine session, GUI, MIDI or preferences access was used.

## Why the UUID comes from list 6

At `0x15df8cc`, X20 receives the begin pointer of assignment list 6 (+0xf8). For a negative incoming W3, the resolver checks whether list 13 (+0x1a0/+0x1a8) is non-empty and its begin is non-null. If so, it builds the UUID callback block at **SP+0x68**.

The list-13 begin initially occupies **X8**, but `0x15df9cc` overwrites X8 with a stack/by-reference pointer. It is not the identity capture. At `0x15dfa20`, `stp x9, x20, [sp, #0x90]` places **X20 at SP+0x98**, which is **block +0x30**. Callback `0x15e01fc` reads that capture and compares:

- candidate element **+0x10**;
- first list-6 entry **+0x10**.

The equality stub is `0x1afb3e0`, already bound to `operator==(CUUIDBase const&, CUUIDBase const&)` in [ASSIGN-ROUTE-003](assignment-route-003.en.md). This independently supports Claude's corrected I5. It rejects the earlier reading that the UUID key was the bytes of list 13.

If the first UUID enumeration misses, normal flow goes through `0x15dfbe0` to a second enumeration with mode 1 and the **same UUID callback**. A second miss goes through cleanup to the zero-result path. There is no branch from that miss into descriptor matching in the inspected normal CFG. This says nothing about exception callbacks or later operations elsewhere.

## Descriptor matching and the incoming ordinal

The other callback's block is based at SP. Its **+0x38** capture is the first list-6 entry, and **+0x40** is the requested ordinal. It compares candidate words +0xbc/+0xb4/+0xb8 to entry words +8/+0/+4. Only candidates whose three words match increment the match counter; selection occurs when that counter equals the ordinal. It does not read the entry's UUID.

There is one useful narrowing of I6: **a nonnegative incoming W3 is kept as the requested ordinal**. Only a negative W3 with an empty/null list 13 loads the stored entry's +0xc ordinal at `0x15dfa58`. The family-A caller previously audited in ASSIGN-FAMILY-006 passes **W3 = −1**, so the saved EQ row still uses its stored ordinal when list 13 is absent. This condition should not be generalized to every caller.

## Implication for target verification

For the historical copied EQ row (selector 0x1000, tag-6 length 32, no tag 13), the mapping and branch conditions support the following **static predictions**, not observed runtime outcomes:

| Controlled change | Expected selection consequence | What must be checked live |
|---|---|---|
| Replace the EQ with a different plug-in; no other matching EQ | Descriptor lookup misses | No unrelated parameter changes |
| Replace it with another EQ with the same IDs and ordinal | Descriptor lookup can choose the new instance despite the stored old UUID | New instance identity and actual Master Gain before/after |
| Add an otherwise identical EQ in the same enumerated section before it | The stored matching ordinal can refer to another EQ | Actual enumeration/UI order and which instance responds |
| Use the fixed-track/UUID branch, then remove that instance | Both UUID enumeration modes can miss without descriptor fallback here | Rejection, no unintended instance movement, independent readback |

A descriptor plus ordinal is an operational selection rule, not a persistent instance identifier. A complete target proof must bind the current document, track, plug-in slot/instance, parameter and readback; a historical record or successful MIDI send is insufficient. No `verified` capability changed.
