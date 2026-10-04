[日本語](EXP-MCU-027-live-smoke.md) | [English](EXP-MCU-027-live-smoke.en.md)

# EXP-MCU-027: 実機の抜き取り試験（`live_smoke.py`）の初回実行

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-05 |
| Logic バージョン | 12.3.1 (6682) |
| macOS バージョン | 27.0 (26A5416b) |
| Logic Remote バージョン | 該当なし |
| テストプロジェクト | LogicCLI-Test.logicx（12 ストリップ） |
| ツール | [`Tests/integration/live_smoke.py`](../../Tests/integration/live_smoke.py)、`logicctl`（`0a7037d` 時点のビルド） |
| 初期状態 | トラック名は `Piano`〜`Master` の 12 個、ミュート・ソロなし、音量 0 dB、パン中央 |
| 1つの操作 | スクリプトを 1 回実行する（コマンド列は固定。内容は下の表） |
| 再現回数 | 1 回 |

## 目的

これまでの実機確認（EXP-CLI-001、EXP-MCU-021〜026）は、その場で手で行ったものだった。同じ確認を**繰り返し実行できる形**にして、
後の変更（ビルド、macOS、Logic の版）で回帰がないかを、同じ手順で調べられるようにする。

## 安全の仕組み

- `--test-project` が必須。さらに**トラック名が期待どおり**（`Piano`、`Audio`、`Bass`、`Synth`、`Trk05`〜`Trk10`、`St Out`、`Master`）でなければ、
  **何も書かずに終了コード 2 で止まる**。間違った期待値で実行して確認した（書き込みコマンドは 0 件）。
- 書き込みはすべて `--expect-name` つき。最後に必ず（失敗しても）元へ戻し、初期状態との差を調べる。
- 記録（コマンドと JSON）は `Research/raw/live-smoke/`（Git の追跡対象外）に残る。

## 結果

26 件の確認がすべて合格（約 55 秒）。最後に、名前・ミュート・ソロ・録音待機・選択・音量・パンが、初期状態と一致した。

| 分類 | 確認 |
|---|---|
| 読み取り（7） | `status` に `compatibility` がある／`track list` が完全で 12 本／`identity.scope` が `mixer_position`／名前が一意／名前が合う `track get` は成功／合わないと `target_mismatch` でデータなし／トラック 13 は `no_such_track` |
| 書き込み（10） | `mute 3`、`solo 2` の ON → 同じキーの再送が `replayed` → OFF／`volume 4` を -6 dB と 0 dB／`pan 5` を -0.25 と 0。すべて `verified` |
| 契約（5） | 同じキーで内容違いは `idempotency_key_conflict`／古い `--expect-session` は `precondition_failed` で、何も送らない／期限 20 ms は `timeout`・`unknown`／その後の同じキーは `replayed` |
| 実行枠（3） | 長い書き込みの最中に `status` が 1 秒以内に答える／実行中の同じキーは `request_in_flight`／最初の書き込みは完了して `verified` |
| 復元（1） | 初期状態と一致 |

## このスクリプトが確かめないこと

- GUI の操作が要るもの：名前変更、追加、削除、並べ替え（EXP-MCU-022〜025）。名前行の変化を見る `bankIsKnown` の修正の回帰も、ここでは検出できない。
- 録音待機の復元（CLI から設定できない。差があれば報告するだけ）。
- Logic の再起動・再接続、古い `logicd`（偽の daemon による統合試験で確認する）。
- 別の macOS・Logic の版。環境が未検証のときは `profile_verified` が `true` でない旨を表示する。

## 仮説（Hypothesis）

仮説（Hypothesis）: 検証済みの環境では、このスクリプトが全件合格する。環境や版が変わると、失敗する項目で影響範囲が分かる。
確信度: 中（1 回の実行）。
反例: なし。
次の検証実験: ビルドや環境を変えるたびに実行する。`Tests/integration/live_smoke.py` が失敗したら、`Research/raw/live-smoke/` の記録で該当のコマンドを読む。
