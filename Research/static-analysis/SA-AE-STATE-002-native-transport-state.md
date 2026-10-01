# SA-AE-STATE-002: トランスポート状態の getter、Logic Remote のフィードバック、モード 4 の書き込み

言語: [日本語](SA-AE-STATE-002-native-transport-state.md) · [English](SA-AE-STATE-002-native-transport-state.en.md)

バイナリには、コマンド状態の購読と評価に到達する Logic Remote のピアメッセージ `/keyCommand/keyCommandDictResponse` がある。これは、外部からネイティブな状態を読み戻すための具体的なプロトコル候補である。ただし、初回応答は一部の値しか含まない。コマンド状態がゼロの項目は省略される。信頼できるトランスポート状態の完全な取得も、CLI を独立したピアとして接続することも、まだ検証していない。そのため、現在の製品では AppleEvent による書き込みを MCU で読み戻す方式を維持する必要がある。

AppleEvent のモード 4 は、引き続き読み取り専用のトランスポート状態 API として使うには適さない。補助関数に渡す `(-1, 0)` は、song の既存テンポを選び、一つの通知経路を抑える。しかし、**テンポレコードや song フラグへの書き込みは抑えない。** この結論は、逆コンパイラーの C の型だけからの推定ではなく、ARM64 命令から確認した。

読み方の要点は、内部で状態を計算できることと、接続済みの外部 CLI が正しい状態を受け取れることを分けることである。ここでは前者への経路を確認し、後者の未検証点を記録する。

## 証拠の来歴と調査範囲

| 項目 | 値 |
|---|---|
| 日付 | 2026-10-01, Asia/Tokyo |
| 対象 | Logic Pro Creator Studio 12.3.1 / 6682, ARM64 |
| インストール済みフレームワーク | `/Applications/Logic Pro Creator Studio.app/Contents/Frameworks/Logic.framework/Versions/A/Logic` |
| インポート元 | `/Users/nagataharuto/GhidraProjects/logicctl/bin/Logic.arm64` |
| 二つの Logic 元ファイルの SHA-256。今回の調査で確認 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| インポートされた定数のために確認した、インストール済み MACore の SHA-256 | `76ab2a5f50b3ef120786369b5bf8b53dfc87a3b4107438e0894ab5f9b8095c52` |
| ツール | Ghidra 12.1.4 ヘッドレス、`query.sh` / `XrefDecompile.java`、`TransportStateReport.java`、`nm`、読み取り専用の Mach-O セグメント・chained pointer デコード |
| Ghidra の実行 | 既存の `Logic.arm64`、`-noanalysis -readOnly`。解析の変更を保存していない |
| ローカルの証拠マニフェスト | `Research/raw/ghidra/q-transport-state-002-manifest.json` |
| 整理済みの先行文書 | `appleevent-registration.md`, `appleevent-command-dispatch.md`, `SA-002-control-surface-assign-model.md`, `SA-004-command-and-engine-boundaries.md` |

以下のアドレスは、データアドレスを含めてすべて、この正確なフレームワークで移動量（slide）を加える前のイメージアドレスである。実行時アドレスでも、安定した公開 API でもない。AppleEvent、MIDI メッセージ、リモートピアメッセージ、録音コマンドの送信、実行中プロセスのメモリー読み取り、対象の改変はいずれも行っていない。

今回出力したクエリは、`Research/raw/ghidra/` 内のローカルファイル `q-transport-state-002-{anchors,feedback,entrypoints,routing,key-state}.c` である。`q-transport-state-002-machinecode.txt` には、Ghidra の命令バイト、アドレス、解決した文字列、セレクタースロット、データ参照を保存している。マニフェストには、これらのローカル出力のハッシュを記録した。専用レポートは、固定の基準アドレスを使う前に、インポートした実行ファイルの SHA-256 を確認する。

名前のない補助関数や Objective-C スタブの一部について、逆コンパイラーのプロトタイプは依然として不正確である。特に、実際の ARM64 では呼び出し結果の `x0` を使う箇所でも、C の一時変数が引数をそのまま保持しているように見える場合がある。以下の主要な主張は、命令列と解決したセレクターデータを照合した。

## 1. 内部ドキュメントの getter

