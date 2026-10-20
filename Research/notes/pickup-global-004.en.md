# PICKUP-GLOBAL-004: settings action, disable bit and applicability predicate

日本語概要: ClaudeがREAで見つけたPickup判定と設定画面の処理を、保存済みLogic 12.4の命令・Objective-Cメタデータ・import fixupで照合した。設定側が書く実体は `0x26c0b9b` のbit5で、1が無効側。初期化ガードは別の `0x26c15a0` である。判定関数には割り当て側の条件もあり、単純な設定値の読み取り関数ではない。今回の実機設定変更は行っていない。

[Machine-readable record](pickup-global-004.json) · [Byte anchors](../protocol/pickup-global-12.4-anchors.tsv) · [Assignment route checkpoint](assignment-route-003.en.md)

## Scope and independent sources

Preserved **Logic 12.4 / 6707 ARM64**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. Claude's retained REA Ghidra12.1.4 session returned the two function dossiers; Codex independently checked the **200-byte reader** and **164-byte action** against image bytes, LLVM and LC_FUNCTION_STARTS. ObjC class/method metadata and chained import fixups were decoded from the same copy. There was no second engine import or target execution.

- Reader **`0x15e0f58..0x15e1020`**: REA `ev_a2a9418ade0861e9293803f78bcdf8432fd9a50ccc5c2c1bb48a25c18c50328b`.
- Action **`0xaa3670..0xaa3714`**: REA `ev_aa8c61d3eb2ece066182a0772880228906d03bf1f8001d08413de5f9c29b5f73`.

Raw independent proof and reproducer: `Research/raw/rea/codex-pickup-global-004/{pickup-global-proof.json,inspect_global.py}`. Claude's immutable dossiers are local `Research/raw/rea/af-0x{15e0f58,aa3670}.json`; machine-readable source hashes bind both inputs.

## The setting action is bound by metadata

`PrefsCSView` has a38-entry instance method list at **`0x1c575d8`**. Entry **`0x1c57688`** binds selector **`change_csPickupMode:`**, type encoding **`v24@0:8@16`**, to implementation **`0xaa3670`**. Relative method offsets and classlist/data/name/method-list chained-pointer membership were checked.

The action moves its sender from X2 to X0, then calls stub **`0x1bbc2a0`**. Exact20-byte stub decoding binds the selector to **`state`** and dispatch to **`_objc_msgSend`**. This proves the requested message, not dynamic receiver class or live UI behavior.

After the initialization gate it updates **byte `0x26c0b9b`**:

```
newByte = (oldByte & 0xdf) | ((senderState == 0) << 5)
```

Thus a zero state sets bit5 and any nonzero state clears it, preserving the other bits. The corresponding reader rejects when bit5 is set. The state-storage polarity is therefore **disable when set**, distinct from a per-assignment picked-up bit.

## Shared initialization is not the preference flag

Both functions read bit0 at **`0x26c15a0`** and use exact import stubs **`0x1afb4b8` / `0x1afb4c4`**, bound to `___cxa_guard_acquire` / `___cxa_guard_release`. Their cold initialization clears four bytes: **`0x26bf3b9`**, **`0x26c0b97`**, **`0x26c0b9b`**, **`0x26c159f`**. The fifth shared address is the guard, not another preference value.

This does not audit persistence, preference loading, current settings or their lifecycle. It also does not make invoking either function a pure read: the cold path initializes shared state.

## The reader is a compound predicate

Let **P** be the reader's X0 argument. After the initialization gate:

| Condition | Result |
|---|---|
| global byte `0x26c0b9b` bit5 set | 0 |
| global bit5 clear and `(u8[P+0x46] & 0x7f)==0` | 1 |
| otherwise, `u8[P+0x4b]` bit5 set | 0 |
| otherwise, pointer pair at `P+0xe0/P+0xe8` differs | 0 |
| otherwise | 1 iff the pair at `P+0x128/P+0x130` is equal |

Pair equality is byte-supported; the represented container/assignment semantics are not established here. Offsets are relative to P and are not automatically merged with other layouts.

Claude's saved consumer disassembly has `mov x20,x0` at `0xab31cc` and `mov x0,x20; bl 0x15e0f58` at `0xab42f4/0xab42f8`. The immediately preceding filter reads **32 bits at X20 `+0x40`**, clears bit0, and compares with **`0x82`**. Thus it excludes the numeric values0x82/0x83; calling this load an assignment-class field is unsupported. Existing WrappedAssign byte evidence instead places its class word at `+0x3a` and its raw track-parameter getter at `+0x40`. Full caller/base identity remains a separate gate; this note does not rename the consumer operand as a class or plug-in slot.

## What this connects, and what remains

These bodies establish a current settings-action → shared disable bit → predicate connection. They support Claude's static Pickup model and are compatible with the earlier ON/OFF experiment; they do not independently replay that GUI experiment or establish the entire value-apply path.

Claude is tracing the per-assignment `+0x39` reset/match flags and tolerance branches. A scan of STRB stores is a bounded candidate list, not proof of every writer or absence of selection-change effects; wide stores, copies and different aliases remain possible. No global-setting or per-assignment bit is read or written live by this work.

REA has also now queried the prior descriptive frontier `0x597f1c`; Claude reports text-oriented callees and infers a formatter at medium confidence. Codex has not independently audited that full body. Parameter identity should next use worker **`0x15de134`** or the actual value-apply callees from `0xab3184`, with a complete document/track/slot/instance/parameter binding and same-target readback before any new verified operation.
