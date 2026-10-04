[日本語](SA-REMOTE-STATE-001.md) | [English](SA-REMOTE-STATE-001.en.md)

# SA-REMOTE-STATE-001: Logic Remote の状態送信 — 初回送信と差分更新

| 項目 | 内容 |
|---|---|
| 日付 | 2026-10-02 |
| Logic | 12.3.1（6682）、macOS 27.0 |
| 対象（arm64） | `Logic.framework`（`LgLogicRemoteController`、arm64 のみ `2f141e1a…`）、`MACore.framework` の `Bg*` 定数（arm64 スライス `99a4a9ad…`） |
| 方法 | **静的解析のみ**。Ghidra 12.1.4 の限定逆コンパイル（`Tools/ghidra/query.sh`）。Logic には何も送信せず、接続もしていない |
| 出力（ローカルのみ） | `Research/raw/ghidra/q-p6-state.c`、`q-p6-state2.c`、`q-p6-fader.c`、`q-p6-type.c`、`q-p6-stubs*.c` |
| 関連 | [SA-005](SA-005-logic-remote-state-push.md)（状態送信の概要）・[SA-REMOTE-SESSION-001](SA-REMOTE-SESSION-001.md)（接続）・[SA-REMOTE-FRAME-001](SA-REMOTE-FRAME-001.md)（フレーム） |
| 機械可読 | [`Research/protocol/logic-remote-state.schema.json`](../protocol/logic-remote-state.schema.json) |
| 計画 | PLAN-06 の**静的部分**。受信実験は PLAN-05（承認待ち）が必要で、まだ行っていない |

**確信度の約束:** 逆コンパイルの内容と一致する事実は「確認」、そこからの推論は「仮説」と書く。
実機の通信では何も確認していない。表の「根拠」は `Logic.framework` 内の関数アドレス。

## 1. 要点

1. **初回送信は専用の処理ではなく、差分の処理を一巡させたもの。** 接続後の `sendWakeupMessageInSong:activeSongChanged:`（0x016843b8）は、
   差分用の `handleUM_*:` を引数 `nil` で順に呼ぶ（§3）。初回と差分で別々のスキーマを覚える必要はない（確認）。
2. **同じアドレスが続けて 2 回届きうる。** 初回送信の中で `/ati` と `/allTrackCount`・`/trackCount` が、
   別の経路から重ねて送られる（§3.2）。受け手は「同じ内容の再送」を許す設計にする（仮説。通信で未確認）。
3. **`/ati` は「トラックごとの辞書の配列」ではなく、13 本の並行配列。** 同じ添字の要素が同じストリップを表す（§4）。
4. **`/gtFaderData` の辞書は値 0 を省略しない**（`r` だけは対象を引けたときのみ入る）。0 の省略があるのは `keyCommandStateSetup:` の初回だけ（§7、確認。ただしコード上の話）。
5. **`/sti` と `/trackSelectionStates` は、引数が NSKeyedArchiver のバイト列。** `/sti` はさらに MAZP で圧縮する（§5、確認）。

## 2. 送信に使う関数

| 役割 | 関数 | アドレス |
|---|---|---|
| 初回送信（接続・曲の切替） | `sendWakeupMessageInSong:activeSongChanged:` | 0x016843b8 |
| トラック一覧を作って送る | `sendChannelStripInfo:`（引数なし版は 0x0168dcf4） | 0x0168d478 |
| 1 ストリップ分の情報を詰める（ブロック） | `FUN_01696ebc` | 0x01696ebc |
| `/ati` の送信（変化時のみ） | `setAllTrackInfo:` | 0x016867b4 |
| `/allTrackCount`・`/trackCount`（変化時のみ） | `setAllTrackCount:mixerTrackCount:` | 0x01686564 |
| 差分の入口 | `handleUpdateBits:` → `handleUpdateBitsForElement:` | 0x0168a450 / 0x0168a610 |
| フェーダー状態の収集 | `collectGInstFaderStatesForInstID:changedMask:` | 0x0168c9e0 |
| 1 インスタンス分の辞書 | `_addGInstAndTrackFaderStatesDictForInstWithID:trackID:pSong:changedMask:` | 0x0168c304 |
| `/gtFaderData` の送信 | `sendCollectedGInstAndTrackFaderDataIfNeeded` | 0x0168ccdc |
| 選択トラック | `updateSelectedTrackInfo` / `sendSelectedTrackInfo` | 0x0168e754 / 0x0168e3fc |
| 選択状態 | `sendTrackSelectionStates` | 0x0168e508 |
| 時計 | `handleUM_CLOCK:` | 0x0168f314 |
| 再生ボタンの旗 | `handleUM_PLAY_BUTTON_FLAGS_CHANGED:` | 0x0168f238 |
| 曲の切り替え | `handleUM_SONG:` | 0x0168ac84 |
| 曲が開いているか | `_sendDocOpen:` | 0x01689c18 |