`0x014fc9d4` の `DfDocument::isPlaying` は、名前付きの Objective-C セレクター `logicModel`、次に `logicDocument` をたどる。得られたドキュメントポインターは、song ポインターを解決・確認する `FUN_01838684` に渡される。getter が検査するのは、ドキュメントオブジェクト自体ではなく、**返された song のバイト `+0xb9`** である。

```asm
014fca04  mov   x0,x20
014fca08  bl    0x01838684
014fca0c  cbz   x0,0x014fca24
014fca10  ldrb  w8,[x0,#0xb9]
014fca14  cmp   w8,#0
014fca18  cset  w0,ne
```

`0x014fcb04` の `DfDocument::isRecording` も同様に song を解決し、`FUN_01103948(song, 0, 2)` を呼ぶ。その結果が非ゼロなら true を返し、それ以外なら名前付きセレクター `isCellRecording` を末尾呼び出しする。補助関数の `param_3 == 2` 分岐では、song のバイト `+0xbd` を検査し、さらに録音設定のロジックを扱う。**Live Loops・セル録音の経路を残さず、完全な録音状態を一つのバイトだけに還元することはできない。**

以下の名前付き getter は、直接バイトを読む代わりに、コマンド状態の評価を使う。どれもグローバルの状態集計変数 `DAT_026883a0` をリセットし、`FUN_00865cec` を呼び、その集計変数の下位バイトが非ゼロかを読む。

| Getter | 入口 | コマンド ID | 評価関数の第 4 引数 |
|---|---:|---:|---:|
| `DfDocument::isPause` | `0x014fca44` | 4 | `0x40000002` |
| `DfDocument::isForward` | `0x014fcd18` | 11 | `0x40000002` |
| `DfDocument::isRewind` | `0x014fcdd8` | 10 | `0x40000002` |

これらは、Logic のオブジェクト間のつながりの中で使われる内部メソッドである。見つかっただけでは、その値を返す AppleEvent、ソケット、プロセス間メソッド呼び出しが存在するとは確立できない。今回の限定した調査では、これらの getter に到達する外部 CLI の入口は見つからなかった。

## 2. `updateTransportButtonStates` が実際に送るもの

`0x0168f070` の `LgLogicRemoteController::updateTransportButtonStates` は、`DAT_0276de68 -> +0xc0` を読んで現在の song を取得する。得られる結果は二つである。

1. `CLgTransportView::transportStopButtonStateForSong:`（`0x00bdacd0`）の結果を、`setTransportStopButtonState:`（`0x0168fa54`）に渡す。
2. `FUN_01a26938(song)` の結果を、`setTransportClickWhileRecording:`（`0x0168fad4`）に渡す。

機械語からは、補助関数の `x0` の結果が `0x0168f0bc` でセレクターの引数 `x2` に移されることを証明できる。生の C 出力は、この呼び出しで song の値を誤って表示している。セレクタースロットは次のように解決できる。

| スタブ | セレクターポインターのスロット | 確認したセレクター |
|---|---:|---|
| `0x01ba7fa0` | `0x0256bba0` | `setTransportStopButtonState:` |
| `0x01ba7f20` | `0x0256bb80` | `setTransportClickWhileRecording:` |

このメソッドは、完全な `(playing, recording, position)` の状態を直接生成するものではない。停止ボタンの状態は、song のトランスポート状態、Live Loops の活動、設定、位置の比較から計算する整数である。静的に観測した戻り値の範囲は 0、1、2。その値を `isPlaying` の直接的な真偽値の代わりに使えるとは確立していない。

確認した送信メッセージの構築処理:

| メッセージアドレス | 生成元 | 引数の構築方法・出典 | 送信方法 |
|---|---:|---|---|
| `/transport/stopButtonState` | `0x0168fa54` | `NSNumber numberWithInteger:`。controller の `+0x70` にキャッシュし、変化時に送信 | 既定ラッパー `useTCP=1` |
| `/transport/clickWhileRecording` | `0x0168fad4` | `NSNumber numberWithBool:`。controller の `+0x68` にキャッシュし、変化時に送信 | 既定ラッパー `useTCP=1` |
| `/transport/playButtonFlags` | `0x0168f238` | 符号付きバイト `DAT_02765b85` から `NSNumber numberWithChar:` | 既定ラッパー `useTCP=1` |
| `/logicClock/spl` | `0x0168f314` | `FUN_001a388c(song, 0)` から `NSNumber numberWithLongLong:` | 明示的な `useTCP=0` |
| `/logicClock/currentTempo` | `0x0168f314` | `FUN_001a9314(song, position)` から `NSNumber numberWithInt:` | 明示的な `useTCP=0` |
| `/keyCommandStateUpdate` | `0x01683ad8`, `0x0168e1d4`, `0x0168f0dc` | 数値のコマンド ID を数値の状態値に対応付けた辞書 | 既定ラッパー `useTCP=1` |

