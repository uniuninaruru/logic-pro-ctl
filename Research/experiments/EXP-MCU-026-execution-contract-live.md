[日本語](EXP-MCU-026-execution-contract-live.md) | [English](EXP-MCU-026-execution-contract-live.en.md)

# EXP-MCU-026: 実行契約を実機で確かめる — 期限切れ・同じキーの再送・世代の不一致

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-05（daemon のログは UTC 2026-10-04 15:47） |
| Logic バージョン | 12.3.1 (6682) |
| macOS バージョン | 27.0 (26A5416b) |
| Logic Remote バージョン | 該当なし |
| テストプロジェクト | LogicCLI-Test.logicx |
| 初期状態 | `logicd` を新しいビルドで再起動して接続済み（世代 4）。トラック 2 の音量は 0 dB、ミュートなし |
| 1つの操作 | 下の A・B・C は、それぞれ**別の条件を 1 つだけ**変えた独立の確認 |
| 再現回数 | 各 1 回 |

## 確認と観察

[docs/execution-contract.md](../../docs/execution-contract.md) の挙動のうち、これまで試験（偽の相手）だけで確かめていたものを、実機で確かめた。

### A. 期限が短すぎる書き込み

`track volume 2 -6 --idempotency-key exp026-vol --deadline-ms 30`

| 観察 | 値 |
|---|---|
| 応答 | `ok: false`、`error: timeout`、`execution.state: unknown`、メッセージ「実行された可能性があります。結果は不明です」 |
| daemon のログ | `exec=unknown error=timeout ms=35`（期限 30 ms の直後に応答） |

### B. 同じキーでの再送

A の直後（約 0.8 秒後）と、さらに 4 秒後に、同じ要求を同じキーで送った。

| 観察 | 値 |
|---|---|
| 1 回目の再送 | `ok: true`、`verified: true`、`execution.state: replayed`、`observed: {fader_value: 9874, volume_db: -6}`。ログは `exec=replayed ms=0` |
| 2 回目の再送 | 同じ内容、`replayed`、`ms=1` |
| ログの行数 | このキーで `completed` の行は無い。実行の行は A の 1 行（`unknown`）だけ |

- A の書き込みは、応答が返った後も裏で続き、**確認済みで終わって記録が `completed` になった**とみられる（1 回目の再送が `verified: true` の結果を返したため）。
- 再送の `ms` が 0〜1 なので、Logic への送信は行われていない。**ただし MIDI の記録は取っていない**ため、「送信が 1 回だけ」は応答時間とログの行数からの推定。
- 1 回目の再送が届いた時点では、裏の書き込みはすでに終わっていた。実行中の同じキーは D で確かめた。

### C. 世代が違うときの書き込み

`track mute 2 on --expect-session 99999 --idempotency-key exp026-pre`（現在の世代は 4）

| 観察 | 値 |
|---|---|
| 応答 | `ok: false`、`error: precondition_failed`、`execution.state: rejected`、「期待した世代 99999、現在 4」 |
| ログ | `exec=rejected error=precondition_failed ms=0` |
| 結果 | トラック 2 のミュートは `false` のまま（`track get 2` で確認） |

### D. 実行中の同じキー（素のソケットで確認）

トラック 9 の音量（バンクを動かす必要があり、3 秒前後かかる）を書き、実行中に同じキーを送った。`logicctl` は安全装置つきの要求の前に `status` を送るが、
その `status` も実行枠を待つ（実行中の書き込みが終わるまで進まない）。そのため CLI では「実行中」を観測できず、素の Unix ソケットで 2 本の接続から直接送った。

| 条件 | 同じキーの 2 本目の応答 |
|---|---|
| 1 本目が**期限切れ**（`--deadline-ms 20`）で、裏で実行中 | 即座に `outcome_unknown`、`execution.state: unknown`（「自動では再実行しません」） |
| 1 本目が**既定の期限で待っている間**（0.3 秒後に送る） | 即座に `request_in_flight`、`execution.state: rejected`（1 本目は 3.19 秒後に `completed`、`verified: true`） |
| 1 本目が終わった後 | `replayed`、`verified: true` |

- 実行中の重複は**待たされずに拒否**され、再実行も行われなかった（1 本目の結果は `completed` の 1 件だけ）。
- 期限切れの後の裏の実行中は「不明」として扱われ、自動では再実行されない。終わると `replayed` に変わる。

### 後始末

`track volume 2 0`（新しいキー）、D のあとはトラック 9・10 の音量も 0 dB に戻した。いずれも `verified: true`。全体の状態は実験前と同じ。

## 仮説（Hypothesis）

仮説（Hypothesis）: 実行契約（期限切れ → 結果不明、同じキーの再送は再実行しない、世代の不一致は送信前に拒否）は、実機でも試験と同じに働く。
確信度: 中〜高（各 1 回。A→B は応答と記録の組み合わせで確認）。
根拠: 上の表と、`logicd` のログ。単体試験（`WriteExecutorTests`）とも一致。
反例: なし。
未検証: キューが満杯のとき（`queue_full`）、`logicd` の再起動をまたいだ照合、`--expect-session` が一致するが接続の中で状態が変わった場合（契約が保証しない範囲）。
次の検証実験: 送信が 1 回だけだったことを、`logicd --trace` の MIDI で確認する。実行中の同じキーを起こすには、遅い書き込みの最中に再送する（タイミングの制御が必要）。

## logicctl への帰結

- 変更はない。[support-matrix.tsv](../../Research/protocol/support-matrix.tsv) の `--expect-session` を `tested` から `live` に更新した（不一致の拒否を実機で確認）。
