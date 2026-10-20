# ASSIGN-TARGET-001: current assignment track modes and the pinned payload

日本語概要: 保存済みLogic 12.4で、MIDI割り当てのトラック番号と種別を読み分ける構造、および対象トラックを決める内部経路を命令で確認した。選択トラック方式は`0x1000`、固定方式はclass5と`0xb000`の組み合わせ。固定対象の16-byte payloadを保存する場所と解決側の読み取りも接続できた。ただし固定フラグだけでは対象解決の成功を保証せず、一部では先頭エントリへのfallbackがある。UUID・永続性・プラグイン実体の識別、MIDI操作後の値検証は未確認。

[Machine-readable proof](assignment-target-001.json) · [MIDI route map](../static-analysis/SA-MIDI-ROUTE-001.en.md) · [REA handoff](rea-ghidra-handoff-001.en.md) · [EQ readback limit](channel-eq-ax-context-002.en.md)

## Scope and witnesses

This is new **offline byte evidence** from preserved Logic **12.4 / 6707**, ARM64 SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. The 124-entry `WrappedAssign` method list, selector fixups and LC_FUNCTION_STARTS bind the named entry points. Six short getter intervals total **152 bytes**; eight relevant consumer/setter/accessor intervals total **2020 bytes**, plus eight table bytes. LLVM disassembly matches every interval byte. LC_FUNCTION_STARTS bounds are not a full CFG or lower-callee audit.

Raw reproducers and complete instruction captures remain ignored under `Research/raw/rea/codex-assignment-target-001/{fields,consumer}/`. This work reuses the existing Mach-O helpers and prior REA artifact identity; it is not a REA native/Ghidra dossier or runtime observation. No engine, target process, GUI, MIDI, preferences or product code was changed by these probes.

## Fields are not universal external IDs

All six selected getters call the previously verified `assign` selector stub `0x1b14bc0`.

| Getter / 12.4 entry | Byte-supported observation |
|---|---|
| `trackObj` `0x6993b8` | `LDRSH w0` reads returned Assign `+0x3e`; despite its name this is not an object-pointer read. The instruction sign-extends to W0, not a promised signed64 external ID |
| `trackNo` `0x6993f4` | Unsigned16 `+0x3e`, masked with `0xfff` |
| `trackType` `0x699b48` | Unsigned16 `+0x3e`, logical shift right12: high four bits |
| `audioTrackParam` `0x699470`, `trackParam` `0x6994b0` | Both read32 bits at `+0x40`; ObjC return type encoding is `i` |
| `parameterName` `0x699a04` | Returned Assign in X0, W1=0, tail branch to `0x15e88ec`; lower formatter not inspected |

The existing `befehl` getter reads the same `+0x3e` area for commands. Interpretation therefore needs assignment class/context. A low12 field is not thereby a public track ID, index base, plug-in slot or persistent identifier. No plugin/slot/instance/focus substring occurred among these exact124 instance selectors; that bounded search does not prove absent storage or behavior.

## A concrete current track-resolution path

`WrappedAssign.resultingTrackNumber` at **`0x6994f0`** calls `assign`, then **`0x15dcfa4`**, and returns only **signed16** via `SXTH x0,w0`. The internal helper returns a packed64 result; the method discards its higher metadata. Do not treat these representations as interchangeable.

The wrapper at `0x15dcfa4` reads a current-context pointer through global `0x276c240`. One path compares acquired global32 at **`0x25f39c4`** with Assign **`+0x208`**, returning cached64 at **`+0x200/+0x204`** on equality. Otherwise it calls **`0x15dd08c`** and stores the result/tag. A separate bit0 test from `0x18f34ac` bypasses these cache checks. The global is a **cache tag**, with generation, increment policy, scope and lifetime unknown.