停止・フラグ・クリック・状態更新の正確な文字列は、Ghidra の CFString データと、その下の C 文字列から解決した。`/logicClock/spl` の位置の単位、`/logicClock/currentTempo` のスケールは、動的に検証していない。`useTCP` はプログラムのセレクター引数の名前である。それだけから生の TCP ポートを推定したり、通常の OSC ソケットを実装したりしてはいけない。

`LgLogicRemoteController::sendMessage:withArgument:`（`0x01683acc`）は、peer に nil、`useTCP=1` を指定して、`sendMessage:withArgument:toPeer:useTCP:` に転送する。後者（`0x016839d4`）は、まず controller の `connected` セレクターを呼ぶ。結果が非ゼロのときだけ、`MAPeerRouter sharedRouter` にメッセージを転送する。解決したセレクタースタブは `0x01b1c480`。したがって、メッセージを作る処理を見つけただけでは、未接続の CLI から利用できることにはならない。

`sendWakeupMessageInSong:activeSongChanged:`（`0x016843b8`）も、wakeup 時にキャッシュ済みの停止ボタン、ヘッダー、クリック、再生フラグの値を送る。ピア接続時のコールバック（`0x016837a0`、ブロック `0x01699828`）は、この wakeup 経路に到達し、プロトコルバージョンを処理する。SA-002 の既存の MACore 解析では、MultipeerConnectivity セッションによる通信と、タグ付き JSON・plist・archive のメッセージフレーミングを確認している。その通信は、今回の作業では実装も実行もしていない。

## 3. 具体的なピアメッセージがコマンド状態の評価に到達する

`0x011df620` の `LgLogicRemoteMessageRouter::messageReceivedAtAddress:withArgument:fromPeer:` は、通常のアプリケーションメッセージをメインキューに送り、`0x011e0118` の `routeMessage:withArgument:` に到達する。そのメソッドの `BgKeyCommandListKey` 分岐が、`keyCommandStateSetup:` を呼ぶ。

インポートされたシンボルの正確な文字列を、インストール済みの MACore で確認した。

| 項目 | アドレス・バイト・値 |
|---|---|
| Logic がインポートしたシンボルのポインター | `0x02282358` |
| MACore の `_BgKeyCommandListKey` スロット | `0x00185130`、バイト `80 2e 19 00 00 00 10 00` |
| MACore の CFString 構造体 | `0x00192e80` |
| MACore の C 文字列 | `0x001514fe`、長さ `0x22` |
| 正確なアドレス | `/keyCommand/keyCommandDictResponse` |
| MACore の chained pointer 形式 | 6（`DYLD_CHAINED_PTR_64_OFFSET`）、`__DATA_CONST` と `__DATA` |

元の名前には `Response` を含むが、Logic はこのメッセージをピアから**受信する**。アドレスは `/keyCommand/list` でも `/keyCommandStateSetup` でもない。`q-transport-state-002-constants.json` に、シンボルの検索結果とデコードした CFString の連鎖を、他の `_BgKeyCommand*` 文字列とともに記録している。

ルーターの ARM64 による比較・呼び出し命令列は次のとおり。

```asm
011e0ff4  adrp  x8,0x2282000
011e0ff8  ldr   x8,[x8,#0x358]        ; imported BgKeyCommandListKey
011e0ffc  ldr   x2,[x8]
011e1004  bl    0x01b51300            ; isEqualToString:
011e1008  cbz   w0,0x011e1158
...
011e1030  mov   x2,x19               ; received argument dictionary
011e1034  bl    0x01b55f80            ; keyCommandStateSetup:
```

`0x01683ad8` の `keyCommandStateSetup:` は次の処理を行う。