Ghidra が `FUN_01bXXXXX` と呼ぶ小さな関数は、Objective-C のメッセージ送信スタブである。
各スタブの本体は「セレクターを 1 つ指定して `objc_msgSend` する」だけなので、
スタブのアドレスを逆コンパイルすればセレクター名が分かる（この調査で約 70 個を解決した。手順は §9）。

## 3. 初回送信の順序（確認）

`sendWakeupMessageInSong:activeSongChanged:` が呼ぶ順に並べる。`→` の右はスタブから解決した実体。

| # | 送るもの / 呼ぶもの | 備考 |
|---|---|---|
| 1 | 蓄積中のフェーダーデータを破棄（`setCollectedGInstFaderData:nil`、`setCollectedTrackFaderData:nil`） | 古い差分を持ち越さない |
| 2 | `/mixer/hideRecordButtons`、`/mixer/automationEnabled` | 曲があれば曲の設定から、なければ既定値 |
| 3 | `setMagicMentorActive:`、`setChordTrainerActive:` | 内部の状態設定 |
| 4 | `/hostType`、`/hostLocaleIdentifier` | 値はホストの種別・ロケール識別子 |
| 5 | `sendChannelStripInfo` | 直前に `/ati` のキャッシュ（+0xc0）を `nil` にする。中身は下の **5a〜5f**。§4 |
| 6 | `/allTrackCount`、`/trackCount`、`/undoLabel`、`/redoLabel` | 件数は `allTrackCount` / `mixerTrackCount` の値 |
| 7 | `/ati`（`useTCP: 1`） | `allTrackInfo` の内容をもう一度送る |
| 8 | `sendMIDIMonoStateForSong:` | MIDI モノ状態 |
| 9 | `setMarkerList:nil` と **`handleUM_MARKER:` `SYNC:` `FORMAT:` `CHSIGNTIME:` `LOCAT:` `VCLOCKSIGNAT:` `CHLEN:` `RULERCHANGED:` `CLOCK:`**（すべて `nil`） | 差分の処理をそのまま呼ぶ |
| 10 | `/keyCommand/currentLogicLocale`、`/tron/loops/setPreviewVolume` | |
| 11 | `handleUM_GLOBALPREFS:`、`handleUM_AUDIOPREFS:`（`nil`）、`dimValueChanged:` | |
| 12 | `updateActiveGInstSet:`、`sendSelectedTrackInfo`（→ `/sti`、§5）、`updateNoteRepeat`、`sendBgSongSettings:` | |
| 13 | `/transport/stopButtonState`、`/transport/headerState`、`/transport/clickWhileRecording`、`/transport/playButtonFlags` | §6 |
| 14 | `dismissAlert`、`_sendDocOpen:`（曲が開いているかを渡す）、`updateLTPorChordTrainerStatus`、`updateRecallSoloState`、`updatePeakHold`、`updateReturnSpeed` | |
| 15 | `/colorIndexMap` | 色の番号表 |
| 16 | `sendTronFlags:`、`sendCurrentGridFocusInfo`、`sendStepSequencerRegionInfoToRemote…`、`sendSendsOnFaderChangeMessage` | |
| 17 | `activeSongChanged` が真のときだけ、`tronMessageRouter` に対する 1 回の呼び出し | 内容は未解析 |

`sendChannelStripInfo:` の中の順序（確認。表の 5 の内訳）:

| # | 送るもの / 呼ぶもの |
|---|---|
| 5a | ストリップごとの追加メッセージ（§4.3）を 1 つの辞書にまとめて送る。空なら送らない |
| 5b | `setAllTrackCount:mixerTrackCount:` → 件数が前回と違うとき、`/allTrackCount`、`/trackCount`、`/mixerLevels/resetAll`、`/bankNavigator/trackLevels/resetAll`（後ろ 2 つの引数は `nil`） |
| 5c | `setAllTrackInfo:` → `/ati`（1 回目） |
| 5d | `handleUM_TRACKSEL:nil`、`_sendArpState`、`updateNoteRepeat`、`sendTrackSelectionStates`（→ `/trackSelectionStates`） |
| 5e | `collectGInstFaderStatesForInstID:0xFFFFFFFF changedMask:0`（全インスタンス・全項目を蓄積） |
| 5f | `sendCollectedGInstAndTrackFaderDataIfNeeded` → `/gtFaderData`（§8） |

