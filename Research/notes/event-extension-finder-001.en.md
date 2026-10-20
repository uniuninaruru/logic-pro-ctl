# EVENT-EXT-001: the extension-unit finder `FUN_019c22cc` (Logic 12.4, static)

[Research guide](../README.md) · [Instruction anchors](../protocol/event-extension-12.4-anchors.tsv) · Requested for Codex's [ASSIGN-FILTER-014](assignment-filter-014.en.md) (board CDEX195)

日本語要約：16 バイト単位の内部レコードから、指定した型の「拡張ユニット」を探す関数を、Logic 12.4 の複製から静的に読んだ。先頭語のビット 63 が拡張ユニットの印で、型は最上位バイトのビット 6 を落とした値で比べる（0xB8 と 0xF8 はどちらも 0xB8 として一致）。返り値は、一致したユニットそのものの番地か NULL で、番号やオフセットではない。第 4 引数が 0 でなければ、先頭イベント自身が占めるユニット（1〜5 個）を飛ばしてから探す。推論であり、実行時の確認ではない。

## Scope

| Item | Value |
|---|---|
| Image | Preserved copy `Research/raw/binaries/Logic12.4-6707.arm64`, sha256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda` |
| Read | `FUN_019c22cc` (688 bytes, whole body) and its helper `FUN_019c257c` (348 bytes, whole body); two 16-byte tables; nothing else |
| Tools | REA 6.7.0 / Ghidra 12.1.4 retained session for names and bytes, llvm-objdump; 30 of 30 anchors hold |
| Call studied | `(record, 0xB8, 0, 1)` as used before Codex's 014 filter |

## Findings

| # | Finding | Anchors | Status |
|---|---|---|---|
| E1 | The record is a run of 16-byte units. A unit whose first 8-byte word has bit 63 set is an extension unit. A head word above 0x3ffffffeffffffff (signed) returns NULL at once | EF001–EF003, EF010, EF011 | Observation |
| E2 | Matching key of a unit: its top byte with bit 6 cleared; when the top byte is 0xA0, the key is instead 0xA000 plus the sign-extended byte 6 of the word with bit 6 cleared. The scan returns the first unit whose key equals the requested type and stops with NULL at the first unit without bit 63. So a request for 0xB8 matches top bytes 0xB8 and 0xF8 | EF020–EF026 | Observation |
| E3 | The return value is the address of the matching unit (inside the record, or inside a linked chain, E4), not an index or a normalized offset; a caller reading "+8" reads that unit's second 8 bytes | EF025 | Observation |
| E4 | Base of the scan: normally record + 0x10. For a type-2 head (bits 4–7 = 2, not an extension), when the unit right after the head's span has key 0xBD (top byte 0xBD or 0xFD), the scan base is a separate chain: the low 32 bits of that unit index a pointer vector in a global singleton (0x2783048, created on first use), and the chain is read through that entry. The base unit must be an extension unit, otherwise NULL | EF004–EF011 | Observation (loads); Inference ("chain" wording) |
| E5 | With the fourth argument 0 the scan starts at the base. With it non-zero (the studied call), the helper `FUN_019c257c` gives the head's span n, and n − 1 units are skipped first, so the scan starts at record + 16·n. n is 2 for head types 0x12 and 0x32, 5 for 0x24, otherwise a table value by bits 4–7 (0, 3, 5, 3, 1, 1, 0, 1, 1, 2, 1, 1, 1, 1, 1, 0 at 0x1d61ad0); n = 0 gives NULL. Exceptions read: a type-7 head with byte +0xc in 0x3B–0x3D gives NULL; for a type-2 head whose next unit is a 0xBD link, nothing is skipped | EF012–EF019, EF027–EF030 | Observation (branches); the duration test inside the helper, which can make n = 0, was not interpreted |
| E6 | The third argument only matters for a type-6 head with byte +0xc = 0x7F (it changes the skip to one unit or accepts n = 0); for the studied call (0) it has no effect | EF012 region | Observation |

Note: the finder's own head-span table at 0x1d61ae0 (1, 2, 5, 3, 1, 1, 1, 1, 1, 2, 1, …) differs from the helper's table; only the helper's value is used for skipping.

## Proof limits

- No caller other than the one Codex named was read; what the 0xB8 unit means is Codex's 014 scope.
- The helper's floating-point duration test (which decides n = 0 for zero-length events) is left uninterpreted.

## Raw data (not in Git)

`Research/raw/rea/x0x19c22cc.objdump.txt`, `x0x19c257c.objdump.txt`.
