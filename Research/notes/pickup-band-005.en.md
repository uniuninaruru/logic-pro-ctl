# PICKUP-BAND-005: integer tolerance, crossing test and reset excerpts

日本語概要: Pickup判定の許容幅は、記述情報の差分をfloat32経由でdoubleへ変換し、0.02を掛けた後に整数へ切り捨てている。差分127なら幅は2。前回値と今回値の間を横切る操作も通り、両端のどちらかが現在値に近いことだけを要求する判定ではない。保存データの読み込みにも状態リセットがあり、2つのSTRBマスクだけでは全リセット経路を列挙できない。

[Machine-readable record](pickup-band-005.json) · [Instruction anchors](../protocol/pickup-band-12.4-anchors.tsv) · [Pickup setting](pickup-global-004.en.md) · [Claude's consumer note](pickup-consumer-001.en.md)

## Scope

Preserved **Logic 12.4 / 6707 ARM64**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. Codex independently captured **11 excerpts / 448 bytes** from Claude's saved consumer/reset evidence and the original image. LLVM instruction bytes and containing LC_FUNCTION_STARTS intervals match. These are bounded excerpts, not full CFG, alias or trigger proofs. Raw reproducers/proof are under `Research/raw/rea/codex-pickup-band-005/`.

No target or native engine was executed. The numeric replay is a restricted instruction-text model, not a live MIDI experiment or complete formal proof.

## Concrete operands and integer tolerance

At `0xab4238`, P is the sign-extended previous32-bit value from consumer pointer X20 `+0x62`. N is the64-bit value at SP `+0x20`; one producer path stores helper `0x15e1020`'s return at `0xab4200`. Other producer paths are not completely audited here. V is the64-bit operand at SP `+0x18`. Calling V the target's current value is supported by Claude's broader flow and earlier live samples, but its complete producer and parameter units are not audited here.

The tolerance block `0xab4414..0xab443c` loads L/H from descriptor SP `+0xb8/+0xc0`, computes H−L, converts to **float32**, then double, multiplies by binary64 constant **`0x3f947ae147ae147b`** (0.02), and uses **FCVTZS** to truncate toward zero into integer T:

```
T = truncTowardZero(float64(float32(H - L)) * binary64(0.02))
```

Examples under the modeled default rounding environment: delta49→0, 50→1, 99→1, 100→2, 127→2, 255→5, 480→9. Therefore “about2.5 units” is not the final integer tolerance for delta127. This does not establish that any particular live assignment's descriptor delta is127. Range provenance, actual units and exceptional/overflow conversions remain unproved.

Descriptor storage is populated by `0x15e0428` with flags0x2003 and can be updated by `0x597f1c` with flags0x22007 on another path. Those calls are recorded; this note does not call the operands universally a raw MIDI range or physical plug-in range.

## Crossing is accepted

The signed comparisons at `0xab4440..0xab447c` accept exactly:

```
min(P, N) - T <= V <= max(P, N) + T
```

for nonoverflowing arithmetic in the replayed domain. The interval includes a crossing even when both endpoints are far from V. For P100,N30,V64,T2, the branch passes; neither endpoint is within2 of64. P100,N80,V64,T2 fails. P100,N100,V98,T2 passes, while V97 fails.

The byte-bound replay compared those branches with the independent interval formula over **7290 cases**, covering nine representative values crossed with ten descriptor deltas; zero mismatches and four distinct paths. It models small nonnegative exact float32 inputs and signed nonoverflowing arithmetic, with no native execution. Passing this branch alone does not establish the requested Logic effect.

## Repeat and first-value gates precede application

When W22==2, the branch at `0xab423c..0xab424c` compares N with P. Equality exits through the skip path before the later Pickup predicate. This gate precedes the global Pickup helper, so disabling the global setting does not automatically remove this particular repeat check. The complete meaning of W22 and earlier helper side effects remain outside these excerpts.

On the changed-value path, N's low32 is stored at `X20+0x62`. The Pickup route additionally requires `(byte[X20+0x4b]&7)==2`, bit3 of `+0x39` clear, the numeric `+0x40` filter and the compound setting predicate documented in PICKUP-GLOBAL-004.

If bit4 is clear, `0xab4360..0xab436c` sets it and takes the skip exit. Accepted crossing reaches `0xab4548..0xab4550`, which sets bit3. “Previous value valid” and “picked up” are behavioral interpretations of these bits, not independent runtime traces.

## Reset excerpts do not form an exhaustive inventory

The timed path at `0xab4228..0xab4234` clears bit3 with mask0xf7 and zeroes a deadline slot. Two other excerpts at `0xab6010..0xab6018` and `0xaba938..0xaba940` clear bits3/4 with mask0xe7 after matching object `+0x2c` to a caller selector's low16. The field's meaning, exact triggering operation and alias relationship to the active consumer object are not established by these snippets alone.

A third mechanism occurs in the serialized-record loader: `0xabe810..0xabe81c` applies mask0xe0 to the temporary object's `+0x39` and zeroes `+0x62` before construction. It clears more bits than the0xe7 pattern. This directly shows why finding two0xe7 stores does not enumerate every state reset. Wide stores, copies, alias bases and other masks can also matter; no absence of a track-selection reset is claimed.

## Next checks

Live predictions need a freshly confirmed test project, available tool access and same-target readback. The existing human authorization covers those experiments; earlier UI availability observations must be refreshed. Target/plug-in identity and actual parameter application remain separate from this gate model.