`/gtFaderData` と `/trackSelectionStates` は、上位の表には出てこない。どちらも `sendChannelStripInfo:` の内側（5d〜5f）で送られる。
**`/gtFaderData` は `/ati` の 1 回目より後で、`/ati` の 2 回目より前**に届くはずである（コードの順序。通信では未確認）。

### 3.1 「初回 = 差分の一巡」の意味

表の 9 行目は、時計・拍子・ロケーター・マーカーなどの差分ハンドラーを `nil` 引数で呼んでいる。
ハンドラーは通知の内容（`userInfo`）ではなく**Logic の現在の値**を読むため、`nil` でも現在値が送られる（仮説。確信度: 中。
`handleUM_CLOCK:` は `param_3` を使わず、曲から直接読んでいることを確認した）。
したがって、**時計・トランスポートの初回と差分は同じスキーマ**と考えてよい。

### 3.2 重ねて届く可能性（仮説）

- `sendChannelStripInfo` は最後に `setAllTrackInfo:` を呼ぶ。`setAllTrackInfo:` は「前回と違うときだけ」`/ati` を送るが、
  表の 5 行目でキャッシュを `nil` にしているため、必ず送る。表の 7 行目で、同じ内容をもう一度送る。
- `setAllTrackCount:mixerTrackCount:` は件数が変わったときだけ `/allTrackCount`・`/trackCount` を送る。
  表の 6 行目も無条件に送る。
- どちらも**内容は同じ**はずだが、通信では未確認。クライアントは「最後に届いたものが正」とし、重複を異常扱いしない。

### 3.3 曲の切り替え（確認。分岐の細部は未整理）

`handleUM_SONG:`（0x0168ac84）が、曲の通知を受けて次のように動く。

1. 通知の種別が 0xd0 以外のとき、内部のグローバル（`DAT_0276e2a0`）を 0 にする。
2. 通知の前後で、「active な曲」（曲の記録の +0x85c が 1 のもの）を調べる。
3. **active な曲が変わったとき**（新しく active になった、または別の曲に替わった）：
   - ドキュメントのワークスペースとマッピングを読み直す（`reloadWorkspaceAndMappingsInDocument:avoiding:`）。
   - **トラックの取り込み中**（`isImportingTracks`）**でなければ、新しい曲で `sendWakeupMessageInSong:activeSongChanged:` を `activeSongChanged = YES` で呼ぶ。**
     つまり、§3 の初回送信が**もう一度一巡**する（`/ati` のキャッシュも空にされるので、`/ati` も送り直される）。
   - それまで active な曲が無かった場合は、さらに `/docOpen` = 真を送る。
4. active な曲が無くなったとき：`/docOpen` = 偽を送り、記録していた曲の参照（+0x38）を 0 にする。

`/docOpen`（`_sendDocOpen:`）は真偽値で、**UDP と TCP の両方で 1 回ずつ**送る。同じ値が 2 回届く。

含意（仮説。確信度: 中）：

- 曲を切り替えると、状態は**ほぼ全部が送り直される**。クライアントは、古い曲のトラック・フェーダー値などを捨て、新しい `/ati` 以降で作り直す必要がある。
  終了の合図は見つかっていないので、いつ作り直しが終わったかは分からない。
- 接続（再接続を含む）の初回送信も、同じ関数を `activeSongChanged = NO` で呼ぶ（§3.4）。
- 曲を取り込み中の切り替えでは、初回送信は呼ばれない。その間に何が送られるかは未確認。

### 3.4 接続したとき（確認）

`didConnectToPeerID:` が呼ぶブロック（`FUN_01699828`）の順序：

1. ルーターへ、この peer を知らせる。
2. この peer に結び付いた、Remote のコントロールサーフェスの各オブジェクトについて、フィードバックの更新を実行する（`FUN_00efe9b4`）。
3. **曲が開いているときだけ**、その曲で `sendWakeupMessageInSong:activeSongChanged:` を**`activeSongChanged = NO`** で呼ぶ。曲が開いていなければ、この呼び出しは無い。
4. その後で、peer のバージョンを確かめ、**10 未満なら**「Logic Remote を更新してください」のアラートを出し、切断の処理を呼ぶ。

つまり、コード上の順序は「初回送信 → バージョン確認」である（バージョンを待つ処理がブロックより前に済んでいるかは未確認。SA-REMOTE-SESSION-001 §4・§5）。
曲の切り替え（§3.3）との違いは `activeSongChanged` が NO であること（§3 の表 17 の呼び出しが無い）。

## 4. `/ati` — 全トラックの情報

