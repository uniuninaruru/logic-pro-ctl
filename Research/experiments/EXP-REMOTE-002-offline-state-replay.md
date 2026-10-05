[日本語](EXP-REMOTE-002-offline-state-replay.md) | [English](EXP-REMOTE-002-offline-state-replay.en.md)

# EXP-REMOTE-002: 保存した受信（EXP-REMOTE-001）から、Logic のミキサー状態をオフラインで組み立て直す

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-05（オフライン。Logic への接続・送信はしていない） |
| Logic バージョン | 12.3.1 (6682)（記録したときの Logic） |
| macOS バージョン | 27.0、arm64 |
| Logic Remote バージョン | 該当なし |
| テストプロジェクト | LogicCLI-Test.logicx（記録したときのプロジェクト。今回は触っていない） |
| 初期状態 | [EXP-REMOTE-001](EXP-REMOTE-001-receive-initial-state.md) の受信記録（`Research/raw/remote-recv/20261005-094234-e1/`、Git の追跡対象外） |
| 1つの操作 | 記録のフレームを到着順に、研究用の状態構築器 `Tools/research-scripts/remote_state.py` へ流す |
| 期待する変化 | 12 ストリップの状態が組み上がり、矛盾（ID の不一致・壊れた `/ati` など）は 0 件 |
| 再現回数 | 記録 1 本に対して何度でも同じ結果（決定的）。**記録そのものは 1 回の受信だけ** |

## 状態構築器の契約

製品（`Sources/`）には入れない研究用の道具である。[読み取りの契約](../../docs/observation-contract.md)と同じ考え方で、**分からないものを分かったことにしない**。

| # | 決まり | 理由 |
|---|---|---|
| 1 | **受け取っていない値は `null`**。0 や `false` は、Logic が送ったときだけ現れる。値には、どのフレームで受け取ったかを付ける | 差分は変わった項目だけを運ぶ。欠落を 0／off と読むと、ミュートや音量を誤る |
| 2 | **4 つの識別子を混ぜない**：`gindex`（ストリップの鍵。`/gtFaderData` の `g` のキー）、位置（最新の `/ati` での順番。並べ替えで変わる）、`track_id`（`BgTrackInfoTrackIDKey`。`/gtFaderData` の `t` のキー）、UUID。ストリップの値は `gindex` に付く。**位置で値を引き継がない** | EXP-REMOTE-001 で、`gindex` は作成順、位置と `track_id` は現在の順だった |
| 3 | `/ati` は**全体の写し**として扱う。壊れたもの（スキーマ違反、長さの違う列、`gindex`・`track_id`・UUID の重複）は**受け付けず、前の状態を保つ**。同じ内容の再送は「重複」で、変化ではない | 部分的に壊れた表で、ストリップの対応を壊さない |
| 4 | 同じ `gindex` で UUID が変わったら**別のストリップ**とみなし、値を `null` に戻す。`/ati` から消えたストリップの値は捨て、戻ってきても `null` から始める | 同じものだと確かめられないものを、同じ扱いにしない |
| 5 | `/gtFaderData` は**部分的な差分**。届いた項目だけを更新し、無い項目は前の値（または `null`）のまま。今の `/ati` に無い `gindex`／`track_id` の値は**孤児**として保持して報告し、後の `/ati` に現れたら結び付ける | 届く順番が前後しても値を失わない。ただし黙って付けない |
| 6 | `/sti` は、最新の `/ati` の添字でストリップに結び付け、名前と `tn` を照合する。**新しい `/ati` が届くたびに照合し直す**。合わなければ結び付けず（`gindex` は `null`）、報告する。`NoTrackSelected` は「選択なし」であり「不明」ではない | 実データで `/sti` が最初の `/ati` より**前**に届いた。並べ替えの後の古い `/sti` は、違うストリップを指しうる |
| 7 | Logic は初回送信の終わりの合図を送らない（[SA-REMOTE-STATE-001](../static-analysis/SA-REMOTE-STATE-001.md) §3）。**`complete` は `true` にしない（`null`）**。代わりに、分かっている項目の数（coverage）を出す。coverage がすべて埋まっても、完全という意味ではない | 後から差分が来るかどうかは、受け手には分からない |
| 8 | 1 つの辞書の中では `/ati` を先に適用する（他のアドレスがそれを参照する）。辞書の中のキーの順序は、Logic が決めていない | 同じ内容に対して結果を一つにする |

