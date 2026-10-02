# SA-005: Logic から Logic Remote へ状態を送る仕組み（読み取り方向）

[日本語](SA-005-logic-remote-state-push.md) | [English](SA-005-logic-remote-state-push.en.md)

| 項目 | 内容 |
|---|---|
| 日付 | 2026-10-01 |
| Logic | 12.3.1（6682）、arm64 |
| バイナリ | `Logic.framework`（`LgLogicRemoteController`）、`MACore.framework`（`MAPeerRouter`、`Bg*` 定数）、`Logic Remote.bundle` |
| 方法 | 静的解析のみ。Ghidra 12.1.4 で解析済みプログラムを逆コンパイル（`Tools/ghidra/query.sh`）、`Tools/research-scripts/macore_wire_keys.py` で定数を文字列に解決。Logic へ何も送っていない |
| 抽出したテーブル | `Research/protocol/logic-remote-wire-keys.tsv`（83 定数） |

対象は、**Logic から Remote クライアントへ状態を運ぶメッセージ**。
MCU に依存しない読み取り経路の候補として調べた。
動的な確認はまだなく、以下はすべて「コード上の処理」であり、
「実際の通信で観測した動作」ではない。

## 1. 通信上の定数（MACore の公開シンボルから文字列に解決）

メッセージは `{address-or-key: argument}` の辞書（SA-002 §3）。
Logic 側で使う名前を、MACore が公開する `Bg*` CFString 定数から解決した。

| 定数 | 通信上の値 | 役割（Logic.framework 内の使用箇所より） |
|---|---|---|
| `BgGInstAndTrackFaderDataKey` | `/gtFaderData` | フェーダー / mute / solo / rec の状態をまとめて送る |
| `BgGInstFaderDataGInstDataSubKey` / `…TrackDataSubKey` | `g` / `t` | インストゥルメント / トラックをキーにした下位の辞書 |
| `BgGInstFaderDataVolumeLevelLongKey` | `vL` | 音量（32-bit。符号付き byte を上位へシフト。§3 参照） |
| `BgGInstFaderDataMuteStateKey` / `…SoloStateKey` | `m` / `s` | mute / solo の状態 |
| `BgTrackFaderDataRecEnableStateKey` | `r` | 録音待機の状態 |
| `BgFaderEventKey` | `/fader` | Remote **から来る**フェーダーイベント（`handleFader:`） |
| `BgAllTracksInfoKey` / `BgSelectedTrackInfoKey` | `/ati` / `/sti` | トラック一覧 / 選択トラックの情報 |
| `BgTrackInfo…Key` | `n` 名前、`tn` トラック番号、`t` 種類、`p` パンの種類、`ip` 独立したパン、`c` 色、`nc` チャンネル数 | これらの辞書のメンバー |
| `BgTrackSelectionStatePrefix` | `/trackSelectionStates` | 選択状態 |
| `BgLevelMeters…Key` | `lmL`、`lmR`、`ti`、`iMT`、`mlmv`、`pklv` | メーター |
| `BgProtocolVersionPrefix` | `/protocolVersion` | プロトコルバージョンのメッセージ |
| `BgHostTypeKey`、`BgJSONSupportKey`、`BgHostLocaleIdentifierKey` | `/hostType`、`/jsonSupport`、`/hostLocaleIdentifier` | ハンドシェイク時の属性 |
| `BgKeyCommand…` | `/keyCommand`、`/commandsQuery`、`/commandsResponse`、`/groupsQuery`、`/groupsResponse`、`/commandSearch`、`/commandResponse`、`/actionNum`、`/localizationRequest|Response`、`/keyCommandDictResponse` | キーコマンドの一覧と実行（まだ追跡していない） |

`strings` で既に見つかっているもの（SA-002 / osc-address-strings）は、
`/transport/headerState`、`/transport/playButtonFlags`、`/transport/stopButtonState`、
`/transport/pauseplay`、`/transport/sync`、`/transport/clickWhileRecording`、
`/logicClock/currentTempo|locator|songLength`、`/mixerLevels`。

## 2. 接続時の処理（Logic 側）

`LgLogicRemoteController -didConnectToPeerID:` は、メインキュー上で
ブロック `FUN_01699828` を実行する。

1. ルーターへ peer を知らせる。
2. この peer に結び付いた、登録済みの Remote コントロールサーフェス・オブジェクトごとに、
   フィードバック更新 `FUN_00efe9b4` を実行する（サーフェスのフィードバックをすべて再送）。
3. 現在の song を使い、コントローラーの「すべて送る」処理を呼ぶ。
4. peer の**プロトコルバージョンが 10 未満**なら、
   "The version of Logic Remote on … needs to be updated …" を表示し、切断ハンドラーを呼ぶ。

したがって、クライアントはプロトコルバージョン ≥ 10 を報告する必要がある。
Logic 自身が Bonjour TXT で公開する `/protocolVersion=10` と一致する
（architecture.md §3.1）。クライアント側のバージョンが `/protocolVersion` で
届くかは仮説（確信度は中。定数が存在し、検査は peer ごとのバージョンを読むため）。

## 3. 状態辞書と変更マスク

`-_addGInstAndTrackFaderStatesDictForInstWithID:trackID:pSong:changedMask:` は、次を行う。