`setAllTrackInfo:` は `NSDictionary` をそのまま `/ati`（`useTCP: 1`）で送る。**前回の辞書と等しければ送らない**（確認）。
辞書は 13 個のキーを持ち、それぞれが**同じ長さの配列**である。添字 *i* の要素がすべて同じストリップを指す（確認。ブロックが 1 ストリップごとに 13 本へ 1 個ずつ追加する）。

| キー（通信上の値） | 配列の要素 | 値の出どころ（確認） | 意味・値域 |
|---|---|---|---|
| `c` | 辞書 `{nc, sc, tnc, tsc}`、各 4 バイトの `NSData` | 色の計算（4 色） | 通常 / 選択 / アイコン通常 / アイコン選択の色。**4 バイトの並びは未確認**（先頭が 0xFF の色がある） |
| `n` | 辞書 `{"name": 文字列, "gindex": 整数}` | トラック名と、ストリップ情報の `identifier` | `gindex` は `/gtFaderData` の `g` のキーと**同じ値**（§8。確認: 同じ種類のオブジェクトの同じアクセサ。通信では未確認） |
| `t` | 整数（`char`） | `trackTypeForTrack:seqID:ginst:inSong:`（0x01693e90） | **0〜10 を返しうる**。各値の意味は**未解決**（§10） |
| `nc` | 整数 | **曲**の 1 バイト（+0xd4）を、15 要素の表 `DAT_01d59030` で引いた値。曲が無ければ 0 | チャンネル数（キー名より。仮説。出どころが曲の値で、ストリップごとではないように見える。疑問が残る） |
| `p` | 整数（`char`） | `allowedElementsForStrip:` の bit 27 が立つときだけ、曲の設定から表引き（値は 0, -5, -1, -4, -1, -4 のいずれか）。それ以外は -1。曲が無いときは、`t` が 4 かどうかで 2 種類の定数（値は未解決） | パンの種類（キー名より。仮説） |
| `tn` | 整数 | `numberOfStrip:`。0 のときは -1 | ストリップの番号（キー名より。仮説） |
| `BgTrackInfoTrackIDKey` | 整数（long） | `(folder << 16) \| (track & 0xffff)` | トラック ID（下位 16 ビット = トラック、上位 = フォルダー）。寿命は**未確認**（PLAN-08） |
| `BgTrackInfoTrackUUIDKey` | 文字列 | トラックの UUID（`CUUIDBase::CreateStringConst`）。取れなければ短い既定の文字列（内容は未確認） | |
| `BgTrackInfoIconIDKey` | 整数 | ストリップ内部の 16 ビット値（+0x7e） | アイコン番号（キー名より。仮説） |
| `BgTrackInfoHasArrangeKey` | 真偽 | 位置の照合 | 「アレンジ側にも存在する」（キー名より。仮説） |
| `BgTrackInfoArrangeHiddenKey` | 真偽 | 親の種類などから算出 | 「アレンジで隠れている」（キー名より。仮説） |
| `BgTrackInfoCollapsibleInfoKey` | 整数 | `_collapsibleInfoForTrack:parentMSeq:`（0x0168d3a8） | §4.2 |
| `BgTrackInfoMetaInfoFlagsKey` | 符号なし整数 | `trackMetaInfoFlagsForTrack:spu:inSong:`（0x016944e4） | 0 または 1。第 3 引数（`spu`）の 32 ビット値（+0x84）の bit 5。`spu` が無ければ 0。`/ati` のブロックでは曲のオブジェクトが渡されており、**全ストリップで同じ値になる可能性**がある（仮説。確信度: 中） |

キーの名前は、通信上の値と定数名が同じものと異なるものがある（[`logic-remote-wire-keys.tsv`](../protocol/logic-remote-wire-keys.tsv)）。
`BgTrackInfo…` で始まる 8 個のキーは、通信上の値も定数名と同じ文字列である（確認。MACore の定数）。

### 4.1 列の対応の確認方法

`FUN_01696ebc` の中で配列は、ブロックの捕捉変数（`param_5 + オフセット`）として渡される。
`sendChannelStripInfo:` はブロックを作るとき、捕捉変数を決まった順に詰める。
この順（+0x20, +0x28, …）と、最後に `dictionaryWithObjects:forKeys:count: 13` へ渡す値の順を突き合わせて、上の表の列を決めた。
捕捉されたオフセットは、+0x48 = 呼び出し元（self）、+0x58 = ミキサーコントローラー、+0xb8 = 曲、+0xc0 = ミキサーのストリップ数で、
ブロック内の用途と矛盾しなかった（検算）。

### 4.2 `CollapsibleInfo` の分解（仮説。確信度: 中）

