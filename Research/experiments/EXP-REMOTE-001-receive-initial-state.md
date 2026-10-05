[日本語](EXP-REMOTE-001-receive-initial-state.md) | [English](EXP-REMOTE-001-receive-initial-state.en.md)

# EXP-REMOTE-001: 研究用ピアを自分の名前で 1 回接続し、Logic の初回送信を受信だけする

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-05 09:39〜09:44（JST）。E0 = 09:39:20、E1/E2 = 09:42:34〜09:43:52 |
| Logic バージョン | 12.3.1 (6682)（Logic Pro Creator Studio） |
| macOS バージョン | 27.0 (26A5416b)、arm64 |
| Logic Remote バージョン | 該当なし（本物の Logic Remote は使っていない。研究用ピア `Tools/remote-research-peer` を使用） |
| テストプロジェクト | LogicCLI-Test.logicx（開いていたのはこの 1 曲だけ） |
| 初期状態 | 12 ストリップ（並び：Piano, Synth, Trk08, Audio, Bass, Trk10, Trk07, Trk06, Trk05, Trk09, St Out, Master。ユーザーが手で並べ替えた後）。全ストリップ 0 dB・パン中央・ミュートなし、停止中、Trk08 を選択 |
| 1つの操作 | 研究用ピア `logicctl-research-peer` が招待 → Logic の確認ダイアログで「接続」を押す → `/protocolVersion = 10` と `/jsonSupport` だけを送り、60 秒受信する |
| 期待する変化 | Logic 側の状態は変わらない。ピアの登録だけが残る（[承認用の計画書](../plans/PLAN-05-approval-brief.md) §2） |
| 再現回数 | 1（E0 は 1 回、E1/E2 も 1 回）。**単一の観測**であり、値の安定性は未確認 |
| 承認 | ユーザーが PLAN-05 を承認（2026-10-05）。「接続」は、ユーザーの許可を受けて Claude が押した |

## 観察

### E0（広告を探すだけ）

- `apple-lgremote` の広告を 0.12 秒で発見。ピア名はホストのローカライズ名、`discoveryInfo` は `/hostType = "0"`、`/protocolVersion = "10"`（SA-REMOTE-SESSION-001 §2 と一致）。
- 招待・送信はしていない。

### E1/E2（接続と受信）

- 招待から 16.2 秒後に `connecting`、16.3 秒後に `connected`（その間に人がダイアログを読んで押した）。ダイアログの文言は「"logicctl-research-peer" が Logic Pro への接続を望んでいます。」、ボタンは「接続しない」「接続」。
- 送信したのは `/protocolVersion = 10` と `/jsonSupport = 1` の 2 通だけ（`events.jsonl` の `sent` が 2 行）。その後は何も送っていない。
- 受信：60 秒で **5,947 フレーム、6,141 メッセージ、707 種類のアドレス**。
- **製品の `RemoteFrameParser` で 5,947 フレームすべてを復号できた（失敗 0）。** Python で独立に書いた復号器（`Tools/research-scripts/remote_capture.py`）でも全件を復号できた。
- **状態のメッセージは、すべてスキーマ（[`logic-remote-state.schema.json`](../protocol/logic-remote-state.schema.json)）に合格した（違反 0）。**
- 形式：JSON（形式 4）5,923、plist（形式 1）19、MAZP 付き plist 3、MAZP 付きキー付きアーカイブ（形式 2）2。圧縮していないフレームのペイロードは、すべて 1,024 バイト以下。
- 接続の前後で Logic の状態（再生・選択・12 ストリップの音量・パン・ミュート・ソロ）は変わらなかった（`logicctl state` の比較）。
- 生データ：`Research/raw/remote-recv/20261005-093920-e0/`、`Research/raw/remote-recv/20261005-094234-e1/`（Git の追跡対象外。27 MB）。

### 予測との照合（計画書 §4 と SA-REMOTE-TRACKTYPE-001 §7）