## 観察（記録の再生）

- 矛盾は **0 件**。出来事の内訳：`/ati` の適用 1・重複 1、ストリップの追加 12、`/gtFaderData` の適用 1、`/sti` の適用 1・重複 1、件数の適用 2・重複 2。
- 組み上がった状態：12 ストリップ。フェーダーの項目（`vL`・`s`・`m`）は 36 個すべて、トラック側の項目（`r`・`ip`）は 24 個すべてが分かった。件数（`/allTrackCount`・`/trackCount` = 12）は `/ati` と一致。`complete` は `null`。
- **`/sti` が最初の `/ati` より前に届いていた**（フレーム 456 と 479）。`/ati` が届いた時点で照合し直し、選択は位置 3（`gindex` 116、Trk08）に結び付いた。名前と `tn` は一致。
- **途中の状態**：フレーム 470 の時点では、ストリップは 0 本で、フェーダーの値は 1 つも分かっていない（`null`）。この時点で値を 0 と読むクライアントは、全ストリップを「ミュートなし・音量最小」と誤る。
- 識別子：位置 1〜12 に対して `gindex` は 88, 100, 116, 92, 96, 124, 112, 108, 104, 120, 80, 84（作成順で、位置の順ではない）。`track_id` は位置の順（`0x40001`〜`0x4000b`、Master は `0x8000f`）。UUID は 12 個とも別。
- 記録には**差分が無い**（受信中に Logic を操作していない）。`/gtFaderData` は 1 回だけ、`/ati` の 2 回目は 1 回目と同じ内容だった。差分・並べ替え・孤児の扱いは、合成の試験だけで確かめた。

### スキーマと記録の対応

[`logic-remote-state-coverage.tsv`](../protocol/logic-remote-state-coverage.tsv) に、スキーマが定める 14 のアドレス（`/ati` は列ごと、`/gtFaderData` と `/sti` は項目ごと）について、届いた数・値の要約・スキーマの検査結果・変化を観測したか、を載せた。文字列（トラック名・UUID・ロケールなど）は**個数だけ**を書き、値は載せていない。

- 14 アドレスすべてが届き、すべてスキーマに合格した。
- **2 回以上届いたものも、内容はすべて同じだった**（`changed_seen` はすべて `no`）。値の安定性・変化の仕方は何も分かっていない。
- 観測した値の範囲は狭い：`/ati` の `t` は 1, 2, 5, 6、`nc` は 1, 2, 6、`p` は −1, 0。`/gtFaderData` の `vL` は 1 種類（0 dB）、`s`・`m`・`ip` は 0 だけ、`r` は 0 と 64。

[`logic-remote-captured-addresses.tsv`](../protocol/logic-remote-captured-addresses.tsv) には、届いたすべてのアドレスを、数字を `{n}` にまとめた 116 の型で載せた（値は載せていない）。スキーマが扱うのはそのうち 14 の型だけで、`/cs/…`（コントロールサーフェスの 8 本分）・`/mixer/io/…`・`/mixer/plugins/…`・メーターなどは、スキーマにまだ無い。

### `/cs/…`（コントロールサーフェスの返信）と静的な割り当て表

[`logic-remote-cs-feedback.tsv`](../protocol/logic-remote-cs-feedback.tsv) で、受信した `/cs/…` を、Logic Remote のプラグインが持つ既定の割り当て表（[`cs-assign-remote.tsv`](../protocol/cs-assign-remote.tsv)、SA-002）と突き合わせた。末尾の数字（ストリップの番号）を外した型でまとめている。

