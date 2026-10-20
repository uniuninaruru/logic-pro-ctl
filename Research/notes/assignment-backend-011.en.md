# ASSIGN-BACKEND-011: a learned plug-in code becomes a slot/index dispatch

[Research guide](../README.md) · [JSON](assignment-backend-011.json) · [219 instruction anchors](../protocol/assignment-backend-12.4-anchors.tsv) · Prior: [target matching](assignment-identity-audit-008.en.md), [parameter cache](assignment-route-003.en.md), [Pickup band](pickup-band-005.en.md)

日本語要約：保存値0x4020とMIDI受信後のパラメーター処理を接続した。対象プラグインが見つかると、パラメーター番号0x20に、実際に見つかった位置と列挙モードの情報を付けて渡す。対象が見つからなければ0x10cを返し、受信側がその値を除外する。値を渡す小さな補助関数には整数の拡大処理もある。ただし、さらに先のプラグイン書き込みと実値の確認は未完了であり、実機の成功とは扱わない。

## Scope

Preserved Logic **12.4 / 6707**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. Existing `ab3184` REA pseudocode/listing was reused to select the concrete forwarding call. Root independently extracted three `LC_FUNCTION_STARTS` intervals totaling **2000 bytes**: `0x5972d8` 268B, related `0x5971e0` 248B, and downstream `0x594890` 1484B. Claims below use the first wrapper and selected downstream instructions; the related function is not claimed to be a getter. An additional **288 bytes of caller/producer excerpts** were checked directly.

Raw bodies, extraction scripts and arithmetic replay stay in ignored `Research/raw/rea/codex-assignment-backend-011/`, with hashes in the JSON. No new analysis engine, target process, MIDI or preferences access was used.

## From the stored parameter to an operational code

In the family-A branch of `0x15de134`, stored `code & 0xffffc000 == 0x4000` leads to the previously audited plug-in resolver `0x15df8a8`. Its pointer result must be non-null. From its companion result **X1 = (enumerator_index << 32) | section**, the instructions at `0x15de1f0–0x15de214` build:

```text
parameter_index = stored_code - 0x4000
encoded = parameter_index
        | ((enumerator_index + 1) << 16)
        | ((section & 1) << 20)              [32-bit arithmetic]
```

The fields are nonoverlapping for indices 0–14, section 0/1 and stored codes 0x4000–0x7fff. This is a **bounded interpretation domain, not a proven Logic slot limit**. The enumerator's relation to visible slot order retains the live-test caveat from ASSIGN-IDENTITY-001/008.

For the historical EQ row, stored **0x4020** leaves parameter index **0x20**. If its resolved enumeration index is 0 and section is 0, the encoded value is **0x00010020**; index 2 produces **0x00030020**. A section-1 result adds bit 20. These are examples of the arithmetic, not observed runtime target locations.

A resolver miss returns **0x10c** at `0x15de584`. The class-5 consumer calls `0x15dcfa4`, rejects a nonpositive low-16 result, calls the parameter wrapper `0x15ddf84`, then explicitly compares **0x10c** at `0xab3440`. This supplies a concrete rejection branch for this path; it does not prove that no other assignment can respond to the same MIDI message.

## Forwarding and integer scaling

At the post-Pickup call site `0xab4554–0xab4588`, equal requested/current integers take the existing skip branch; otherwise a nonzero bits-16–19 field selects forwarding through `0x5972d8`. The wrapper acquires a context and checks its input token before forwarding to **`0x594890`**. At that call it splits the encoded parameter as:

| Backend argument | Bits of encoded value |
|---|---|
| W2 | Bit 20, the section bit in the bounded producer domain |
| W3 | Bits 16–19, the enumeration index plus 1 in that domain |
| W4 | Low 16 bits, the parameter index |

The downstream excerpt subtracts 1 from W3 and passes it to **opaque helper `0x2fec34`** after context/container checks. That helper's meaning and the ultimate plug-in write were not established here. `0x5972d8` is a forwarding candidate supported by these operands and the nearby `AssignSetTrackValue` diagnostic; it is not confused with the previously identified description helper `0x597f1c`.

The wrapper also reads a signed 64-bit operand **H at descriptor +0x10**, when the descriptor is non-null:

```text
descriptor null: new value and companion integer remain unchanged
H < 128:        S = 0x01000000
H >= 128:       S = floor(0x7f000000 / unsigned(H))
new value      *= S  modulo 2^64
companion W7   *= S  modulo 2^32
```

The companion W7 integer is stored in a stack argument before W7 is repurposed as a descriptor-null flag. This is integer scaling evidence. H's runtime value, physical parameter units and the final plug-in gain are **not inferred** from the constant or from the earlier CC calibration. Flags/context arguments also remain separate from value verification.

## Targeted checks and remaining limits

All **219 byte/text anchors** hold. A restricted instruction-text interpreter compared forwarding arithmetic with an independent reference on **13,440 cases**, with **zero mismatches**, visiting 27 instruction sites. It covers section 0/1, index 0–14, four parameter indices, descriptor null plus six nonnegative H values (including 127/128), new values 0/1/64/127, two companion integers and two flag modes.

The replay starts after context acquisition and stops **before the backend call**. It does not execute the producer, target matching, caches, the native backend or a plug-in. The encoding formula is a separate operand-level derivation. The complete intervening consumer CFG and special-case adjustments are not audited by these excerpts. Cache freshness and invalidation remain unproved as recorded in ASSIGN-ROUTE-003.

The remaining end-to-end gap is therefore precise: bind the current document/track/slot/instance, observe this path's requested effect through independent readback, and reject replacement or stale targets. A historical code, resolved integer, or reached forwarding call does not by itself satisfy `verified`.