| # | 予測 | 結果 | 判定 |
|---|---|---|---|
| P1 | 最初に `/protocolVersion = 10` と `/jsonSupport` が届く | 1 通目 `/protocolVersion = 10`、2 通目 `/jsonSupport`（引数は **0**） | 合格 |
| P2 | バージョンを待ってから初回送信 | こちらの 2 通は接続と同時（0 ms）に送ったため、待ちの有無は判別できない | 判別不能 |
| P3 | 初回送信の順序は SA-REMOTE-STATE-001 §3 の表のとおり | 表の行 2〜16 と 5a〜5f が**この順に**届いた。表に無いものも届いた（下記） | 合格（追加あり） |
| P4 | `/ati` は 13 本の同じ長さの配列 | 13 本・各 12 要素。スキーマ合格 | 合格 |
| P5 | `/ati` と `/allTrackCount`・`/trackCount` が 2 回ずつ届く | 2 回ずつ。`/ati` の 2 通は完全に同じ内容 | 合格 |
| P6 | `/sti` の引数は MAZP 圧縮のキー付きアーカイブ | plist フレームの中の `NSData` が MAZP。展開すると辞書 | 合格 |
| P7 | `/gtFaderData` の `g` のキー = `/ati` の `gindex` | 12 個とも一致 | 合格 |
| P8 | テンポの単位と `/multiTempo` の向き | `/logicClock/currentTempo = 1200000`（120 BPM → **BPM × 10000**）。テンポが 1 つの曲で `/multiTempo = true`（コードの読み「1 = 全部同じ」と一致） | 1 点で確認 |
| P9 | `vL` と dB の関係 | 0 dB の全ストリップで `vL = 0x5A000000`。上位バイト 90 は `/cs/mixer/volume/volumeN = 0.70866`（= 90/127）と一致 | 1 点で確認（0 dB のみ） |
| P10 | `s`・`m`・`vL` は 0 でも含まれる | すべて含まれる | 合格 |
| P11 | 初回送信に終了の合図は無い | 決まった終わりの形は無い。最後は `/newTrackSheetOpen`・`/undoLabel` などの後、メーターだけが続く | 合格 |
| P12a | Master の `t` は 5 | **Master は 6、Stereo Out が 5** | **不合格** |
| P12b | Piano・Bass・Synth の `t` は 9 | **2** | **不合格** |
| P12c | Audio と Trk05〜Trk10 の `t` は 1 | 1 | 合格 |
| P12d | St Out の `t` は 6 か 10 | **5** | **不合格** |
| P12e | ソフトウェア音源だけを選んだとき `/sti` の `t` は 0 | 今回の選択はオーディオ（Trk08）で、`/sti` の `t` = 1。条件が違うため未検証 | 未検証 |
| P13a | `c` は 4 バイトで、4 バイト目はほぼ 0xFF | 48 個すべて 4 バイトで、4 バイト目は 0xFF。並びは見た目の色と一致（オーディオ = 青 `36 6e aa`、音源 = 緑 `1a a3 30`） | 合格 |
| P13b | 色番号 0 のトラックの `tnc`・`tsc` = `8cc0ffff` | 色番号 0 のトラックが無かった（下記） | 未検証 |

### 予測していなかったもの

1. **接続直後に `/cs/…` が 447 通届く**（`/cs/mixer/…` の 8 ストリップ分、`/cs/transport/…`、`/cs/bankLeftOffset`）。SA-REMOTE-SESSION-001 §3.4 の「フィードバックの更新」（接続ブロックの手順 2）に当たる。Logic Remote は、8 本単位のコントロールサーフェスとしても扱われている。値は 0〜1 の小数（例：0 dB = 0.70866 = 90/127、パン中央 = 0.50394 = 64/127）。
2. 初回送信の前に `/libData`、`/docOpen`（2 回）、`/duplicateTrack`・`/undo`・`/redo`、`/sti` と選択関連の一式が届く。初回送信の中（行 14）でも `/docOpen` がもう 2 回届く（計 4 回、すべて `true`）。
3. **メーターが停止中でも流れ続ける**：`/mixerLevels`・`/bankNavigator/trackLevels`・`/mixer/gainReductionData` が各 30 通/秒（合計 90 フレーム/秒）。
4. **`gindex` は位置ではなく、作成順に並んでいる**：St Out 80、Master 84、Piano 88、Audio 92、Bass 96、Synth 100、Trk05 104 … Trk10 124。ユーザーが手で並べ替えた後でも、元の作成順（Piano, Audio, Bass, Synth, Trk05〜Trk10）を保っていた。`BgTrackInfoTrackIDKey`（`0x4000N`）と `tn`（1〜11）は現在の位置に従う。UUID は 12 個とも別。
5. `/ati` の名前は Logic の名前そのままで、**末尾の空白を含む**（`"Piano "`、`"Synth "`、`"Audio "`、`"Bass "`、`"Trk10 "`）。MCU の LCD では見えない違い。出力の名前は `/ati` では `Stereo Out`、MCU の LCD では `St Out`。
6. `nc`（列）：オーディオ 1、ソフトウェア音源 2、Stereo Out 2、Master 6。`p`：Master だけ −1、他は 0。Master は `tn = -1`、`BgTrackInfoHasArrangeKey = false`。Stereo Out は `BgTrackInfoArrangeHiddenKey = true`。
7. **各トラックの色番号**：`c.nc` は、`/colorIndexMap` の `cellBackgroundColor` と 1 単位以内で一致した。オーディオ = 16、ソフトウェア音源 = 9、Stereo Out = 24、Master = 20。`defaultColorIndexForTrackTypes` = `{0: 9, 1: 16, 2: 9, 3: 76, 4: 9}`（静的解析 SA-REMOTE-TRACKTYPE-001 §4 と完全に一致）。差は 12 本とも各成分 1 以下で、常に `nc` の方が小さいか等しい。`/ati` が切り捨て（`fcvtzs`）を使うことと矛盾しない。
8. `sc` は 4 色とも最小の成分が `0x99`（= 0.6）。彩度 0.40・明度 1.00（`FUN_00d35578(番号, 40, 100)`）の読みと一致。
9. ペイロードの選び方：`/jsonSupport` の交換の前に届いた 5 通は plist、その後は JSON。`NSData` を含むものは plist、数値キーの辞書（`/gtFaderData`、`/colorIndexMap`）はキー付きアーカイブ（SA-REMOTE-FRAME-001 §2・§4 の仮説どおり）。
10. 受信を始めてからの 60 秒、Logic は接続を切らなかった。こちらからは何も送らなくても切断されない。

