# SA-004: Logic のコマンド処理境界（befehl）とシーケンサーのメッセージキュー

[日本語](SA-004-command-and-engine-boundaries.md) | [English](SA-004-command-and-engine-boundaries.en.md)

| 項目 | 内容 |
|---|---|
| 日付 | 2026-10-01 |
| Logic | 12.3.1（6682）、`Logic.framework` arm64 |
| ツール | `Tools/ghidra/query.sh Logic.arm64 …`（出力: `Research/raw/ghidra/q-cmd.c`、`q-cmdtable.c`、`q-menu.c`、`q-fader.c`） |

## 1. 各 UI 経路で共通のコマンド・ディスパッチャー: `FUN_008663d4(befehl, song, flag, source, x)`

68 の呼び出し元には、メニュー（`CLgAppManager -globalMenuItemCall:`、
`CLgView -localMenuItemCall:`）、ツールバー
（`CLgDocManager -doBefehlForToolbarItem:…`）、トランスポート画面、
`DfDocument` の play/stop/record/undo、Accessibility の操作
（`CLgViewAccessibility* -accessibilityPerformAction:`）、Logic Remote
（`LgLogicRemoteMessageRouter -routeMessage:withArgument:`）、
Notes のリンク（`RemoteCommandSupport`）が含まれる。

呼び出し元がリテラルとして渡すコマンド番号と、そのコードから分かる意味は次のとおり。

| befehl | 呼び出し元 | Logic Remote のテーブル（SA-002） |
|---|---|---|
| 3 | `DfDocument -_playCallbackWithWillFreeze:`、Remote ルーター | `/cs/transport/play` 3 ✓ |
| 4 | `DfDocument -pause`、仮想カウントインの play/record | — |
| 5 | `DfDocument -stop` | `/cs/transport/stop` 5 ✓ |
| 7 | `DfDocument -recordCallback` | `/cs/transport/record` 7 ✓ |
| 10 / 11 | `DfDocument -rewind` / `-forward` | — |
| 12 / 13 | `-fastRewind` / `-fastForward`、トランスポートのボタン | — |
| 15 | `DfDocument -enableCycle:`、ツールバー、AX | `/cs/transport/cycle` 15 ✓ |
| 20 | `-setRecordingReplaceModeEnabled:` | — |
| 29 | `DfDocument -sendPanic` | — |
| 51 | `CLgView -toggleCatchPlayhead` | — |
| 474 | `-setMetronomEnabled:` | `/cs/transport/click` 474 ✓ |
| 535 | `ChordPopoverActionsDelegate -triggerPlayStop` | — |
| 542 | `DfDocument -captureLastRecording` | — |
| 761 / 796 | `DfDocument -undo:` | `/undo` 761、`/redo` 796 ✓ |
| 1040 | `-toggleKillRecallSoloAll` | `/cs/mixer/soloreset` 1040 ✓ |

**H2 を確認:** Assign class 9 の `befehl` は Logic のコマンド ID であり、
メニュー、ツールバー、トランスポート、Accessibility と同じ ID を使っている。

ディスパッチャー内部の処理は次のとおり。

- `befehl < 0x1357` なら、コマンドテーブル `DAT_026883b0[befehl]` を引く。
  要素は 40-byte のエントリーを指し、`+0x18` がハンドラー、`+0x20` が引数。
  ハンドラー `FUN_00f2c010` は `DAT_01cd1d98` を経由して別名のコマンドへ転送する。
- 第 4 引数 `source`: 2 は Notes のリンク。Logic Remote の `/keyCommand/actionNum` も 2 を使う（[SA-REMOTE-KEYCOMMAND-001](SA-REMOTE-KEYCOMMAND-001.md)）。6/7 は修飾キーを読む
  メニュー / キー操作の経路。1 はその処理をスキップする。
- 同じコマンドが 500 ms 以内に 2 回来るとフラグを立てる（`DAT_02701c54`）。
- `FUN_00865cec` を経て実行する。失敗時は `NSBeep` と、
  "Command not available because …" の通知。

