# ASSIGN-FILTER-014: a conditional target-token rejection gate

[Research guide](../README.md) · [JSON](assignment-filter-014.json) · [107 instruction anchors](../protocol/assignment-filter-12.4-anchors.tsv) · Previous: [ASSIGN-HANDLER-013](assignment-handler-013.en.md)

日本語要約：後段には、候補オブジェクトと内部レコードの対象番号が異なる場合に、その候補を除外するフィルターがある。ただし対象番号の比較には追加のフラグが必要で、通常のB8ヘッダーだけではこの比較を通らない。8196ケースの分岐モデルでこの条件を確認した。これを全レコード共通の保護や、現在のEQインスタンスのUUID確認と扱うことはできない。

## Scope and caller

Preserved Logic **12.4 / 6707**, SHA-256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`. This report saves a **768-byte prefix** of the 3408-byte interval at **0x77ff64**, then the complete selected **1064-byte** callee at **0x1a13954**. The prefix is not a complete audit of the larger function. Existing producer bytes from [011](assignment-backend-011.en.md) are reused. The curated witnesses cover **428 instruction bytes**. Raw scripts and excerpts stay in ignored `Research/raw/rea/codex-assignment-consumer-014/`.

The caller keeps context and record in X19/X20 and iterates candidates in its selected branch. After establishing non-null X26 at **0x78023c**, it calls:

```text
0x780250: 1a13954(candidate=X26, context=X19, record=X20, -1)
0x780254: if return bit0 is set, skip this candidate to0x78019c
```

The callee is therefore a candidate filter at this call site. The candidate's precise object class and its relationship to a current plug-in instance are not established here.

## The token comparison has an extra condition

On the primary-tag path from 012 with the first qword bit 63 clear, the callee reaches **0x1a139d4**, calling opaque helper **`19c22cc(record, 0xb8, 0, 1)`**. The helper's returned extension pointer is the starting assumption for the following analysis; its search and validation behavior is not expanded.

The post-call branch at **0x1a139d8–0x1a13a14** compares target tokens only when:

```text
extension != NULL
(u64[extension] & 0xbf08000000000000) == 0xb808000000000000
(u64[extension] & 0xff00000000000000) != 0xa000000000000000
```

In particular, the mask requires **header bit 51 to be set**. For a returned high byte 0xb8 with that bit clear, this gate bypasses the token comparison. Later filters still apply.

When the condition holds, **0x1a13a08/0x1a13a0c** load and compare:

| Operand | Source |
|---|---|
| Record token | 32-bit word at returned extension +0x8 |
| Candidate token | 32-bit word at candidate +0x30 |

A mismatch branches to **0x1a13cc4**, sets W8 to 1, masks it into W0 and returns. The caller's bit-0 test then excludes that candidate. Equality only continues to later class/record gates; it does not establish final acceptance or parameter application.

## The producer sets the marker conditionally

[012](assignment-record-012.en.md) established the B8 template, marker bytes and token stored at **record +0x18**, which is extension +0x8. That initial extension has bit 51 clear.

The existing producer has a separate conditional block at **0x594d4c–0x594d54**:

```text
u8[record +0x16] |= 0x08    // bit 51 of the qword at record +0x10
```

Earlier branches can bypass the block. Their context-dependent conditions are not assigned GUI or playback names here. Its existence explains how a marked extension can be produced, while preventing the unsupported claim that every B8 record carries the comparison marker.

This is a **32-bit token filter**, not the [UUID-based resolver in 008](assignment-identity-audit-008.en.md). It does not prove token uniqueness, freshness, current document/track ownership, or identity after plug-in replacement. Those properties still require separate evidence.

## Validation and next evidence

A restricted interpreter starts **after the opaque finder**, at 0x1a139d8, with a non-null candidate. It stops at the next class gate or the mismatch return path. **8196 model cases, zero mismatches**, visit 15 instruction sites and vary all 256 returned high bytes, bit 51, other header bits and equal/unequal 32-bit tokens, plus an absent extension. The arbitrary returned headers are synthetic inputs, not a claim that the finder can return every one. The comparison executes in 32 cases and rejects mismatches in 16.

**107/107 byte/text anchors** hold; JSON, source hashes and local links were checked. No native engine or live process was used. Product code, parser and CI were unchanged.

The remaining question is where an accepted record changes an actual parameter, including how the timer-buffer branch from 013 reaches its consumer. That work must retain the distinction between a routing token, a plug-in UUID and a current same-instance proof. No new assignment or value verification is established by this filter.
