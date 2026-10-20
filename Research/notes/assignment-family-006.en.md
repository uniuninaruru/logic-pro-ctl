# ASSIGN-FAMILY-006: copied parameter probes and the serialized-prefix bridge

日本語概要: 保存済みの候補行を16-bit/+6と32-bit/+8で読み分けると、EQ・Volume・Panの値は0x4020・7・10となる。従来の32-bit/+6は重なる範囲を読んでいた。読み込み先は一時バッファで、その後のコンストラクタが同じオフセットへ固定部をコピーすることも命令で確認した。ただしバイト順・旧コード変換・後続ヘルパーがあり、最終的な対象識別やプラグイン実体の同一性を保証する形式とは扱わない。

[Machine-readable record](assignment-family-006.json) · [Instruction anchors](../protocol/assignment-family-12.4-anchors.tsv) · [Copied row table](../protocol/assignment-family-copied-rows.tsv) · [Earlier strict inventory](../static-analysis/SA-CS-PREFS-001.en.md) · [Parameter cache](assignment-route-003.en.md)

## Read-only parser change

`Tools/research-scripts/cs_assignments.py` now adds two **overlapping raw probes**, `u16le_payload_6` and `u32le_payload_8`, alongside the existing `u32le_payload_6`. It retains strict copied-file validation, live-file rejection, omitted names/opaque contents and `semantics_confirmed: false`. No candidate becomes an active assignment or verified target merely because its bytes match. The affected21-test suite passes.

The earlier inventory records the prior parser revision; this note binds the new parser hash. No product/daemon/MCP operation or preference-write path was added.

## Four copied candidates

The strict historical `s0b` copy has SHA-256 **`d80b27bb49b6c65e7841a36a5e6ee95dafdb61e7ab110605a75e20600de331f4`**. Existing GUI associations identify these candidate rows; bytes alone do not identify active assignments, input ports or current Logic targets.

| GUI-associated CC / label | Record offset | Raw32 +6 | Raw16 +6 | Raw32 +8 | If loaded as dispatcher operand v |
|---|---:|---|---|---|---|
| 23 / EQ Master Gain |14714|0x40201000|0x1000|0x4020|matches family-A mask condition|
| 22 / Volume |14841|0x00071000|0x1000|0x7|within small switch interval|
| 21 / Pan |14937|0x000a1000|0x1000|0xa|within small switch interval|
| 20 / fixed Pan |15021|0x000a1000|0x1000|0xa|within small switch interval|

All four also have raw class probe5, raw mode bytes2/2/2/4, and signed16 multiply probe100. Values agree with the existing class/selected-track/value-mode/multiply observations. Agreement is not a complete serialization or live-identity contract.

The bounded variable fields are tag1 length3 and tag3 with differing name lengths; tag16 length16 appears in all four. Only the EQ candidate also has **tag6 length32**. Names and opaque contents remain omitted. The mapping of these variable tags into live vectors is a separate uninspected helper, so tag6 is not promoted here to a learned plug-in identity.

## The writer serializes a buffer, not an arbitrary memory dump

All native evidence uses preserved **Logic12.4/6707 ARM64**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`.

Writer **`0xabe8d4`** calls `0x85d538(assignment)` and gets a serialized buffer and length. It writes an RDAF header using `length−0x38`, then sends **buffer+0x38** to exact import **`CFileIO::Write`**. Its LC_FUNCTION_STARTS interval is488B; the REA defined body was456B. This proves the buffer origin, not that the original live object is dumped unchanged. The producer `0x85d538` is uninspected.

The outer reader `0xad7c30` delegates a matching RDAF record to **`0xabe67c`**. Its pointer-array growth copy is unrelated to the record-to-object field mapping.

## The decoder and constructor provide a bounded prefix connection

Decoder **`0xabe67c..0xabe8d4`**,600B by LC_FUNCTION_STARTS (REA580B), allocates `payloadLength+0x38` with exact `_NewPtrClear`, zeroes the first0x38 bytes, and passes **TEMP+0x38** to exact **`CFileIO::Read`**. It bounds the read against file state and zeroes any remaining tail. File byte `+0xcc` bit1 enables byte swaps on several fields; its connection to the copied file's endian header remains a gate.

The decoder may remap selected legacy class5 codes in0x180..0x18a. The four raw parameter candidates0x4020/7/a/a lie outside that remap set under the no-swap interpretation. It also clears TEMP `+0x39` bits0..4 and zeroes TEMP `+0x62` before constructing a new object.

At `0xabe888..0xabe89c` it allocates a new0x220-byte object and calls **`0x15dc8a8(new,TEMP)`**. That constructor's924-byte interval directly copies source `[0,0x30)`, `[0x30,0x60)` and overlapping `[0x5e,0x66)` to the **same destination offsets**. Thus the fixed copied region reaches destination `[0,0x66)` at this construction stage. Payload k in the first0x2e bytes maps to TEMP `+0x38+k` and then the same destination offset, after loader fix-ups.

| Copied probe | Constructor-stage offset | Existing getter observation |
|---|---|---|
|u32 +2|+0x3a|class word|
|u16 +6|+0x3e|packed track mode/operand; context-dependent command field|
|u32 +8|+0x40|raw track-parameter field|
|byte +0x13|+0x4b|value-mode low3 bits|
|i16 +0x14|+0x4c|multiply getter scales by0.01|
|u32 +0x2a|+0x62|cleared by loader; do not use as target-value readback|

After the direct copy, **`0x15dbff0`** is called and variable fields1..16 are delegated to **`0x15dc284`**. Their complete effects are not audited here. This record proves the copy stage; it does not prove every final live field remains unchanged, nor equate TEMP storage with the live object's vector representation. The decoder starts variable-field scanning at TEMP+0x66, corresponding to payload+0x2e, consistent with the copied rows' tag1 beginning there.

## The current dispatcher supports the candidate distinction

`0x15de134` loads v from its X0 argument `+0x40`. Early comparison is with literal **`0x3fffffff`**, not a read from a cache variable. The class5 path also needs a non-null supplied entry before family selection. Family-A condition is `(v & 0xffffc000)==0x4000`; its branch further requires a nonempty Assign `+0xf8/+0x100` range before `0x15df8a8`, passing W3=−1. Matching the bitmask alone does not prove resolution.

The copied EQ probe0x4020 matches this mask. The Volume7 and Pan10 probes fall within the small dispatch range; not all gates or table destinations are audited here. Other dispatcher branches have their own conditions. In particular, the `v>>8 <0x23` branch goes to0x15de4d8; the0x15dfc90 call is on the non-low path after earlier family tests.

Claude's [companion identity note](assignment-identity-callbacks-001.en.md) now reports learn-side construction of descriptor/ordinal/UUID entries and conditional UUID versus descriptor lookup. Those bodies are outside this independent byte audit. This note makes no replacement-retargeting claim. The next gates are complete variable-field construction, actual identity ownership, current document/track/slot/instance/parameter binding, and same-target value readback.