コマンドテーブルの構築は `FUN_00863ec4` → `FUN_008630b4` → `FUN_00864230`。
40-byte のエントリー `{int16 befehl @0, handler @0x18, arg @0x20}` のグループを、
機能が利用できる場合に `table[entry.befehl] = &entry` として登録する。

グループは Key Commands 画面の分類に対応する。例は
`GlobalCommands`（672）、`MainWindowTracksandVariousEditors`（290）、
`MainWindowTracks`（247）、`Mixer`（85）、`ViewsShowingTimeRuler`（80）、
`VariousEditors`（67）、`ViewsShowingAutomation`（22）、
`LiveLoopsGrid`（18）、`WindowsShowingAudioFiles`（13）。
ほかに Piano Roll、Score、Step Sequencer、Smart Controls、Control Surfaces などがある。

配列はゼロ初期化領域に置かれ、C++ の静的初期化で構築される。
エントリーに名前はないため、**ファイルから ID と名前の対応を読めない**。
実行中のアプリが必要になる（例: Logic Remote の `/keyCommand/commandsQuery`）。

## 2. Logic Remote の振り分け（`LgLogicRemoteMessageRouter -messageReceivedAtAddress:withArgument:fromPeer:`）

アドレスの先頭により処理を振り分ける。
`/midi…` → MIDI、`BgFaderEventKey` → `-handleFader:`、
`BgStepSequencerEditorActiveKey`、`/cs/` → コントロールサーフェスの Assign 処理
（読み取りロック下）、`/loopBrowser/`、`/sendsOnFader/sendsMenu|sendsTarget`、
`/arrangeOverview/request`、`/alert/`。
その他はメインキューへ送って `-routeMessage:withArgument:` を呼び、
3/4 などの番号でディスパッチャーへ渡す。

`-handleFader:` は 12 bytes 以上のデータ
`{u32 object, …, byte status @5, u16 data @6, u32 value @8}` を受け取る。
MIDI 形式のイベント（status `E0` は pitch bend、それ以外は controller）を作り、
`FUN_00791330(0x0e, &event, object, …)` に渡す。

## 3. シーケンサーのメッセージキュー: `FUN_00791330(type, event, object, …)`

ロックで保護した 1024 × 0x78-byte のリングバッファへメッセージを入れる。
シーケンサーエンジンがこれを読む（インデックスは `DAT_027034a8/ac`）。
キューが満杯の場合は待機し、その後
"Sequencer engine timed out after %d milliseconds" を記録して `TimerMessage()` を呼ぶ。

Type `0x0e` は、オブジェクト宛てのイベントを運ぶ。
`object` はチャンネルストリップ / Environment のオブジェクト ID。

**Hypothesis H4（仮説）:** class-5 の `trackParam` 番号
（volume 7、pan 10、mute 9、solo 3、sends 28–35）は、
Logic の Environment におけるチャンネルストリップの制御番号。
サーフェスによるミキサー変更は controller 形式のイベントになり、
このキューを経てチャンネルストリップ・オブジェクトへ送られる。
確信度は中（Remote のフェーダー経路は確認できたが、
`/cs/` の Assign からキューへ至る経路は未追跡）。
確認すべき反例として、MCU の mute/solo は 128/129 を使う。

## 観測できた範囲の処理境界（brief §16）

```text
メニュー / ツールバー / キーコマンド / AX 操作 / Notes リンク / Remote "/cs/transport/*"
        └──────────────► FUN_008663d4(befehl) ──► コマンドテーブル ──► ハンドラー
コントロールサーフェス（MCU、Remote /cs/、TouchOSC、Lua、Controller Assignments）
        └──► Assign {assignmentClass, trackNo|befehl, trackParam}
                 ├─ class 9  → FUN_008663d4(befehl)            （H2: ID を確認済み）
                 └─ class 5  → チャンネルストリップ・パラメーター （H4）
Logic Remote フェーダーデータ ──► event → FUN_00791330(0x0e, event, object) ──► シーケンサーエンジン
```
