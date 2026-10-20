# ASSIGN-DRAIN-015: the sequence timer returns queued records to the handler

[Research guide](../README.md) · [JSON](assignment-drain-015.json) · [253 instruction/import/data anchors](../protocol/assignment-drain-12.4-anchors.tsv) · Previous: [ASSIGN-HANDLER-013](assignment-handler-013.en.md)

日本語要約：013で未確定だったタイマーのコールバックと、内部バッファを読む処理がつながった。タイマー処理は待機フラグを消し、バッファからレコードを取り出して元のハンドラーへ渡す。スレッド比較に使う番号は、この処理側で現在のスレッドから設定される。キューへの書き込みから後段への再投入までは静的に追えたが、実際のEQパラメーターへの書き込みと読み戻しは未確認である。

## Scope

Preserved Logic **12.4 / 6707**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. A bounded syntactic scan found candidate references to the two addresses already established in 013. Claims below come from selected LLVM instruction reads, not from treating those candidates as a complete reference inventory.

Saved excerpts total **3580 bytes across six ranges**. The largest complete function is the **1828-byte consumer at 0xbcae68**; the 5432-byte worker at 0x783684 is represented only by 768-byte and 512-byte excerpts. The curated evidence covers **984 instruction bytes**, import bindings and two short thread-name constants. Raw material stays in ignored `Research/raw/rea/codex-timer-xref-015/`.

No analysis engine or live Logic process was used. Current callback registration, queue execution and parameter changes were not observed at runtime.

## Registration identifies the callback

In the selected initialization block of **0x5c9bd8**, X19 becomes **timer record 0x266bd18**. The code stores function address **0x777b68** at **timer +0xa** at 0x5c9e10, then calls imported **`InsTime(timer)` at 0x5c9e24**. The neighboring record at 0x266bd48 has a separate callback and `InsXTime` registration; it is not substituted for the timer used in 013.

Apple's shipped **CarbonCore/Timer.h**, SDK **27.0**, defines the `TMTask` callback field. A compile-only arm64 check confirms `offsetof(TMTask, tmAddr) == 0xa` and `offsetof(TMTask, tmWakeUp) == 0x1a`. This supports the callback-slot interpretation and the wake-up-field offset used in 013. The check links or executes no program; header/source hashes and compiler arguments are in the JSON.

The complete 56-byte callback at **0x777b68** can set the name `SeqTimer 2` when its atomic byte guard was clear. It then **clears byte 0x2676cf4 at 0x777b98** and **tail-calls 0x783684 at 0x777b9c**. This is the flag the producer tested before calling `PrimeTime`.

## The compared thread port belongs to the worker path

On a selected non-null-context branch, the worker:

- Obtains the current port through **`mach_thread_self` at 0x7836dc**.
- Compares it with **global 0x266c0c8 at 0x7836ec**.
- Stores the current port there at **0x7836f4** if different.
- Passes the constant **`SeqTimer`** to **`pthread_setname_np` at 0x783730** on that path.

This identifies a worker-side writer of the global that 013 left unresolved. It does not identify the UI or main thread. The following static call path can re-enter the handler with the worker's matching port; concurrent updates and live execution remain unobserved.

## The reader and writer refer to the same storage

The selected worker branch compares cursors, then calls **`bcae68(base +0x40, context)` at 0x783f60**. Let `S = base +0x40`, its first argument. The secondary consumer in that function uses:

| Field | Relative to S | Relative to original base |
|---|---|---|
| Producer cursor | +0x8cad0 | +0x8cb10 |
| Consumer cursor | +0x91180 | +0x911c0 |
| First storage address | +0x8cad8 | +0x8cb18 |
| Exclusive storage bound | +0x90958 | +0x90998 |

The producer cursor and storage bounds therefore match **013's exact buffer**, after accounting for the +0x40 argument. At 0xbcb208, a saved non-null context is required; this is not an unconditional drain in every worker invocation.

At **0xbcb27c–0xbcb2a8**, the reader zeroes a 96-byte scratch region, normalizes an out-of-range read cursor, copies 16-byte units into scratch, follows the next unit's bit 63 and stores the resulting consumer cursor. The first extension is then checked for the B8 family. Its 32-bit word at **extension +8** selects a context collection entry when it has the accepted encoded-index form. Other conditions select a first-element fallback or null target. This is routing-token processing, not a plug-in UUID comparison.

Finally, **0xbcb378–0xbcb38c** call:

```text
781438(context, scratch_record, resolved_target,
       u64[scratch_record] & 0xffffffffffff0000, 5)
```

The copied record has returned to the **same handler that queued it** in 013. The fourth argument is stated as its observed bit mask; its time/unit semantics are not inferred here.

```mermaid
flowchart LR
    H[781438: thread-port mismatch] --> Q[Copy record to buffer]
    Q --> P[PrimeTime on 266bd18]
    P --> C[777b68: clear armed flag]
    C --> W[783684: SeqTimer worker]
    W --> R[bcae68: selected buffer read]
    R --> H2[781438: record re-entry]
    H2 --> U[Parameter application remains unresolved]
```

The diagram represents selected static branches. It is not a runtime trace or a promise that every scheduled record is consumed.

## Validation and remaining gap

**253/253 byte/text/import/data anchors** hold. JSON, source hashes, local links and the SDK layout assertions were checked. The offset conversion above is exact arithmetic; no consumer or concurrency behavior was executed. Product code, parser and CI were unchanged.

The buffer's end-lookahead sentinel, maximum permitted record length, overflow/drop handling, concurrent safety and response time remain unknown. The producer replay from 013 verifies its restricted write loop and does not verify those consumer properties. Reaching this re-entry still does not establish the final Audio Unit write, current same-instance identity or independent value readback.