Worker `0x15dd08c` requires non-null context and assignment class **5**, rejects/special-cases packed values `0x8001` / `0x7fff`, then splits `+0x3e` into high4 mode / low12 operand. Mode1 calls `0x15dd5b8`; mode11 reads the pinned byte range at Assign **`+0x1a0/+0x1a8`**, returning the empty case or passing its begin pointer to **`0x15a1b60`**. Other modes use `0x765f00` or `0x15a1f04` with different operands; those callees and enum meanings are not established here.

## Selected and pinned modes: storage, not a success token

| Named method | Confirmed path |
|---|---|
| `setTrackTypeSelectedTrack` `0x69b978` | Sends `0x1000` to helper `0x15e6d44` |
| `setTrackTypePinnedToTrack` `0x69ba44` | Sends signed `−0x5000`, whose low16 bits are `0xb000`, to the same helper |
| `isPinnedToTrack` `0x69ba08` | True only when class5 and `(uint16(+0x3e)&0xf000)==0xb000`; no payload/target check |

Helper **`0x15e6d44`** saves the old packed value, resolves the old target, writes the new16 bits at `+0x3e`, and zeroes the tag at `+0x208`. Zero does **not** prove cache invalidation if the global can also equal zero.

For pinning it may select a context entry by packed old-result bits. An incompatible result, out-of-range index or null indexed entry can instead select the **first** entry from `context+0x788 → +0x1e0/+0x1e8`. Missing context or no usable fallback restores the old packed value. These are current12.4 setter branches, separate from the historical AE resolver's similar fallback.

With an entry selected it asks **`0x15dc49c(Assign,13,16)`** for storage, then copies exactly **16 bytes** from that entry's prefix when the returned pointer is non-null. The caller does not restore the mode on a null return at this point; reachability of that case for the audited allocation path remains unknown. Therefore the flag predicate alone cannot establish successful pin storage or resolution.

## The storage-to-consumer edge is proved

Accessor **`0x15dc49c`** computes `Assign + 24*fieldIndex`, with begin/end/capacity fields at `+0x68/+0x70/+0x78`. For field13:

```
begin    = 13*24 + 0x68 = 0x1a0
end      = 13*24 + 0x70 = 0x1a8
capacity = 13*24 + 0x78 = 0x1b0
```

These are exactly the range fields consumed by worker mode11. The size-rule table entry at **`0x1d44378`** is16. For ordinary nonzero field13 requests the comparison selects **max(16, requested)**, a minimum nonzero size, not a maximum. Request16 gives16; request0 bypasses that rule and can shrink end to begin while retaining capacity.

Resizing can allocate, copy, free and update the range. For class5/B000, changed lengths can also mutate context bytes `+0xe4/+0x96` and call `0x1bf3f0`; unchanged lengths can bypass those side effects. **This accessor is not a pure getter.** Lower allocation/notification contracts remain unaudited.

The connected16-byte payload is a **pinned-target key candidate**. Its exact format, UUID interpretation, persistence, uniqueness and replacement behavior are unknown. It does not identify a plug-in instance or parameter by itself.

## Historical reuse and next gates

Existing12.3.1 XML evidence selects a backend by parent/child type and ordinal, linked-entry match, then `entry+0x120`. XML Plugin `id` at child `+0xbc` is formatted separately and does not drive that lookup. Old R2 `0x01a15c7c` can also fall back to the first entry. These are historical comparison evidence, not the current generic Assign-to-backend edge.

Next bounded work is the current parameter side: `parameterKind` **`0x699dac`** (308B), `parameterPath` **`0x699b64`** (584B), and pinned lookup **`0x15a1b60`**. Claude was asked to obtain compact dossiers through its one retained REA session after analysis/Pickup work reaches a boundary; Codex will independently audit the bytes. No second cold import is needed for this request.

Acceptance still requires explicit class/mode, payload and resolved identity, rejection of fallback/mismatch, current document/session binding, plug-in-slot/instance/parameter namespaces and same-target readback. Cache equality, a pin flag, names and ordinal success are insufficient. No new product write operation or `verified: true` capability is supplied by this note.