- 受信した 33 の型は、**すべて割り当て表にあった**。表に無いアドレスは届いていない。
- 表にあって届かなかったのは 5 つ：`/cs/mixer/mutereset`、`/cs/mixer/soloreset`、`/cs/mixer/volume`、`/cs/transport/track+`、`/cs/transport/track-`。名前と表の値（`kind` 9 で `flags` 3、`kind` 1）から、**Remote から Logic へ送るボタン側で、Logic からは返さないもの**と考えられる（仮説。確信度: 中）。
- 値：`volume`・`trimvolume`・`mastervolume` は 0 dB で **90/127**、`pan` は中央で **64/127**。割り当て表の `param` は、音量が 7、パンが 10（MIDI のコントロールチェンジの音量・パンの番号と同じ）。`/gtFaderData` の `vL` の上位バイト 90 とも一致する。したがって、`/cs` の音量は **Logic の 7 ビットの音量（90 = 0 dB）を 127 で割った値**と考えられる（仮説。確信度: 中。0 dB の 1 点だけ）。
- **MCU の値とは尺度が違う**：MCU の 14 ビットのフェーダーは、0 dB が約 12440（[`mcu-fader-calibration.tsv`](../protocol/mcu-fader-calibration.tsv) の −0.4 dB = 12283 と +0.2 dB = 12523 の間。0.759）で、7 ビットに縮めると 97 になる。90 とは合わないので、2 つの経路の値をビットの切り詰めで相互に変換してはいけない。
- `/cs` が扱うのは **8 本**（`/cs/bankLeftOffset` = 0 から 8 本）だけで、12 本すべてを扱う `/ati`・`/gtFaderData` とは範囲が違う。送り（sends）は、2 桁の番号の 64 アドレス（8 × 8）。どちらの桁がストリップで、どちらが送りの番号かは未確認。

## 試験

`Tools/research-scripts/test_remote_state.py`（35 件）。合成のメッセージ列で、契約の各項を確かめる。

- 0 と欠落：送られていない `m` は `null` のまま（0 にならない）。届いた 0 は 0。部分的な差分は他の項目を消さない。
- 壊れた `/ati`：列の長さの違い、列の欠落、`gindex`・`track_id`・UUID の重複は受け付けず、前の状態を保つ。
- 重複：同じ `/ati`・`/sti` の再送、同じ値の `/gtFaderData` は変化として数えない。
- 識別子：並べ替えで値が `gindex` に付いていく。UUID が変われば別のストリップ。消えて戻ったストリップは `null` から。
- 不一致：知らない `gindex`／`track_id` は孤児として報告し、後の `/ati` で結び付く。スキーマ違反の `/gtFaderData` は何も変えない。
- 選択：`/ati` より前の `/sti` は後で結び付く。並べ替えの後の古い `/sti` は結び付けず、報告する。
- 完全性：すべての項目が分かっても `complete` は `null`。
- `/cs` の照合：番号付きのアドレスが表の型にまとまること、表にあって届かないもの・表に無いのに届いたものを区別すること。
- 実データ（手元に記録があるときだけ）：矛盾 0、36／24 項目、2 回目の `/ati` は重複、`/ati` 直後の時点ではフェーダーの値が全部 `null`。

試験が誤りを検出できることは、選択の再照合を外した版で、実データの試験が失敗したことで確かめた（その失敗から、`/sti` が先に届くことに気づいた）。

## 仮説（Hypothesis）

仮説（Hypothesis）: **`/sti` の `BgTrackInfoIndexKey` は、`/ati` での 0 始まりの位置である。**
確信度: 中（1 回の受信の 1 個の値。添字 2 が位置 3 の Trk08 と、名前・`tn` とも一致）。
根拠: 本実験の再生。
反例: 別の選択（Stereo Out・Master、複数選択）で、添字と `/ati` の位置がずれる。
次の検証実験: 受信中の選択の変更（E3 の候補。別途承認が要る）。

## 未確認のこと

| 項目 | 状態 |
|---|---|
| 差分（音量・ミュート・選択の変更）が、この契約どおりに積み上がるか | 合成の試験だけ。実データの差分は 0 件 |
| `gindex` が、同じセッションの中で並べ替えをまたいで変わらないか | 未確認（EXP-REMOTE-001 の仮説 2） |
| 曲を切り替えたときの `/ati` の入れ替わり（`gindex` の振り直し） | 未確認。契約 4 で、UUID が違えば別のものとして扱う |
| 値の安定性（同じ状態で、同じ値が送られ続けるか） | 未確認。記録は 1 本だけ |
| `m`・`s`・`r`・`ip` の値の意味 | 未解決（生の値のまま扱い、解釈しない） |

## 再現

```sh
python3 Tools/research-scripts/remote_state.py replay Research/raw/remote-recv/<日時>-e1 [--at <フレーム番号>]
python3 Tools/research-scripts/remote_state.py coverage Research/raw/remote-recv/<日時>-e1 > Research/protocol/logic-remote-state-coverage.tsv
python3 Tools/research-scripts/remote_state.py addresses Research/raw/remote-recv/<日時>-e1 > Research/protocol/logic-remote-captured-addresses.tsv
(cd Tools/research-scripts && python3 -m unittest test_remote_state)
```
