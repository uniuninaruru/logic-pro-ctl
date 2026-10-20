# ASSIGN-FIELDS-007: serialized variable fields reach assignment lists

[Research guide](../README.md) · [JSON](assignment-fields-007.json) · [79 instruction/data/import anchors](../protocol/assignment-fields-12.4-anchors.tsv) · Previous: [ASSIGN-FAMILY-006](assignment-family-006.en.md), [ASSIGN-TARGET-001](assignment-target-001.en.md) · Complementary: [CS reader endian gate](cs-reader-endian-gate-001.en.md), [Claude's identity callbacks](assignment-identity-callbacks-001.en.md)

日本語要約：保存コピーの可変長データから、実行時の割り当てリストへ至る読み込み処理を接続した。EQの識別用32バイトはタグ6からリスト6へコピーされ、4件とも固定トラック用のタグ13はない。4件が通る初期化経路では、コピー済みのクラス・トラック選択値・パラメーターコードをこの補助関数が変更しないことも確認した。現在のLogicの割り当てや値を実機で確認した結果ではない。

## Scope

Preserved **Logic 12.4 / build 6707** arm64 copy, SHA-256
`48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`.
Two `LC_FUNCTION_STARTS` intervals were extracted independently of the native analysis engine:

| Helper | Interval | Bytes | Purpose in this report |
|---|---|---:|---|
| `0x15dc284` | `[0x15dc284, 0x15dc49c)` | 536 | Select a serialized variable tag, allocate/resize its destination and copy its bytes |
| `0x15dbff0` | `[0x15dbff0, 0x15dc284)` | 660 | Resolve/clear the controller pointer after fixed-prefix copying |

These are report labels, not recovered original names. Raw instructions, reproducer scripts and whole-copy row probes remain in ignored `Research/raw/rea/codex-assignment-fields-007/`. The JSON records their hashes. No native import, Logic process, GUI, live preferences or settings write was used.

## Variable tags and live lists

The constructor already traced in ASSIGN-FAMILY-006 calls `0x15dc284(destination, temporary, id)` separately for IDs 1 through 16. The helper:

1. Starts at **temporary +0x66**, equivalently **RDAF payload +0x2e** after the decoder's +0x38 prefix.
2. Reads a one-byte tag. A zero tag terminates the scan. The following length uses MSB-first seven-bit groups; bit 7 indicates another length byte. For example `81 00` is 128, rather than 1.
3. Skips the indicated content for a different tag. At the **first matching tag**, it retains the content pointer and decoded length.
4. Calls `0x15dc49c(destination, id, length)` and, if the returned pointer is non-null, calls the exact `_memcpy` import with that pointer, the content pointer, and the decoded length. The copy call is at `0x15dc358`; its stub `0x1afbb54` binds through `0x228d9c0` to `/usr/lib/libSystem.B.dylib`'s `_memcpy`.

The earlier accessor proof gives the destination vector layout `+0x68 + 24*id` (begin/end/capacity). Therefore tag **6** populates the list whose begin/end/capacity are **+0xf8/+0x100/+0x108**, and tag **13** populates **+0x1a0/+0x1a8/+0x1b0**. Its table gives minimum nonzero lengths of 32 and 16 respectively. These are minimum allocations, not caps: the requested copy length remains the decoded length.

For ID 1 the helper also checks whether its destination list was already non-empty. That can trigger later notification work. General calls may also enter a class-5/pinned-mode context branch. The helper is not a pure byte getter, and its lack of an explicit source-end argument is **not** evidence that malformed inputs are safe.

## The copied rows

This reuses the strict, historical `s0b.bin` copy from ASSIGN-FAMILY-006, SHA-256
`d80b27bb49b6c65e7841a36a5e6ee95dafdb61e7ab110605a75e20600de331f4`.
Opaque content, names and UUIDs are omitted.

| RDAF record offset | Historical GUI association | Tag 6 | Tag 13 | Stored selector | Controller word at payload +0x16 |
|---:|---|---|---|---|---|
| 14714 | CC23 / EQ | Payload +0x44, length 32 | Absent | `0x1000` | 0 |
| 14841 | CC22 / volume | Absent | Absent | `0x1000` | 0 |
| 14937 | CC21 / pan | Absent | Absent | `0x1000` | 0 |
| 15021 | CC20 / pan | Absent | Absent | `0x1000` | 0 |

The EQ's 32 bytes thus have a concrete route to the list consumed by the plug-in resolver in Claude's identity work. A stored list's existence is distinct from successful current target resolution; the snapshot is historical, and another track or plug-in can occupy the runtime route.

## Bounding the post-copy controller helper

`0x15dbff0` reads the 32-bit word at destination **+0x4e**. Its high byte selects the path: values below `0xff` clear the controller pointer at **+0x30** and the controller-derived byte at **+0x218**. A class-5 selector with high nibble `0xb000` may then enter context-update work. The `0xff` path can look up a controller and adjust its reference count; that path is outside the copied-row conclusion.

All four copied rows have word zero and selector `0x1000`. Their path is:
`0x15dc000 → 0x15dc068 → 0x15dc070 → 0x15dc088 → 0x15dc1cc → return`.
It contains no call. The helper has no direct store to **+0x3a, +0x3e or +0x40** anywhere in the inspected interval. Thus the previously established prefix mapping is not undone by this helper on these four rows. This does not claim general absence of later runtime mutation or prove allocator/exception paths of the constructor.

The decoder's endian gate is now explained by CS-READER-001: these MROF/FCSS copies select mode 0, so its byte-swapping branch is skipped. The research parser still requires a consistent top-level declared length as a conservative snapshot-integrity rule; that rule is stricter than Logic's observed reader and remains appropriate for copied evidence.

## Targeted validation and remaining gaps

A separate restricted instruction-text interpreter replays the helper from first tag read through length selection, stopping before allocation/copy. It was compared with an independently written base-128 reference on **672 cases**: **608 synthetic** and **64 copied-row/requested-ID combinations**, with **zero mismatches**. Synthetic cases include duplicate tags, missing tags, immediate termination, and lengths 0, 1, 16, 32, 127, 128, 255, 16383 and 16384. It visited 28 instruction sites.

This is not native execution, a full constructor model, a malformed-input safety test, or a proof for overflowing lengths. The copy and vector association come from the separate instruction/import witnesses. No product capability or `verified` result changed.

Still required: independent review of the resolver's UUID/descriptor register flow, GUI assignment/inventory restoration, same-instance selection proof, and MIDI-before/after readback of the requested parameter value. A valid copied record alone proves none of those runtime conditions.
