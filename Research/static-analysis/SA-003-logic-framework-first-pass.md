# SA-003: Logic.framework の初回解析 — Assign フィールド、コマンド入口、URL 処理

[日本語](SA-003-logic-framework-first-pass.md) | [English](SA-003-logic-framework-first-pass.en.md)

| 項目 | 内容 |
|---|---|
| 日付 | 2026-10-01 |
| Logic | 12.3.1（6682） |
| バイナリ（arm64） | `Frameworks/Logic.framework/Versions/A/Logic`（40.7 MB、公開シンボル 3 個。Ghidra で ObjC メタデータを復元）、メイン実行ファイルのスタブ、`LogicAppFramework` |
| ツール | Ghidra 12.1.4 headless、解析は約 20 min、ヒープは 10 GB。`Tools/ghidra/analyze.sh` に名前フィルターを指定。対象を絞った追加解析は `Tools/ghidra/query.sh` + `XrefDecompile.java` |
| 出力（ローカルのみ） | `Research/raw/ghidra/Logic.arm64.{functions.tsv,decompiled.c}`、`q-*.c` |

## 0. コードがある場所

- メイン実行ファイル `Logic Pro Creator Studio`: 29 関数。
  `NSApplicationMain` とアプリ生成の準備のみで、主要な処理はない。
- `LogicAppFramework`: 80 関数。Swift の `AppFactory` による
  ドキュメントのライフサイクル処理のみ。
- アプリ本体の処理は `Logic.framework` と `MA*.framework` にある。

フィルターを使った逆コンパイルで得たクラスとメソッド数は、
`LgLogicRemoteController` 275、`WrappedAssign` 124、
`ControllerAssignmentsController` 100、`LgTronMessageRouter` 51、
`CSLearnRecentAssignmentsImpl` 42、`LiveLoopsControlSurfaceManager` 21、
`CSControlSurfaceControllerImpl` 20、`KeyCommandsController` 11、
`RemoteCommandSupport` 10。

## 1. Assign のフィールド対応 — WrappedAssign の getter から確認

`WrappedAssign` は、Controller Assignments で使う C++ の Assign を
ObjC で包んだもの。`pvVar1 = [self assign]` により取得した
シリアライズ済み Assign の、次のオフセットを読む。

| Getter | オフセット / 型 |
|---|---|
| `assignmentClass` | +0x3a u32 |
| `trackNo` | +0x3e u16 & 0xfff |
| `befehl`（ドイツ語で「コマンド」） | +0x3e s16 |
| `key`、`mode` | +0x3e（s8 / s16） |
| `trackParam`、`audioTrackParam`、`groupParam` | +0x40 s32 |
| `bankType` | +0x40 u8 |
| `valueMode` | +0x4b & 7 |
| `feedbackType` | +0x46 & 0x7f |

SA-002 の対応を更新できる。「kind」= **assignmentClass**、
「sub」= class 5 の **trackNo** または class 9 の **befehl**（コマンド）、
「param」= **trackParam**。確信度は高（getter のコードが根拠）。

その他の WrappedAssign プロパティ名にも意味が現れている。
`globalObj`、`clockPart`、`markerIndex`、`alertButton`、`trackObj`、
`viewFilter`、`groupObj`、`csGroupObj`、`valueFormat`、`multiply`、
`min/maxMIDIValue`、`resolution`、`MIDIInput` / `MIDIOutput`、
`isPinnedToTrack`、`paramMin/Max`。

## 2. 番号によるコマンド実行（befehl）

- `RemoteCommandSupport -doLogicAction:(short)` は
  `FUN_008663d4(befehl, currentSong, 0, 2, 0)` を呼ぶ。
- `-parseCommandQuery:` はクエリ文字列を分割し、
  `befehlid=<n>`（doLogicAction を実行）、
  `remoteid=<n>`（n が 1…14 なら小さなテーブル `DAT_01cbeb70` を経て doLogicAction）、
  `openhelpvieweranchor=<a>` を扱う。
- 呼び出し元は `CLgNotesFocusView -textView:clickedOnLink:atIndex:` のみ。
  Logic の Notes 内にある `file://…/logic?<query>` リンクをクリックしたときに呼ばれる。
  GUI のクリックを経由せずに外部から到達する経路はない。

**Hypothesis（仮説）:** `FUN_008663d4` は、キーコマンド、Notes のリンク、
Assign class 9 で共有するキーコマンド・ディスパッチャー
（Logic Remote の `/cs/transport/play` は befehl 3）。
確信度は中。次は `FUN_008663d4` の逆コンパイルと `/keyCommand/*` の通信記録。

## 3. URL スキーム（Info.plist と `CLgAppManager -handleGetURLEvent:withReplyEvent:`）

- `applelogicpro://<path>?alternativeIndex=<n>&selectBackup=<bool>` は、
  `openDocumentAtURL:withAlternativeIndex:` で `<path>` のプロジェクトを開く。
  対象のパスが存在する必要がある。
- `logicpro:` は別のクラスへ渡す
  （`FUN_01b3f480(0x25bc080, url)`。まだ処理内容を読んでいない）。
- コマンドやミキサーを操作する URL 経路は見つかっていない。

## 4. キーコマンド名のテーブル（未解決）

`__DATA_CONST` の 0x23a8018…0x23abfd8 に、511 要素 × 32 bytes のテーブルがある。
各要素は `{name ptr (chained fixup), length, 0x8020000000001ce6, 0x7c8}`。
例は "Cycle Mode" [132]、"Clear/Recall Solo" [139]、"Mute off for all" [140]。

Logic Remote では solo/mute reset に befehl 1040/1041 を使うため、
この区間では index + 901 が一致する。しかし "Cycle Mode" の index + 901 は、
Remote の cycle である 15 と一致しない。コードからの参照は見つかっておらず、
アドレスは実行時に計算される。ID と名前の対応は**不明**。
次は `/keyCommand/commandsQuery` → `commandsResponse` から動的に取得する。