`_collapsibleInfoForTrack:parentMSeq:` の戻り値は次のビットでできている（コードから読んだ式）。

| ビット | 内容 |
|---|---|
| 0〜7 | トラックの階層の深さ（トラック記録の +0x12 のバイト） |
| 8 | トラック記録の +0x14 の bit 7 |
| 9 | 次の行の深さが「この深さ + 1」である（**子を持つ**と読める） |
| 10 | トラック記録の +0x14 の bit 6 |

ビット 8 と 10 の意味は**不明**。

### 4.3 ストリップごとの追加メッセージ（確認）

ブロックは `/ati` の 13 本とは別に、**ストリップごとのメッセージ**を 1 つの辞書（`sendChannelStripInfo:` の `self`）へ溜める。
溜め終わると `MAPeerRouter` の `sendMessages:toPeer:useTCP:completion:` で**まとめて送る**。
このメッセージは、引数のブロック（トラック ID を受けて真偽を返す）が真を返すストリップに限る。

| アドレス | 引数 | 備考 |
|---|---|---|
| `/mixer/plugins/audio/%lu`、`/mixer/plugins/midi/%lu` | NSKeyedArchiver のバイト列（プラグイン一覧） | 一覧が無ければ整数 0 |
| `/mixer/eq/state/%lu` | 整数 0 / 1 / 2 | 0 = EQ なし、1 = バイパス中、2 = 有効（`pathPointsForEQThumbnailOfStrip:bypassed:` の出力を、`bypassed` が偽なら 2 にしている。確認） |
| `/mixer/eq/path/%lu` | NSKeyedArchiver のバイト列（EQ の曲線の点） | EQ があるとき |
| `/mixer/plugins/slotbase/%lu` | 整数 0 / 1 | ストリップの種類が 1 のとき 1 |
| `/mixer/io/inputname/%lu`、`outputname/%lu` | 辞書 `{LgInputNameKey 等: 名前, …BypassedKey: 真偽}` | 名前が空なら `NoInput` / `NotAssigned` を入れる。真偽は「元の名前が空でない」とき真で、キー名（Bypassed）と向きが合うか**未確認** |
| `/mixer/io/inputgain/%lu` | 辞書 `{LgInputGainDBKey: dB, LgInputGainKey: ゲイン}`（浮動小数） | |
| `/mixer/io/hasPhantomPower/%lu`、`phantomPower/%lu`、`hasHighPassFilter/%lu`、`highPassFilter/%lu`、`hasPhaseInvert/%lu`、`phaseInvert/%lu` ほか | 真偽 | |

- `%lu` に入る値は、逆コンパイルでは見えない（可変長引数）。差分側（§8）では同じ種類のメッセージを `%i` で作り、`updateBitsInstID`（インスタンス ID）を使う。
  両者は**同じ ID を整数の幅違いで整形したもの**と推定する（仮説。確信度: 中）。
- この追加メッセージの対象は、`sendChannelStripInfo:` の引数のブロックで決まる。引数なし版（0x0168dcf4）はグローバルなブロックを渡す。
  そのブロックの本体は**未解析**。したがって「どのストリップに付くか」は不明。

## 5. `/sti` と `/trackSelectionStates`

### `/sti`（選択トラックの情報）

- `updateSelectedTrackInfo`（0x0168e754）が辞書を作り、`setSelectedTrackInfo:`（0x0168df54）が前回と等しいか比べる。
  **違うときだけ** `sendSelectedTrackInfo`（0x0168e3fc）が送る（確認）。
- 辞書の中身（確認）：

  | キー | 値 |
  |---|---|
  | `n` | トラック名。何も選択していなければ `NoTrackSelected` |
  | `t` | 整数（`char`）。選択トラックの内部記録の +3 のバイト。**`/ati` の `t`（`trackTypeForTrack:…`）とは別の算出**で、同じ値域とは限らない |
  | `BgTrackInfoMetaInfoFlagsKey` | 符号なし整数。`trackMetaInfoFlagsForTrack:spu:inSong:`（`/ati` と同じ関数） |
  | `tn` | 整数（算出元は未整理。キー名より、ストリップの番号。仮説） |
  | `BgTrackInfoShowArpeggiatorButtonKey` | 真偽。選択トラックにアルペジエーターのボタンを出すか |
  | `BgTrackInfoIndexKey` | 整数。`getStrip:forTrackWithID:` が返すストリップの添字。見つからなければ `NSIntegerMax`（0x7fffffffffffffff） |

  何も選択していないときは、`n` = `NoTrackSelected` に加え、`t`・`BgTrackInfoMetaInfoFlagsKey`・`tn`・`BgTrackInfoIndexKey` の 4 つを送る（値の内訳は未整理）。

