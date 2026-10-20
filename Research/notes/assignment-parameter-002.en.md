# ASSIGN-PARAMETER-002: parameter descriptions and typed pinned-key comparison

日本語概要: Logic 12.4の `parameterPath` は文字列を配列へまとめ、`parameterKind` はクラス別の判定値を返す。これだけではプラグイン実体やスロットの識別にはならない。一方、固定先の16バイトを渡す解決関数から、MACoreの `CUUIDBase` 同士の比較への接続を確認した。保存形式・永続性・最終的な対象解決・実機効果は引き続き未確認。

[Machine-readable record](assignment-parameter-002.json) · [Prior storage-to-consumer proof](assignment-target-001.en.md) · [Byte anchors](../protocol/assignment-parameter-12.4-anchors.tsv) · [REA handoff](rea-ghidra-handoff-001.en.md)

## Scope

Offline evidence from preserved **Logic 12.4 / 6707 ARM64**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. Only two metadata-bound `WrappedAssign` method intervals (**892 bytes**) and the prior mode11 callee (**932 bytes**) were expanded. Exact LLVM bytes, LC_FUNCTION_STARTS bounds, ObjC selectors, chained fixups and import stubs were checked. These intervals are not a complete CFG or audit of lower callees. Raw scripts and full captures are local under `Research/raw/rea/codex-assignment-parameter-001/{fields,consumer}/`.

No analysis engine, Logic process, GUI, MIDI, preference or product operation was run. Claude retains the sole REA engine; requests for new dossiers use that existing session.

## `parameterPath` exposes composed components

`parameterPath` **`0x699b64..0x699dac`**, 584 bytes, calls `assign` and then **`0x15e0428(Assign,0x01000010,globalBuffer)`**. Fixup-bound `NSString.stringWithUTF8String:` makes a string from the buffer at `+0x40`.

The body reads **32 bits** at Assign `+0x3a`. For a value other than5, it returns an `NSArray` containing that string. For5, it calls the previously audited track resolver `0x15dcfa4`, plus unexpanded `0x15ddf84`, `0x597f1c` and `0x15e7134`. It constructs a second string and tests its `length`: a nonempty string produces three array elements; an empty one produces two. The first element is the return from `0x15e7134`; the last is the common-helper string. Label meanings and the exact returned type from that unexpanded helper remain unknown.

This is a concrete description-construction path. It does not establish a stable ID namespace or an independently validated document/track/slot/instance tuple. The body initializes and writes global buffers; lower helpers may resolve targets or have side effects. Calling this selector is not proven to be a pure read.

## `parameterKind` returns a classification, not a target handle

`parameterKind` **`0x699dac..0x699ee0`**, 308 bytes, reads the same32-bit classification word.

| Classification word | Direct body behavior |
|---|---|
| 4, 5, 11 | Calls `0x15e0428(Assign,0x00022007,stack)`; returns1 iff `(i32[stack+0x10] - i32[stack+0x08] + 1) == 2`, else0 |
| 8, 9 | Returns2 |
| 10 | Calls `0x159f988` with signed16 `Assign+0x3e` and address `0x27586d8 + min(u8[Assign+0x218],19)*0xc0`; returns1 iff helper result equals2, else0 |
| Other values, including unsigned values above11 | Returns3 |

The arithmetic is 32-bit; no enum names or range semantics are inferred. In particular `+0x218` is **unnamed**, not a proved plug-in slot. Shared helper **`0x15e0428`** is the next bounded target for tracing description/range information to a backend. Its body has not been inspected in this record.

## The pinned payload reaches `CUUIDBase` equality

The prior setter copies exactly16 bytes into field13, whose begin/end fields match mode11. That mode passes its begin pointer in **X2** to **`0x15a1b60..0x15a1f04`**, 932 bytes. This callee saves X2 and later passes it as **X1**, with a candidate entry pointer as **X0**, to **`0x1afb3e0`** at **`0x15a1d94`** and **`0x15a1e4c`**.

The exact ADRP/LDR/BR stub loads chained import **`0x228fc00`**, bound to MACore symbol **`__ZeqRK9CUUIDBaseS1_`**. Removing the Mach-O symbol prefix and demangling gives **`operator==(CUUIDBase const&, CUUIDBase const&)`**. This proves a typed equality interface for those candidate/payload prefixes; it does not prove an Apple UUID byte encoding, serialized format, persistence or plug-in instance identity.

The first comparison accepts a nonzero W0; the second accepts bit0 set. Failed comparisons continue searching. The initial fast scan instead invokes an **opaque block at `0x7663cc`** over0x48-byte records; equality semantics of that path remain unaudited.

An invalid, out-of-range or null encoded entry can select the first pointer for a comparison. **That candidate must still pass the comparison**; this branch does not by itself accept an unrelated target. This differs from treating every fallback as success.

No match constructs packed **X3=`0xffffffff00000000`**, W4=0. Both match and no-match paths then call **`0x15a16a8`**. Its normalization/fallback semantics remain unaudited, so final fail-closed behavior and the returned target are unknown. Independent review reproduced the932-byte interval, registers and comparison branches; import binding was verified separately by the root probe.

## Next gates

Reuse Claude's retained REA session for `0x15e0428` metadata/xrefs and the backend-selecting branch if present. Keep Pickup as Claude's primary lane; avoid a second cold import. Candidate helpers `0x7663cc` and `0x15a16a8` matter if a complete pinned-target contract is needed, but are not expanded here.

The acceptance gate remains the same: explicit assignment class/mode, same-document target identity, plug-in slot/instance and parameter namespace, mismatch rejection, and same-target value readback. Neither these descriptive methods nor a typed equality call creates a new `verified: true` capability.
