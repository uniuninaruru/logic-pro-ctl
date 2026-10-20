# ASSIGN-HANDLER-013: thread-dependent buffering before record consumption

[Research guide](../README.md) · [JSON](assignment-handler-013.json) · [136 instruction/import anchors](../protocol/assignment-handler-12.4-anchors.tsv) · Previous: [ASSIGN-RECORD-012](assignment-record-012.en.md)

日本語要約：内部レコードの受け渡し先では、スレッドの比較結果によって処理が分かれる。別のスレッドから来た対象レコードは、16バイト単位のバッファへコピーされ、タイマー処理を予約する経路がある。書き込み規則は72ケースのモデル照合で一致した。ただし、バッファを読む処理、現在のプラグインへの適用、適用後の値は未確認である。送信や予約の完了を値の検証と扱わない根拠が具体化した。

## Scope

Preserved Logic **12.4 / 6707**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. Direct image reads and LLVM establish the complete **1560-byte** `LC_FUNCTION_STARTS` interval **0x781438–0x781a50**. Selected semantic witnesses cover **524 instruction bytes**, including five import stubs, plus five chained import slots. Raw material and the restricted replay stay in ignored `Research/raw/rea/codex-assignment-handler-013/`; hashes are recorded in the JSON.

This report follows the primary 0x40/0x50 record family constructed in 012. It interprets the buffering branch and its scheduling boundary. Other format handlers and context flags remain unnamed. No engine, live Logic process, MIDI or preferences was accessed.

## The branch compares thread ports

The handler preserves context, record and caller arguments, then:

1. Calls imported **`mach_thread_self` at 0x781478**, retaining the returned port in X24.
2. Loads a 32-bit saved port from **global 0x266c0c8** into W25.
3. Calls **`mach_port_deallocate` at 0x781498** for the obtained thread-port reference.
4. Compares **W24 with W25 at 0x78149c**. A mismatch branches to **0x781564**.

The global's initializer and intended thread role are unknown. These instructions do not establish that it represents the UI or main thread. Import names are supported both by the stub instructions and independently decoded chained bindings.

On the equal-port branch, **0x7814ec/0x7814f4** call `GetFeatureAvailabilityCache` and `CFeatureAvailability::FeatureAvailable` with **raw feature ID 4**. Bit 0 of the result is tested at 0x7814f8. The feature's meaning is unknown; it is not labeled as a GUI event mask.

## A mismatched-thread B8 record enters a circular storage region

For the prior primary tags **0x41–0x4f / 0x51–0x5f** and an extension qword with high byte **0xb8**, the checks at 0x781564–0x7815a8 select the writer at **0x7815ac**.

The writer loads a pointer from global **0x276c240**, dereferences that pointer once to obtain a base, and uses these offsets:

| Field | Observed use |
|---|---|
| Base +0x8cb10 | Current write cursor |
| Base +0x8cb18 | First storage address |
| Base +0x90998 | Exclusive upper storage bound |

The region spans **16000 bytes**, or **1000 locations of 16 bytes each**. This is not a count of complete events: records can occupy multiple units. Initialization, consumer coordination and live overflow behavior are outside this report.

The selected instructions implement this producer rule:

```text
For each source unit:
    if cursor < low or cursor >= high: cursor = low
    copy 16 bytes from source to cursor
    cursor += 16
    continue if bit 63 of the next source qword is set
Store the final cursor at base +0x8cb10
```

The final cursor can equal the exclusive upper bound. Wrapping occurs before the next store, not necessarily before saving that cursor. No alignment guard is established in this excerpt; the replay uses aligned cursors.

## Scheduling is a distinct completion boundary

After storing the cursor, **0x781604** tests bit 0 of byte **global 0x2676cf4**. If already set, execution branches to the return epilog at **0x781750**.

Otherwise, the code **stores byte value 1** at that global, zeros the qword at **timer record 0x266bd18 +0x1a**, restores the frame, and **tail-calls imported `PrimeTime(timer_record, 0)` at 0x781650**. It does not preserve other bits of the flag byte through an OR operation.

The timer callback and buffer drain have not been identified here. Scheduling this work is therefore not evidence that a plug-in value has changed, nor does the zero timer argument establish a measured response time. Other branches call **0x77ff64** at **0x781694** and **0x781998**; its 3408-byte interval is a bounded next question, not an interpreted consumer in this report.

## Validation and limits

A restricted interpreter of the **20 instruction sites at 0x7815ac–0x7815f8** was compared with an independent modulo-index byte-buffer model. **72 cases, zero mismatches** cover six aligned cursor positions, six source lengths from 2 through 1001 units, and two payload variants. Comparison checks the entire 16000-byte destination and final cursor. The model can overwrite earlier locations for long inputs; this does not establish live drop handling, concurrency safety or throughput.

**136/136 byte/text/import anchors** hold. JSON, source hashes and local links were checked. Research parser, product code and CI remain at the existing affected-test checkpoint.

The next useful evidence is the actual drain or downstream type-0x40/0x50 handler, followed by current instance identity and independent value readback. The producer replay executes no native consumer, timer, transport or plug-in. Assignment confirmation and value verification remain false.
