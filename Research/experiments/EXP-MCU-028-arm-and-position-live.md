[日本語](EXP-MCU-028-arm-and-position-live.md) | [English](EXP-MCU-028-arm-and-position-live.en.md)

# EXP-MCU-028: `track arm` と `state` の `position` を実機で確かめる

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-07 01:03〜01:10（JST） |
| Logic バージョン | 12.3.1 (6682) |
| macOS バージョン | 27.0、arm64 |
| テストプロジェクト | LogicCLI-Test.logicx（ウインドウの題名「LogicCLI-Test - トラック」を画面で確認。それ以前に別の曲が開いていたときは、何もしなかった） |
| 初期状態 | 8 本（Piano, Synth, Ballad, Trk08, Audio, Amped Up, Bass, Trk10）。停止中。選択は Ballad（3）で、Ballad は自動の録音待機（`rec_armed: true`） |
| 1つの操作 | MCU の REC ボタンで Piano（1）を録音待機にして、戻す |
| 期待する変化 | Piano だけが録音待機になり、戻すと元に戻る |
| 再現回数 | 1 |
| 承認 | ユーザーがこのチャットで直接「全て許可」 |

> **訂正（2026-10-07、[EXP-MCU-029](EXP-MCU-029-two-units-on-one-port.md)）:** この実験のとき、Logic には同じポートに Mackie Control が **2 台**つながっていた（「Mackie Control #2」）。曲は **14 本**（出力と Master を含む）で、`state` の「8 本・complete」は **1 台目が表示する 8 本**だけだった（2 台目が残りを表示するので、バンクが動かず、走査が端と判断した）。下の「8 本」はそのように読むこと。録音待機の結果は、Piano が 1 台目の 1 番目だったので有効（`--expect-name Piano` が LCD の名前と一致し、画面でも R の点灯を確かめた）。ただし REC の LED の番号は 2 台で同じなので、証拠の通り道は 2 台目と共有されていた。

## 観察

- `logicctl track arm 1 on --expect-name Piano` → `ok: true`、`verified: true`、`observed.rec_armed: true`。画面の Piano の R は**赤く点滅**した（スクリーンショットは点滅の消えた瞬間を撮ることがあるので、3 回撮って確認した）。
- `logicctl track arm 1 off --expect-name Piano` → `verified: true`。続けて同じ `off` → 何も押さずに確認済み（「既に要求どおりの状態です。送信していません。」）。
- **予想しなかった副作用**：Piano を録音待機にした時点で、**選択中の Ballad の自動の録音待機が外れた**（`track get 3` で `rec_armed: false`）。Piano を戻しても、Ballad は戻らなかった。
- 戻し方：選択を Synth に移してから Ballad に戻すと、Ballad の自動の録音待機が付き直った。最後の `logicctl state` は、基準と全 8 本で一致した（音量・パン・ミュート・ソロ・録音待機・選択）。
- `state` の `position`：停止中に `{"display": "  1 2 3226", "mode": "beats", "bar": 1, "beat": 2, "division": 3, "tick": 226}`。画面の時刻表示「1 2」と一致した。実機での 2 つ目の値（1 つ目は EXP-MCU-024 のログの `  1 3 2 29`）。
- 今回の一覧には出力と Master が含まれず（原因は 2 台目。上の訂正）、「録音待機できないストリップでは確認に失敗する」場合は確かめられなかった。深夜のため、音の出る再生は行わなかった（再生中の `position` は未確認）。
- 保存はしていない。生の記録：`Research/raw/live-arm/`（Git の追跡対象外）。

## 仮説（Hypothesis）

仮説（Hypothesis）: **MCU で別のトラックを録音待機にすると、Logic は選択中のトラックの自動の録音待機を外す。**
確信度: 中（1 回。ソフトウェア音源どうし）。
根拠: 上の観察。
反例: オーディオトラックでは外れない、外れるのが MCU の経路だけではない、など。
次の検証実験: 画面の R ボタンで Piano を録音待機にした場合と比べる。

製品への含意：`track arm` は、指定したトラックの録音待機だけを変えるとは限らない。`verified: true` は、指定したトラックの REC の LED を確かめたという意味で、**他のトラックの録音待機が変わっていないことは確かめていない**。仕様書に書いた。
