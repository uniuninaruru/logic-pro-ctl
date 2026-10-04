[日本語](EXP-MCU-025-same-name-tracks.md) | [English](EXP-MCU-025-same-name-tracks.en.md)

# EXP-MCU-025: 同じ名前のトラックが 2 本あるとき、`name_unique` と `--expect-name` はどう働くか

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-05 |
| Logic バージョン | 12.3.1 (6682) |
| macOS バージョン | 27.0 (26A5416b) |
| Logic Remote バージョン | 該当なし |
| テストプロジェクト | LogicCLI-Test.logicx（12 ストリップ）。保存はしていない |
| ツール | `logicctl track list`、`track mute --expect-name`、Logic のトラックヘッダーでの名前変更 |
| 初期状態 | 全トラックの名前はすべて異なる（`name_unique` はすべて `true`）。ミュート・ソロなし |
| 1つの操作 | トラック 7 の名前を `Trk07` から `Trk06`（トラック 6 と同じ）に変更して確定する。それ以外は変えない |
| 期待する変化 | 6 と 7 の表示名が同じになり、両方の `identity.name_unique` が `false` になる |
| 再現回数 | 1 回（変更 → 確認 → 元に戻す） |

## 観察

| 段階 | 観察 |
|---|---|
| 変更前 | `track list`（完全）：12 ストリップすべて `name_unique: true` |
| 変更後の LCD（バンクを動かさず） | `Trk05  Trk06  Trk06  Trk08  Trk09  Trk10  St Out Master ` |
| 変更後の `track list` | 完全。トラック 6・7 とも `name: "Trk06"`、**両方とも `name_unique: false`**。ほかは `true` |
| `track mute 7 on --expect-name Trk07` | `target_mismatch`（トラック 7 は今 `Trk06` と表示）。何も送らない |
| `track mute 7 on --expect-name Trk06` | **成功**、`verified: true`。ミュートされたのはトラック 7 だけ（一覧で確認） |
| ミュートを解除し、名前を `Trk07` に戻す | `track list`：12 ストリップすべて `name_unique: true`、ミュートなし |

- 名前を入力しただけでは Logic の名前は変わらなかった。名前欄をダブルクリックして編集状態にしてから入力し、空き領域のクリックで確定すると変わった（操作ツールの動作）。

## 仮説（Hypothesis）

仮説（Hypothesis）: 表示名が同じ 2 本のトラックは、`--expect-name` では区別できない。`name_unique: false` は、その事実を事前に知らせる。
確信度: 高（実機で、一覧の判定と照合の挙動の両方を確認）。
根拠: 上の表。単体試験（`theListMarksDisplayedNamesThatAreNotUnique`、`aNameCheckCannotTellTwoTracksWithTheSameDisplayedNameApart`）とも一致。
反例: なし。
未検証: 同名の 2 本を入れ替えたとき（並べ替えを起こせていないため）。3 本以上の同名。

## logicctl への帰結

- 同名のトラックがあるとき、`--expect-name` は「その位置の名前が期待どおり」までしか保証しない。どちらの `Trk06` かは区別できない。
- `--expect-session` は Logic との**接続の世代**を確認するだけで、同じ接続の中で同名のトラックが入れ替わっても検出できない。同名トラックの個体の同一性は、現在の契約では保証できない。
- エージェントは、`identity.name_unique` が `false` のトラックには、位置を決めた直後に書き込むか、名前以外の確認（人による確認など）を別に用意する必要がある。名前と位置の照合だけに頼らない。
- 変更はない。契約文書の「守れないこと」を、実機で確認済みと書き換えた。
