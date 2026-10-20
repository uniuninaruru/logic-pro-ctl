# ASSIGN-ROUTE-003: class5 forwarding, parameter cache and no-match projection

日本語概要: MIDI割り当てのclass5の情報取得は、既知のトラック解決と別のパラメータ解決を経て共通関数へ進む。固定先検索の高速経路も `CUUIDBase` 比較へ接続できた。検索失敗を表す内部値は今回の条件では維持されるが、短いトラック番号取得では0に縮退する。番号だけを対象特定の成功判定に使えないことが、静的な根拠として増えた。実機の効果・スロット識別・キャッシュの鮮度保証は未検証。

[Machine-readable record](assignment-route-003.json) · [Prior descriptions and comparison](assignment-parameter-002.en.md) · [Track storage and consumer](assignment-target-001.en.md) · [Byte anchors](../protocol/assignment-route-12.4-anchors.tsv)

## Scope

Preserved **Logic 12.4 / 6707 ARM64**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. Four concrete caller/callee intervals total **3200 bytes**: `0x15e0428`1456B, `0x7663cc`104B, `0x15a16a8`1208B and `0x15ddf84`432B. Exact image bytes, LLVM disassembly and LC_FUNCTION_STARTS bounds match. Lower callees remain uninspected unless explicitly identified as prior evidence. This is offline analysis, with no engine import or target execution.

Raw capture/reproducer files live under ignored `Research/raw/rea/codex-assignment-backend-003/`. REA/Ghidra remains Claude's sole heavy-engine lane.

## The class5 information route has another layer

Prior `parameterPath` and `parameterKind` call **`0x15e0428`** with different flags and output buffers. Its class5 branch at **`0x15e05f4`**:

1. Keeps Assign, flags and output pointer.
2. Calls **`0x15dcfa4(Assign)`** for the packed track result.
3. Calls **`0x15ddf84(Assign,0)`** for a32-bit result.
4. Tail-branches at **`0x15e063c`** to **`0x597f1c(flags,out,packedTrack,result32,Assign)`**.

Thus this class5 branch is a forwarder; no backend virtual call is exposed in that branch itself. `0x597f1c` is5284 bytes by LC_FUNCTION_STARTS and remains the next bounded REA query. Other classes in the1456-byte helper have different behavior; this note does not assign their full semantics or make a global purity claim.

## A separate parameter cache precedes the worker

**`0x15ddf84..0x15de134`** reads helper `0x18f34ac` bit0. One route compares acquired global32 **`0x25f39c0`** with Assign **`+0x214`**. Equality returns32-bit Assign **`+0x20c`** and, if the caller supplied a non-null output pointer, copies **`+0x210`** there. A mismatch computes, stores these fields and updates the tag. This is separate from the track resolver's `0x25f39c4` / `+0x208` cache.

When context is unavailable, a fallback reads32 bits at **Assign `+0x40`**. With context, the function resolves the packed track and may obtain an entry pointer from `context+0x788 → +0x1e0/+0x1e8` if masks, context markers and bounds permit. It otherwise passes a null entry. **`0x15de134(Assign,context,entryOrNull,optionalOut)`** performs the lower work and is not inspected here.

The class5 information route passes a null optional-out pointer. Its32-bit result is therefore not universally just raw `+0x40`; current context, another worker and a separate cache can intervene. Tag equality is not a proved freshness or invalidation guarantee. `+0x210` and the result's external namespace remain unnamed; no plug-in slot/instance meaning is assigned.

## The fast pin comparison is no longer opaque

The prior lookup block **`0x7663cc..0x766434`** receives its context in block `+0x20`, and the payload pointer in block `+0x28`. It checks non-null context, one of two context markers, encoded-index mask `0x80000003`, bounds and a non-null entry. Failed checks return0. A valid candidate is passed in X0 and the payload in X1 to a tail branch at **`0x766430`** to **`0x1afb3e0`**.

The prior exact stub/fixup evidence binds that destination to MACore **`operator==(CUUIDBase const&, CUUIDBase const&)`**. This closes the fast-path equality edge; byte encoding, persistence, target lifetime and plug-in identity remain unknown. The whole lookup and downstream use are not automatically a verified target contract.

## The no-match encoding survives, but a scalar getter loses its marker

The exhausted lookup in ASSIGN-PARAMETER-002 calls **`0x15a16a8`** with **X3=`0xffffffff00000000`**, **W4=0**. This normalizer selects a mode from W0/W1. On these inputs, its mode0/1 guards bypass the lower helper paths, modes2/3 preserve the input, and other modes construct the same encoding. No lower call is reached on this particular no-match input.

A restricted offline replay of the byte-verified LLVM rows covered **1280 cases**: all256 values of the W1 low byte, crossed with five signed-boundary W0 representatives. All returned **`0xffffffff00000000`**, over three unique paths. W0 is used here only for its signed-positive predicate, and the selected W1 is masked to eight bits. The replay starts after the save prologue and ignores callee-save restores and the SP epilogue, which do not affect result X0. It is an instruction-text model, **not native execution or a complete formal proof**. Match inputs with W4 nonzero are outside this replay.

The prior worker preserves the packed high/low halves. When a freshly calculated no-match encoding reaches **`WrappedAssign.resultingTrackNumber`**, its **`SXTH x0,w0`** exposes only low16, giving **0**. The no-match high32 marker is lost. Cache behavior is a separate gate: this does not claim every invocation freshly evaluates the lookup.

Consequently a scalar track number of0 alone cannot establish successful target resolution. Pin-mode flags, composed names, and cache equality are also insufficient. No public enum meaning for0 or a universal index base is inferred.

## Next bounded work

Claude was asked to query **`0x597f1c`** through the retained REA session after its Pickup boundary; no second cold import. Its parameter-worker input can be traced through **`0x15de134`** if needed. Preserve same-document/track/slot/instance/parameter binding and value readback gates. This record supplies no new product write operation or `verified: true` capability.