- 送るときは `NSKeyedArchiver` で辞書をバイト列にし、さらに `maCompressedDataWithCompressionLevel:9` で圧縮する（確認。セレクター名はスタブから解決）。
  この圧縮は [SA-REMOTE-FRAME-001](SA-REMOTE-FRAME-001.md) の **MAZP コンテナ**にあたると推定する（仮説。確信度: 中）。
  フレーム全体の圧縮（先頭タグの bit 7）とは別の層である。したがって `/sti` の引数は、**フレームの中のバイト列が、さらに MAZP**になる。
- 送信直後に `_sendArpState`、`updateNoteRepeat`、`sendTrackSelectionStates` を続けて呼ぶ（確認）。

### `/trackSelectionStates`

- `sendTrackSelectionStates`（0x0168e508）は、辞書 `{"PreviousTrackKey": 真偽, "NextTrackKey": 真偽}`（通信上の値は MACore の定数から解決）を
  NSKeyedArchiver でバイト列にして送る（確認。**圧縮はしない**）。
- 2 つの真偽は、キーコマンド ID `0x4f8` / `0x4f9` の状態を評価した結果（`!= 0` なら真）。
  コマンドが有効でない場合（グローバルのフラグ `DAT_02686180/81` が真でない）は、評価せずに**常に真**を送る（確認）。
  キー名より「前 / 次のトラックへ移れるか」の意味と推定（仮説。確信度: 中）。

## 6. トランスポートと時計

| アドレス | 引数 | 送るとき（確認） | 備考 |
|---|---|---|---|
| `/transport/stopButtonState` | 整数 | 初回送信（表 13）。差分は `updateTransportButtonStates` | 値の意味は未解決 |
| `/transport/headerState` | 整数 | 初回送信。差分は `setHeaderState:` で**変化時のみ**（SA-005） | 〃 |
| `/transport/clickWhileRecording` | 真偽 | 初回送信。差分は setter 経由 | |
| `/transport/playButtonFlags` | `char`（グローバル `DAT_02765b85`） | 初回送信と `handleUM_PLAY_BUTTON_FLAGS_CHANGED:` | SA-005 §4 の「0x0168f238」はこの関数。**ボタンの旗を単に送るだけ**で、構築はしない |
| `/logicClock/spl` | `long long` | `handleUM_CLOCK:`（`useTCP: 0` = UDP） | サンプル位置（キー名より。仮説） |
| `/logicClock/currentTempo` | 整数 | `handleUM_CLOCK:`（UDP） | 単位は未確認（BPM そのものか 100 倍かなど） |
| `/multiTempo` | 真偽 | `handleUM_CLOCK:`（UDP） | **値の向きに注意**（下記） |

`/multiTempo` の注意: コードは、曲のテンポ列をたどり、**値が変わる要素が見つからなければ 1 を送る**（途中で違う値を見つけると 0）。
名前は「複数のテンポがある」を連想させるが、コードの形は逆（1 = 全部同じ）に見える。
**どちらが正しいか（名前、または私の読み違い）は未確認**。比較しているのが本当にテンポ値かも未確認。通信での確認まで、この値を使った判断をしない。

`handleUM_PLAY:`（0x0168f0dc）は、通知の種別が 0x85 / 0xdd で、かつ内部の値（`local_70`）が非 0 の場合を除き、
`/keyCommandStateUpdate` に `{<定数>: 0}` を送る。他の種別のときは、内部のグローバル（`DAT_0276e2a0`）も 0 にする。
キー（定数）は未解決で、再生状態そのものではなく、キーコマンドの状態を 0 に戻す処理に見える（仮説。確信度: 低）。

再生・録音の**実際の状態**を表すと分かっているのは、今のところ上の `/transport/*` の 4 つだけである。
値の意味づけは [SA-AE-STATE-002](SA-AE-STATE-002-native-transport-state.md) の範囲で、ここでは扱わない。

## 7. 値 0 の扱い（SA-005 §5 の続き）

| 経路 | 0 を省略するか | 根拠 |
|---|---|---|
| `/gtFaderData` の `vL` `s` `m` `ip` | **省略しない**。`changedMask == 0` なら必ず `NSNumber` で入れる（値が 0 でも入れる） | `_addGInstAndTrackFaderStatesDict…`（0x0168c304）。`setObject:forKeyedSubscript:` に `numberWithInt:0` を渡している |
| `/gtFaderData` の `r` | 録音待機の対象を引けたときだけ入れる（引けなければキー自体が無い） | 同上。`FUN_001a1dcc` の結果が空のとき飛ばす |
| `/gtFaderData` の対象そのもの | 楽器を引けない（`FUN_01a15c7c` が空）と、そのインスタンスは**丸ごと省略** | 同上の冒頭で `return` |
| `/ati` の 13 本 | 省略しない（配列に必ず 1 要素追加） | ブロック |
| `keyCommandStateSetup:`（初回、`/keyCommandStateUpdate`） | **0 は送らない** | 0x01683ad8: 値が 0 なら辞書を作らず次へ |
| `keyCommandStateChanged:`（差分） | **0 も送る** | 0x0168e1d4 |