- `NSNumber(instID)` をキーにするインストゥルメントごとの辞書を作成 / 更新する。
  `vL` は `mask == 0` または bit 0、`s` は `mask == 0` または bit 13、
  `m` は `mask == 0` または bits 12/14 のいずれかが立っている場合に入れる。
  トラックの辞書には、`mask == 0` または bit 2 の場合に `r` を入れる。
- **`changedMask == 0` は、すべてのキーを含める。**
  これが全項目を送るモードであり、0 以外のマスクでは一部の項目だけを更新する。
- `-collectGInstFaderStatesForInstID:changedMask:` は、`instID == 0xFFFFFFFF` の場合、
  全インストゥルメントをたどる。`-handleUpdateBits:` は `updateBitsArray` の
  変更通知を受け取り、要素ごとのハンドラーを呼ぶ。こちらは差分更新。
- `-sendCollectedGInstAndTrackFaderDataIfNeeded` は `{g: instDict, t: trackDict}` を作り、
  どちらかの辞書が空でない場合に限り、`/gtFaderData` として **TCP 経由**
  （`useTCP: 1`）で送る。

コード上の `vL` の表現は `(int8 at +0x8b) << 24`。
符号付き byte を上位 8 bits に置く。dB との対応はまだ確認していない。

## 4. トランスポート

- `-setHeaderState:` は 64-bit 値を保存し、**変化した場合だけ**、
  整数を引数に `/transport/headerState` を送る。
- その後の ARM64 とセレクタースロットの解析
  [SA-AE-STATE-002](SA-AE-STATE-002-native-transport-state.md) で、
  `FUN_01ba7fa0` が `setTransportStopButtonState:`、
  `FUN_01ba7f20` が `setTransportClickWhileRecording:` と判明した。
  `-updateTransportButtonStates` は、これらの setter を通して
  `/transport/stopButtonState` と `/transport/clickWhileRecording` を送る。
  `/transport/playButtonFlags` は別の処理、`0x0168f238` の
  `sendTransportPlayButtonFlags` で構築する。これらは静的な解析結果であり、
  実行時の値と、完全なトランスポート状態のスキーマは未検証。

## 5. 制約: キーコマンドの初期設定では状態 0 を省略する

訂正と対象範囲の明確化: 以前記載した「初期値 0 を省略する」という結果は、
**`/keyCommandStateUpdate` の静的な解析結果**である。
実機セッションの通信記録でも、`/gtFaderData` の観測結果でもない。
SA-AE-STATE-002 には、初期コマンド状態が 0 の送信を飛ばす
`keyCommandStateSetup:` の分岐（`0x01683c48..0x01683c50`）を記録している。
購読開始後の更新では 0 を送ることがある。
独立した Remote クライアントや実際の通信記録による裏付けはまだない。

静的解析から分かることと、クライアント側で守るべき扱いは次のとおり。

- §3 の `/gtFaderData` の関数は、`changedMask == 0` なら、すべてのフィールドの
  キーを出力する。値が 0 のメンバーを省略するという根拠はない。
  接続時の収集が対象となる全インストゥルメント / トラックを列挙し、
  受信側で完全なスナップショットになるかは、まだ不明。
- 任意のクライアントや logicctl は、存在しないキーを「未報告」（不明）として扱い、
  0 / off と解釈しない。初回の応答**と**その後の差分更新から状態を組み立てる。
  スナップショット内にフィールドがないだけでは、書き込みを `verified` にしない。
  どちらの経路でも報告されないフィールドは不明のまま。

次の検証実験は、以下の順で行う。

1. 静的解析: `FUN_00efe9b4`（フィードバック更新）と、
   `handleUpdateBits:` が呼ぶ要素ごとのハンドラーを逆コンパイルする。
   `FUN_01b407c0` はセレクタースタブなので、実体を解決する。
2. 静的解析: `/ati`、`/sti`、`/trackSelectionStates` の辞書を構築する場所を探し、
   値が 0 のメンバーを省略するか調べる。
3. 動的解析（実際の Logic Remote または自前の MPC peer が必要）:
   初回応答と、1 トラックの mute ON/OFF 更新を記録し、含まれるキーを前後で比較する。

追記（2026-10-02）: 手順 1・2 の静的な部分は
[SA-REMOTE-STATE-001](SA-REMOTE-STATE-001.md) で完了した。`FUN_01b407c0` は `handleUpdateBitsForElement:`、
`/ati`・`/sti`・`/trackSelectionStates` の辞書は `FUN_01696ebc`・`updateSelectedTrackInfo`・`sendTrackSelectionStates` で作られ、
どれも値 0 のメンバーを省略しない（省略するのは `keyCommandStateSetup:` の初回だけ）。手順 3 は PLAN-05（承認待ち）が必要。

## 6. SA-002 の訂正

`Logic Remote.bundle` の `_CSFeedback` は**メッセージを作る関数ではない**。
Assign のフィードバック種別を返す。テーブル要素の `+0x30` のポインターが
null なら `0`、そうでなければ `+0x38` の値を返す。既定値は 8。

抽出スクリプト `Tools/ghidra/remote_table.py` は `+0x18` の word を
"flags" として出力するが、その意味は未検証。
したがって、各要素には少なくともフィードバックのポインター（`+0x30`）と
種別（`+0x38`）があり、SA-002 ではこれらを解読していなかった。