### 副作用（確認）

- **Logic に端末として登録された。** `com.apple.mobilelogic` の `ControlSurfaceDevicesDict` に `logicctl-research-peer` が追加され、コントロールサーフェスの設定ファイル `~/Library/Preferences/com.apple.logic.pro.cs` も 09:42 に書き換わった（`Control Surface: logicctl-research-peer` の項目）。
- Logic の「コントロールサーフェス設定」ウインドウに、Mackie Control とは**別の行**の装置（iPad の絵、名前 `logicctl-researc…`）として表示される。画面から選んで削除できる見込み（未実施。設定の変更にあたるため、ユーザーの判断を待つ）。
- MCU 経路（`logicctl status`・`track list`）は、登録後も正常だった。
- macOS の「ローカルネットワーク」の確認は、私（Claude）が見ていた範囲では表示されなかった（Logic の画面だけを見ていた）。広告の発見と接続はどちらも成功した。

## 仮説（Hypothesis）

仮説（Hypothesis）1: **種別語と `t` の対応は、0x40 = オーディオ（1）、0x43 = ソフトウェア音源（2）、0x44 = 出力（Stereo Out、5）、0x46 = Master（6）。**
確信度: 高（オーディオ・音源・出力・Master の 4 種類で、各 1 プロジェクト分）。
根拠: 本実験の `/ati`。静的な規則（SA-REMOTE-TRACKTYPE-001 §2）はそのまま正しく、**値ごとの意味の推測が外れていた**。Logic が種別語 0x44 に「Master Track」という名前を使うのは、トラック領域の「マスタートラック」が Stereo Out を表すため、と考えると矛盾しない。
反例: 別のプロジェクト（サラウンド出力、複数の出力）で、出力が 5 以外になる。
次の検証実験: E3 以降（別途承認）で、バス・フォルダー・トラックスタック・外部 MIDI を加えたプロジェクトを受信する。

仮説（Hypothesis）2: **`gindex` は位置ではなく、作成順に振られる識別子で、並べ替えの後も変わらない。**
確信度: 中〜高（並べ替えの後の 1 回の受信で、作成順のまま残っていた）。
根拠: 観察 4。並べ替えの前に受信した記録は無いので、「同じセッションの中で並べ替えをまたいで同じ値」を直接は見ていない。
反例: 同じセッションで並べ替えた前後で `gindex` が変わる。プロジェクトを開き直すと振り直される。
次の検証実験: 受信中に 1 回並べ替えて、前後の `/ati` を比べる（E3 の候補。並べ替えは人の操作）。製品の対象確認（PLAN-08）に使えるかは、その結果で判断する。

仮説（Hypothesis）3: **`vL` の上位 1 バイトは、7 ビットのフェーダー位置（0〜127）。0 dB は 90。**
確信度: 中（0 dB の 1 点だけ）。
根拠: `vL = 0x5A000000` と `/cs` の音量 90/127。
反例: 0 dB 以外の値で、上位バイトと `/cs` の音量がずれる。
次の検証実験: 受信中に MCU 経路で 1 本の音量を変え、`/gtFaderData` の差分と `/cs` を並べる（E3 の候補）。

## 再現

```sh
Tools/remote-research-peer/build.sh
Tools/remote-research-peer/run.sh e0 --seconds 15
Tools/remote-research-peer/run.sh e1 --seconds 60 --target "<E0 で見つかった名前>"   # Logic のダイアログで「接続」を押す
python3 Tools/research-scripts/remote_capture.py report Research/raw/remote-recv/<日時>-e1
```