したがって、省略が起きるのは**キーコマンドの初回だけ**で、`/ati` や `/gtFaderData` ではない（コード上の確認）。
ただし、送信側の辞書に載っていても、**フレーム化・受信の途中で落ちるかは通信でしか確かめられない**。

## 8. `/gtFaderData` — 構造と差分（SA-005 §3 の補足）

```
/gtFaderData = {
  "g": { <instID:整数>: { "vL": 整数, "s": 整数, "m": 整数 } , … },
  "t": { <trackID:整数>: { "r": 整数, "ip": 整数 } , … }
}
```

- 内側の辞書のキーは `NSNumber`。plist / JSON は文字列キーしか持てないため、この辞書は NSKeyedArchiver（形式 2）で送られると推定している
  （[SA-REMOTE-FRAME-001 §4](SA-REMOTE-FRAME-001.md)。仮説）。
- `trackID` は `/ati` の `BgTrackInfoTrackIDKey` と同じ値（`(folder << 16) | track`。`getOrCreateTrackDict:` が
  `numberWithLong:` でキーにする。確認）。
- `instID` は、ミキサーのストリップ情報の `identifier`。`/ati` の `n` の `gindex` も、同じ種類のオブジェクトの同じ `identifier` である。
  両方とも `consolidatedChannelStrips` の要素を列挙しており（`/ati` は `consolidatedChannelStripsAndGetMixerStripCount:`、
  フェーダー側は `consolidatedChannelStrips`）、差分側の `updateBitsInstID` も `getStrip:forGindex:` に渡される。
  したがって `gindex` = `instID` と見てよい（確認: コード上。確信度: 中〜高。通信では未確認）。

### 8.1 変更マスクと項目

| `changedMask` のビット | 項目 | 値（確認 / 仮説） |
|---|---|---|
| 0 | `vL`（`g`） | 32 ビット整数。`(int8)(+0x8b) << 24`。ただし内部の 32 ビット値（+0xcc）の上位バイトが同じなら、その値をそのまま使う（確認）。**フェーダー位置の符号付き 32 ビット表現**（仮説）。MCU の 14 ビットとは別物で、変換は未確認 |
| 13 | `s`（`g`） | 符号付き 1 バイト。`+0x8c`。値域は**未確認**（0 / 1 以外がありうる） |
| 12, 14 | `m`（`g`） | 0 / 1 を基本に、2 / 3 になることがある。ビット 1 が立つ、または特定の条件（グループなどの影響と推測）で 2 / 3。さらにグローバルフラグ `DAT_0261e118` が真だと 0x80 を足す。**意味は未確認** |
| 2 | `r`（`t`） | 0, 1, 3, 0x40, 0x80 のいずれか（コードの分岐から）。録音待機の種類（キー名より。仮説） |
| 32 | `ip`（`t`） | 最大 12 ビットのマスク。ビット *k* は、*k* 番目のチャンネルの内部フラグ（+0x3a の bit 2）（確認）。キー名より「独立パン」（仮説） |

- `changedMask == 0` は全項目を含む（SA-005 §3 の確認）。
- 差分の入口 `handleUpdateBitsForElement:` は、`updateBitsValue` が `0x100007005` のビット（0, 2, 12, 13, 14, 32）のどれかを含み、
  かつ `updateBitsInstID != -1` のとき、`collectGInstFaderStatesForInstID:changedMask:` を呼ぶ（確認）。
  つまり**項目ごとの変更ビットは上の 5 行と一致**する。
- 蓄積はコントローラー側の 2 つの辞書（+0x100 = `g`、+0x108 = `t`）に溜まり、`sendCollectedGInstAndTrackFaderDataIfNeeded` が
  どちらかが空でなく、かつ接続が有効（`FUN_01b1c480` = `connected`）のときだけ `/gtFaderData` として**まとめて 1 通**送る（確認。`useTCP: 1`）。
  送ったあとに蓄積を空にする。

### 8.2 他の変更ビット

`handleUpdateBitsForElement:` は、ほかのビットでも別のメッセージを送る（確認）。