- グローバルの購読集合 `DAT_02750110` を置き換える。
- `argument.allKeys` を順に取り出し、`intValue` を適用して、数値 ID を購読する。このメソッドは辞書の値を読まない。
- ID 0 と 5 については、現在の状態の評価を省略する。
- `DAT_02687010` で利用可能と示される ID について、`DAT_026883a0` をリセットし、`FUN_00865cec(commandID, currentSong, 0, 2)` を呼ぶ。
- **初回の状態値が非ゼロのときだけ**、一つの数値 ID・状態値の組を含む `/keyCommandStateUpdate` を送る。

初回のゼロ値の省略は、機械語で確認済みである。

```asm
01683c38  sxth  w0,w23               ; command ID
01683c3c  mov   x2,#0
01683c40  mov   w3,#2
01683c44  bl    0x00865cec
01683c48  ldr   x25,[x22,#0x3a0]     ; DAT_026883a0
01683c4c  mov   w8,w25
01683c50  cbz   x8,0x01683b8c        ; skip sending this entry
```

評価関数の第 4 引数 2 は、状態を扱う経路を選ぶ。これは、名前付きの代替セレクター分岐から裏付けられる。`0x00866178` でフラグを 2 と比較し、`0x00866188` で `befehlStatus:`（`0x01b0f3c0`）を呼ぶ。フラグ 0 なら、代わりに `0x00866198` の `performBefehl:`（`0x01b6bb40`）に到達する。共通の評価関数は、登録済みコマンドハンドラーにも到達し、内部キャッシュ・グローバルを変更する。ID 3 と 7 の個別ハンドラーについて、状態出力の意味や副作用は、まだ完全には監査していない。

`0x0168e1d4` の `keyCommandStateChanged:` は購読集合を確認し、購読済み ID の後続の状態値がゼロでも更新を送る。`0x0168f0dc` の `handleUM_PLAY:` は、定数の数値 **キー 3、値 0** を持つ `/keyCommandStateUpdate` を別途構築する。両方の定数は、`0x0242fd30` と `0x0242fcb8` のデータで確認した。その内部メッセージ条件は、実行時の再生・停止の観測とまだ対応付けていない。

**静的解析で確立した境界:** 受信するピアメッセージが状態評価関数と、送信するピア向け状態辞書に到達する。**実行時には未確立の境界:** 独立して接続した CLI ピアでは、まだこれらのメッセージを受信していない。初回のゼロ値が無言で省略されると、停止状態、コマンドの無効・利用不可、認識されないペイロード、通信失敗を区別できない。したがって、この購読方式で MCU の読み戻しを置き換えるのは早い。

## 4. モード 4 は `(-1, 0)` でも条件付きでテンポを変更する

AppleEvent ハンドラーが行う正確な補助関数呼び出しは、次のとおり。

```asm
005914c0  mov   x0,x19               ; current song
005914c4  mov   x1,#-1
005914c8  mov   w2,#0
005914cc  bl    0x010e3628
```

`FUN_010e3628` では、第 2 引数が負のとき、song の `+0xcc` にある既存の整数を読む（`0x010e376c`）。補助関数は、`FUN_01a14040` が返すテンポイベントリストを調べる。数えたイベントが複数なら、`0x010e374c` で早期に 1 を返す。ゼロ・一つのイベントの分岐では、作成または更新処理を続ける。その分岐には、次の書き込みがある。

| アドレス | 命令・効果 | 条件 |
|---|---|---|
| `0x010e37f4` | 1 との OR 後に `strh w8,[x19,#0xde]` | 正規化・変更の分岐。`ChangeTempo_und` という名前の undo 準備を含む |
| `0x010e3818` | `str w8,[x22,#0x10]` | 既存イベントの分岐。整数を 50,000..9,900,000 に制限 |
| `0x010e3828` | ビット 63 を立ててから `str x8,[x22,#8]` | イベントのマークビットがまだ立っていない場合 |
| `0x010e3834` | `DAT_025e23d8` に 2 を書く | 既存イベントの分岐 |
| `0x010e383c` | `FUN_010e230c(song)` を呼ぶ | 既存イベントの分岐 |
| `0x010e38a0` | `FUN_010e1fd8(song, 0, 0x960000000000, 0, existingValue, 2, flags)` を呼ぶ | 数えたイベントがない場合。作成用の補助関数に、テンポレコードを明示的に構築する処理を含む |

