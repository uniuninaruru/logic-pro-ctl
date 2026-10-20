# ASSIGN-RECORD-012: value packing precedes internal event handling

[Research guide](../README.md) · [JSON](assignment-record-012.json) · [187 instruction/data anchors](../protocol/assignment-record-12.4-anchors.tsv) · Previous: [ASSIGN-BACKEND-011](assignment-backend-011.en.md)

日本語要約：前回見つけた値の転送先をさらに調べた。小さな値関数は、EQ自体を変更する関数ではなく、内部レコードへ値を格納する処理だった。対象経路では32ビット値を書き、フラグ1ビットを消すだけで、別の関数を呼ばない。そのレコードが後段へ渡される経路も確認した。現在のEQへの適用と独立した読み戻しは引き続き未確認である。

## Scope

Preserved Logic **12.4 / 6707**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. Five small `LC_FUNCTION_STARTS` intervals totaling **2276 bytes** were saved from direct copy/LLVM reads: `0x2fec34` 180B, `0x1a26eec` 436B, `0x199abf8` 524B, `0x199ae04` 300B, and `0x59e714` 836B. Semantic claims below concern the primary value path, predicate and selected dispatcher flow. The two `0x199…` helpers are retained as context; their other record formats are not interpreted here.

The curated witnesses cover **744 instruction bytes** plus a 16-byte constant. Raw bodies/replay scripts stay in ignored `Research/raw/rea/codex-assignment-record-012/`; their hashes are in the JSON. No engine, live process, preferences or MIDI was accessed.

## The primary path constructs a record

ASSIGN-BACKEND-011 showed the chosen call site supplying a non-null descriptor at SP+0xb0. The forwarding wrapper therefore passes descriptor-null flag **W7 = 0** to `0x594890`. At `0x594be4`, that selects the call **`0x1a26eec(record, scaled_integer)` at 0x594c1c**, instead of the descriptorless helper.

The record is at global **0x2640128**. For the bounded plug-in path of 011, the caller constructs:

| Record field | Instruction-level observation |
|---|---|
| +0 | `(section_bit ? 0x40 : 0x50) OR nonzero index-plus-one nibble` |
| +0xc | Low-16 parameter index, written by this record-format path |
| +0x10 | Initial 16-byte template from `0x1cb5b10`; its first qword has high byte 0xb8 |
| +0x17 | Marker byte 0xb8 |
| +0x15 | Marker byte 1 |
| +0x18 | Low 32 bits of the caller's input target token |

These are internal record fields. Their presence does not establish an external transport, a persistent instance identity, or successful plug-in application.

## What the value helper actually changes

`0x1a26eec` has no call instruction in its complete 436-byte interval. For record tags **0x41–0x4f** and **0x51–0x5f**, its selected path makes exactly these mutations:

```text
u32[record + 0x8] = low32(value_argument)
u8 [record + 0x1] &= 0xdf
```

The first byte's bit 7 is clear, so the function skips the alternate formats' floating conversion and packing branches. Even when byte +0xc equals 0x7f, the preliminary type-0x60 special case does not apply to these tags. This supports a specific conclusion: at the caller's known global-record address, the helper encodes the value; it is not a direct Audio Unit parameter setter.

A restricted instruction-text interpreter compared this path with an independent byte-array reference on **5760 cases**, with **zero mismatches**, visiting **19 instruction sites**. Cases vary both tag families, all 15 nonzero low nibbles, four parameter words, six raw values, four flag bytes and two header-sign variants. All 64 model bytes outside the allowed value/flag mutations remain identical. This tests the local arithmetic and preservation rule, not a live record or a plug-in.

## The next handoff and the separate predicate

The backend calls **`0x59e714(context, record, target, input_token, 5)` at 0x594d78**. That dispatcher can tail-forward to **0x781438**. The constructed extension's high byte 0xb8 selects its longer path: it calls opaque helper `0x28ea60(stack_address, record, 0)`, then calls the same **0x781438** with restored arguments. Later mask/condition processing can invoke a block whose entry is **0x59ea58**; its fanout meaning is not established here.

The small helper **0x2fec34** from 011 is a container/type/flag predicate. Its true return makes the backend exit early. Its vector load uses an index from the object at +0x4a, rather than the incoming W1 ordinal. It is therefore not proof that the requested slot contains the original instance. No UUID equality or instance matching is established by this predicate.

## Validation and remaining gap

**187/187 byte/text/data anchors** hold, and source hashes/JSON/local links were checked. The research parser and CI were unchanged; the earlier affected-test checkpoint is reused.

The next bounded target is the **1560-byte handler at 0x781438**, whose body has not been expanded in this report. Actual event consumption, target lifetime/cache validity, the ultimate parameter write and physical units remain unknown. `verified` still requires a current same-target proof and independent before/after value readback. No new product capability is implied by reaching this internal handoff.