| ビット | 送るもの |
|---|---|
| 11 | `/mixer/plugins/audio/%i`、`/mixer/plugins/midi/%i`（プラグイン一覧。NSKeyedArchiver）、`/mixer/eq/state/%i`（整数 1 / 2） |
| 29 | `/mixer/eq/path/%i`（EQ の曲線の点。NSKeyedArchiver） |

`handleUpdateBits:`（0x0168a450）は、通知の `userInfo` にある `updateBitsArray` の要素をひとつずつ `handleUpdateBitsForElement:` に渡す。
処理中だけ `cachedCurrentMixerController` を設定し、終わると解除する。
`handleUM_TRACKSEL:`（0x0168e0ac）は `updateActiveGInstSet:` と `updateSelectedTrackInfo` を呼ぶ。つまり**選択の変更が `/sti` を作り直す**。

## 9. 手順と再現

解析の手順（すべてローカルのみ。Logic への送信なし）。

1. `Tools/ghidra/query.sh Logic.arm64 <出力名> 0x… 0x…` で、アドレスを指定して逆コンパイルする（[`XrefDecompile.java`](../../Tools/ghidra/XrefDecompile.java)）。
2. `objc_stub::FUN_01bXXXXX` と出る呼び出しは、スタブのアドレスを同じ方法で逆コンパイルすると
   `PTR_s_<セレクター名>_…` の形でセレクターが読める。
3. 文字列定数は [`logic-remote-wire-keys.tsv`](../protocol/logic-remote-wire-keys.tsv)（MACore の `Bg*`）と
   [`osc-address-strings.tsv`](osc-address-strings.tsv)（バイナリ内のアドレス文字列）で照合する。
   `/allTrackCount`、`/redoLabel` などは後者の表に**載っていない**。Ghidra が付けた `cf_` ラベル（文字列の内容から付く）だけが根拠で、
   文字列そのものの確認は未了。

## 10. 不明なこと・次の検証

| 項目 | 状態 | 次の手 |
|---|---|---|
| `t`（トラックの種類）の値 0〜10 の意味 | 未解決。戻り値の集合は読めたが、分岐の意味が未整理 | 関数の分岐を読み切り、既知のトラック種別（オーディオ・ソフトウェア音源・フォルダー等）と対応づける。PLAN-08 の前提 |
| `p`（パンの種類）・`nc`・`DAT_01d59030` の値表 | 未読 | 表の内容を読み出す |
| `c` の 4 バイトの並び | 未確認 | 色の計算関数（`FUN_017e5998` ほか）を読む |
| `sendChannelStripInfo` の引数なし版が渡すブロックの本体 | 未解析 | どのストリップに追加メッセージが付くかが決まる |
| `gindex` と `instID` が同じ値であること | コード上は同じ（§8）。通信では未確認 | 受信で照合 |
| `/multiTempo` の向き、`/logicClock/currentTempo` の単位 | 未確認 | 受信実験 |
| `vL` と dB / MCU のフェーダー値の対応 | 未確認 | 受信実験で既知の dB と並べる（PLAN-02 の MCU 読み取りが比較対象になる） |
| 重ねて届くメッセージの内容が一致するか | 未確認 | 受信実験 |
| フレーム化・受信の途中で 0 が落ちないか | 未確認 | 受信実験 |
| 曲の切替・再接続で何が再送されるか | 曲の切替は §3.3、接続は §3.4（どちらも確認）。表 17 の `tronMessageRouter` の呼び出しの中身は未解析 | 静的に続行。実機は PLAN-05 |
| 初回送信が完了したことを知る合図 | **見つかっていない** | 最後の送信（表 16 / 17）に終了を示すメッセージがあるか。無ければ「完全性」は別の手で判断する |

### クライアント（logicctl）に反映するときの決まり（提案。実装はしていない）

1. 受信した値だけを状態にする。**届かないキーは「不明」**であって 0 / false ではない（SA-005 §5 と同じ）。
2. 同じアドレスが続けて届いたら、後のものを採用する。内容が食い違えば、その事実を記録する。
3. 初回送信に**終了の合図が見つかっていない**ので、受信のスナップショットを `complete: true` にしない。完全性を主張できる条件は、
   実験で決める（PLAN-06 の受信実験）。
4. `gindex` / `instID` / トラック ID の寿命は未確認なので、接続（セッション）をまたいで使わない（PLAN-08）。
5. `/docOpen` を受けたとき、または曲が替わったと分かったときは、前の曲の状態（トラック・フェーダー値・選択）をすべて捨てる（§3.3）。

この文書は、Logic Remote の実機の通信を観測した結果ではない。受信実験は PLAN-05 の承認後に行う。