`flags == 0` なら、後続の通知呼び出し `FUN_019c3b50(0x97)` と、`0x010e3840..0x010e3858` の song `+0x758 |= 8` を省略する。しかし、そのフラグは、前述の書き込みや作成用の補助関数呼び出しを抑えない。ハンドラーは、テンポ補助関数の結果を、応答フィールドを生成する前の停止条件として使っていない。

その呼び出し後、`FUN_019ae630(song, 3, 0, 0)` でイベントを取得し、整数 `event +0x18` を読み、`FUN_01079a2c` に渡して `sPso` の文字列を作る（`0x005914d0..0x005914ec`）。この整形関数は、グローバルの表示形式フラグを一時的に変更し、通常の戻り経路で元に戻す。

既存の `sPsr`、`sPfr`、`sPso` についての事実は維持される。`sPsr` は `FUN_003b1c58` から取得し、`sPfr` は song のバイト `+0xc4` を 0..11 に制限した値、`sPso` は整形関数の UTF-8 文字列である。`FUN_003b1c58` には既定の整数 `44100` と、オーディオレートらしい計算がある。**Hypothesis（仮説）、確信度は中程度:** `sPsr` はサンプルレートを表し、他のフィールドは時刻・形式のメタデータを表す。これは動的に確認していない。この分岐からは、再生中・録音中を表す応答フィールドは何も確立できない。

**判断:** モード 4 を、製品の読み取り専用の状態クエリに含めない。今回の調査は、到達する可能性のある変更命令を証明するものである。すべての song、すべてのモード 4 の呼び出しが、ディスク上のプロジェクトを変更するという主張ではない。

## 次の範囲限定の確認目標

次の調査では、**コマンド ID 3（再生）と 7（録音）だけ**について、パケットのスキーマと状態値の意味を示す表を作る。

1. 登録されたハンドラーの `flags == 2` の経路を、正確な `DAT_026883a0` への代入まで追跡し、機械語と照合する。名前付きのドキュメント getter と比較し、Live Loops・セル録音を考慮する。
2. 残る `MAPeerRouter` の接続・プロトコルバージョン経路と、コマンド状態の購読を確立するために必要な一つのピアメッセージを解決する。状態クエリの実験に、actionNum、トランスポートフラグ、位置、任意のコマンドの送信を含めない。
3. `LogicCLI-Test.logicx` だけを使う、別途記録した実験で、専用プロジェクトを停止・再生・再停止させながら、実際に接続されたピアを観測する。ペイロードの正確な型と、完全な初期 false 状態を回収できるかを記録する。MCU のタイムスタンプ・読み戻しと比較する。

成功条件は、外部で受信し、明確に識別できる playing 値が **true と false の両方**で得られること、さらに、有効なピアや購読がない場合のタイムアウト・エラーを定義できることである。一部の応答がないという無言の状態は、検証済みの false 値ではない。録音状態の意味には、その後の別実験が必要。この確認目標は、録音イベントを暗黙に許可するものではない。

モード 4 について次に仮説を見分けるのは、別のテンポマップ実験である。song のテンポイベントがゼロ・一つ・複数の状態を使い分け、テンポ、undo 履歴、プロジェクトの変更済み状態を確認する。これはコマンド状態の購読作業とは独立しており、トランスポート CLI 統合の前提条件ではない。

## 再現

既存の読み取り専用プロジェクトを使い、対象を絞った逆コンパイル結果を改めて取得する。

```bash
bash Tools/ghidra/query.sh Logic.arm64 q-transport-state-002-anchors \
  0x0168f070 0x014fca44 0x014fcd18 0x014fcdd8 0x010e3628
bash Tools/ghidra/query.sh Logic.arm64 q-transport-state-002-key-state \
  refs:0x01b55f80 0x016955bc 0x01a14040 0x019ae76c \
  0x010e1fd8 0x010e230c 0x003b1c58 0x01079a2c refs:0x010e3628 0x00590e30
```

ハッシュ一致を条件とする命令・データレポートは、同じ `-process Logic.arm64 -noanalysis -readOnly` ヘッドレスコマンドの後処理スクリプトとして `TransportStateReport.java` を使い、`Research/raw/ghidra/` 内の出力ファイルを渡して再現できる。Ghidra のプログラムを読むだけであり、Logic にアタッチしたり、Logic を起動したりしない。
