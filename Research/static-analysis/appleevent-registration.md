# SA-AE-REG-001: arm64 の AppleEvent 登録と Spt2 ハンドラー

言語: [日本語](appleevent-registration.md) · [English](appleevent-registration.en.md)

| 項目 | 値 |
|---|---|
| 日付 | 2026-10-01, Asia/Tokyo |
| 調査対象アプリ | `/Applications/Logic Pro Creator Studio.app` |
| Bundle ID | `com.apple.mobilelogic`（このアプリの plist から取得） |
| バージョン・ビルド | 12.3.1 / 6682 |
| バイナリ | `Contents/Frameworks/Logic.framework/Versions/A/Logic` |
| アーキテクチャ | arm64 |
| UUID | `641ea797-e5a3-3ff1-8188-b36067cf8361` |
| SHA-256 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| ツール | macOS の `nm`、`otool`、Python 標準ライブラリ、Ghidra 12.1.4 ヘッドレス |
| 実験の種類 | 静的解析、読み取り専用。この調査では AppleEvent を送信していない |
| 生の証拠 | `Research/raw/2026-10-01-appleevent-registration/`。対象を絞った Ghidra クエリは `Research/raw/ghidra/q-appleevent-*.c` にも保存 |

## 結果

**機械語から確認済み:** このビルドは、アプリケーション側の `aUeV/Spt2` ハンドラーを明示的に登録する。ハンドラーとは、受信したイベントを処理する関数である。そのモード 6 は `sPkc` を解析し、Logic の他のコマンド経路も使う共通のディスパッチャーに入る。したがって、このイベントが認識されるという結論は、スクリプトの成功応答や、未知のイベントを一括処理する汎用ハンドラーからの推定ではない。

**範囲を限定して確認した「見つからなかった」という結果:** `Logic.framework` の arm64 から、C による直接の登録呼び出しを 1 箇所、Objective-C による登録の末尾呼び出しを 1 箇所復元した。それぞれ `aUeV/Spt2` と `GURL/GURL` を登録しており、どちらも `****` を使っていない。ただし、間接的な登録、フレームワークの既定動作、実行時に別の場所で登録されるハンドラーまで否定するものではない。

## 実験記録と再現

今回の調査で行った一つの操作: arm64 の逆アセンブル結果から、インポートされた `AEInstallEventHandler` と、既知の `setEventHandler:andSelector:forEventClass:andEventID:` スタブへの直接呼び出しをすべて復元し、その後、登録されたハンドラーとコマンドテーブルのバイトを調べた。

`Tools/research-scripts/appleevent_handlers.py` は、アプリのメイン実行ファイル、バンドル直下のフレームワークと dylib を走査する（今回の実行では 68 バイナリ）。各バイナリのインポート状況を記録し、arm64 の逆アセンブル結果全体をローカルに保存し、登録箇所の前後を抜き出す。また、モード 6 の正の値に対応するコマンドテーブルを Mach-O から直接デコードする。アプリ名や Bundle ID を固定するのではなく、アプリのパスを引数として渡す必要がある。

```sh
python3 Tools/research-scripts/appleevent_handlers.py \
  '/Applications/Logic Pro Creator Studio.app' \
  --out Research/raw/2026-10-01-appleevent-registration
```

逆アセンブル結果がすでにある場合は、`--reuse-disassembly Research/raw/2026-10-01-appleevent-registration/Logic.arm64.disassembly.txt` を追加する。スクリプト内の基準アドレスは、今回調べたビルドを対象としている。他のバージョンでは再特定する必要があり、ABI の安定性を保証するものではない。

既存の Ghidra 解析済みプログラムは、`logicctl` プロジェクト内の `Logic.arm64` である。次の読み取り専用の対象限定クエリから、元の関数・相互参照の証拠を取得した。

```sh
Tools/ghidra/query.sh Logic.arm64 q-appleevent-registration refs:0x1aeca40
Tools/ghidra/query.sh Logic.arm64 q-appleevent-spot-handler 0x590e30 refs:0x590e30
Tools/ghidra/query.sh Logic.arm64 q-appleevent-selectors \
  s:setEventHandler:andSelector:forEventClass:andEventID:
Tools/ghidra/query.sh Logic.arm64 q-appleevent-objc-registration \
  refs:0x1b8ed20 0x10e3628 0x19ae630 0x1079a2c
Tools/ghidra/query.sh Logic.arm64 q-appleevent-owner-provenance \
  0x168bba4 0x146f914 0xdb6f88 0x579e1c 0x57badc
```

`Tools/ghidra/AppleEventHandlerReport.java` は、SDK に基づく関数プロトタイプを一時的に適用し、ハンドラー・登録処理・ディスパッチャーを出力し、現在の owner グローバルへの相互参照を記録する。`-readOnly` を付けて実行する。ヘッドレスログには `Discarding changes to ... /Logic.arm64` と明記される。

メモリー内の型を変更する前に、この後処理スクリプトは、Ghidra のプログラム名と保存された実行ファイルの SHA-256 が調査対象イメージと一致することを確認する。ラッパーも、インストール済みバイナリと独立した解析用コピーを確認する。データベース側の確認により、同じプロジェクト内の別プログラムがファイル側の確認だけを通過することを防ぐ。

```sh
JAVA_HOME='/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home' \
GHIDRA_HEADLESS_MAXMEM=10G \
/opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless \
  '/Users/nagataharuto/GhidraProjects/logicctl' logicctl \
  -process Logic.arm64 -noanalysis -readOnly \
  -scriptPath '/Users/nagataharuto/logicpro cli/Tools/ghidra' \
  -postScript AppleEventHandlerReport.java \
  '/Users/nagataharuto/logicpro cli/Research/raw/2026-10-01-appleevent-registration'
```

SDK の出典は、インストール済み macOS SDK 内の `CoreServices.framework/Frameworks/AE.framework/Headers/AppleEvents.h`、`AEDataModel.h`、`usr/include/MacTypes.h`。`OSErr` は符号付き 16 ビット、`Size` は符号付き 64 ビットの `long`、LP64 での `SRefCon` は `void *` である。`AEDesc` は SDK の 2 バイト単位のパッキングに従い、4 バイトの型と 8 バイトのハンドルを持つ。インポートされたハンドラーの戻り値は `OSErr` であり、呼び出し元は 32 ビットの `w0` レジスター全体を検査する。

二つの逆コンパイル出力は、意図的に層を区別している。

- `typed-decompiled.c` は、SDK と正確に同じサイズの `OSErr` を API の戻り値宣言に使う。
- `abi-normalized-decompiled.c` は、インポートされた API の戻り値レジスターを 32 ビットの `OSErr_W0_register` としてモデル化する。Ghidra の上位ビット不明・`CONCAT` に由来する見かけ上の表現を避けるためである。アプリケーションのハンドラー自体は、引き続き SDK の `OSErr` を返す。これは出力を読みやすくする補助であり、SDK インターフェースの再定義ではない。

無関係な C++・Objective-C の関数シグネチャには、未解決のものがある。その経路に現れる生の逆コンパイラーのキャストやポインター名は、実際のソース型を示す証拠にはならない。以下の主張は、整理した疑似コードとアセンブリに基づく。

## 登録箇所

| 仕組み | 呼び出し箇所 | クラス / ID | ハンドラー | 追加引数 |
|---|---|---|---|---|
| `AEInstallEventHandler` | `FUN_004f0d24` 内の `0x004f11fc` | `aUeV` / `Spt2` | `0x00590e30`, `FUN_00590e30` | refcon `0`、システムハンドラー指定は false |
| `NSAppleEventManager setEventHandler:andSelector:forEventClass:andEventID:` | `CLgAppManager::addURLhandler`（`0x017ccab8`）内の末尾分岐 `0x017ccb08` | `GURL` / `GURL` | レシーバーは app manager、セレクターは `handleGetURLEvent:withReplyEvent:` | `FeatureAvailable(4)` の条件付き |

非公開イベントの登録は、起動進行状況の文字列 `InitializingSpotRegionHandlers` の直後、`InitializingSequencerandAudioEngines` の前に行われる。この箇所では `AEInstallEventHandler` の戻りステータスを確認しない。静的解析で登録しようとする処理が見つかっただけでは、実行時の登録成功は証明できない。

正確なインポートスタブは `0x01aeca40`。ハンドラーのアドレスは `adrp x2, 0x590000; add x2, x2, #0xe30` から得られる。クラス・ID の即値は `0x61556556` と `0x53707432` であり、リソースの文字列走査から見つけた値ではない。

Objective-C のセレクター文字列は `0x01f59e5a` にあり、スタブ `0x01b8ed20` がセレクターポインター `0x02565700` を通じて参照する。このスタブには、復元できた呼び出し元が一つあり、それが `GURL/GURL` の末尾分岐である。レシーバーとセレクターは別の引数であり、`x2` は app manager、`x3` は `handleGetURLEvent:withReplyEvent:`、`w4` / `w5` はイベントクラス・ID である。

## ハンドラー入口と -38 の発生元

入口 `0x00590e30` では、まずグローバル `0x0276de68` にあるポインターを読み、次にそのオフセット `+0xc0` にあるポインターを読む。どちらかが null なら `0x00591054` に分岐し、`w22 = 0xffda` を設定する。終了処理の `0x00591070` は、その下位 16 ビットを符号拡張して **-38** を返す。

二つ目のポインターが何を表すかは、名前付きの Objective-C getter から独立して裏付けられる。

- `LgLogicRemoteController::song`, `0x0168bba4`: `global_0276de68 ? *(void **)(global_0276de68 + 0xc0) : NULL` を返す。
- `CLgSelectionBasedAudioViewController::currentSong`, `0x0146f914`: 同じポインターをロードして返す。
- `PrefsGlobalView::song`, `0x00db6f88`: 対象を絞った逆コンパイル結果でも同じ処理。

したがって、**このハンドラーの -38 は、パラメーターを読む前の「現在の song を利用できない」という失敗である。** パラメーター値 `sPkc = -38` とは別物である。現在の song の検査に成功した後なら、`sPkc = -38` はコマンド 38 に変換される。

owner グローバルは変更され得る。`0x00579e1c` の `FUN_00579e1c` は、引数がゼロならグローバルをクリアし、それ以外なら候補をポインターベクター `0x02633be0..0x02633be8` と照合してから選択する。`FUN_0057badc` は、以前のグローバルを出力ポインター経由で保存し、検証済みの候補を一時的に選択する。これは、現在選択されている owner の状態を示す追加の来歴である。owner の元の C++ クラス名は、依然として不明。グローバルへの静的相互参照の完全な一覧は、生の `owner-state-xrefs.tsv` に記録してある。

## 必須のモードパラメーター

現在の song を確認した後、ハンドラーは次を呼ぶ。

```c
AESizeOfParam(event, 'sPmo', &actualType, &size);
// require actualType == 'long'
AEGetParamPtr(event, 'sPmo', 'long', &actualType,
              &global_02633d60, size, &size);
```

静的な型比較は正確に `'long'`（`0x6c6f6e67`）との一致を要求する。任意のディスクリプター型を暗黙に変換して受け付ける要求ではない。`AESizeOfParam` が失敗すれば、そのエラーを返す。成功しても型が違えば、ディスパッチせずに、その成功ステータス（ゼロ）を直ちに返す。モード 6 の `sPkc` パラメーターにも同じパターンがある。したがって、AppleEvent の応答が成功しただけでは、コマンドが実行されたと判断できない。

パーサーは `AESizeOfParam` が返したサイズを、そのまま次の処理に渡す。対応する機械語の範囲には、独立した `size == 4` の検査は見つからなかった。通常の `'long'` 入力は、4 バイトの符号付き整数である。不正な形式のペイロードは試していないため、呼び出し側は標準の 4 バイトのディスクリプターを生成するべきである。

## モード 6: 正確なコマンド変換

`sPmo = 6` は `0x00591308` で分岐する。`sPkc` の型が正確に `'long'` であることを要求し、4 バイトの符号付き値を読む。`0x0059136c` の分岐はビット 31 を検査する。

負の値では、`neg w8, w8`（`0x00591578`）と `sxth w0, w8`（`0x0059157c`）により、32 ビットで符号反転した値の下位 16 ビットを、符号付きとして取り出す。したがって、`-3` はコマンド 3、`-5` はコマンド 5、`-38` はコマンド 38 をディスパッチする。通常の 16 ビットのコマンド範囲を超える値は切り詰められる。たとえば `-65539` もコマンド 3 に変換される。これは静的に求めた算術結果であり、動的テストを勧めるものではない。

非負の `sPkc` では、命令列 `sub w9, w8, #15; cmn w9, #14; b.lo no_op` が、正確に 1..14 の値だけを受け付ける。ハンドラーは対応する符号なし halfword（16 ビット）をロードし、同じ `sxth` を使う。ゼロと 15 以上の値は、何もせず成功を返す。

`0x01cbeb70` のテーブルには、リトルエンディアンの符号付き 16 ビット値が 15 個ある。

| sPkc の添字 | ディスパッチされるコマンド |
|---:|---:|
| 0 | 受け付けない。保存されているテーブル値は 0 |
| 1 | 5 |
| 2 | 535 |
| 3 | 10 |
| 4 | 11 |
| 5 | 12 |
| 6 | 13 |
| 7 | 7 |
| 8 | 1272 |
| 9 | 1273 |
| 10 | 4 |
| 11 | 3 |
| 12 | 14 |
| 13 | 754 |
| 14 | 753 |

バイト列:
`0000050017020a000b000c000d000700f804f904040003000e00f202f102`。
コマンド名と動的な動作は、別のディスパッチャー解析・実験記録で扱う。このテーブル自体が証明するのは、数値の変換だけである。

`0x00591590` の呼び出しは次のとおり。

```c
FUN_008663d4(command, currentSong, 0, 2, 0);
return 0;
```

ディスパッチャーの結果は無視され、呼び出し後にハンドラーはゼロを返す。`FUN_008663d4` はテーブル `0x026883b0` を通じてコマンドエントリーを参照し、範囲 `< 0x1357` を確認し、特別な間接コマンドエントリーを解決し、コマンド発生元の状態を 2 に設定し、最終的に `FUN_00865cec` を呼ぶ。コマンド失敗経路は `NSBeep` を呼び、`Commandnotavailablebecause___` を表示し得る。つまり、イベントの認識、ペイロードの受理、要求したコマンドの完了は、それぞれ別の事実である。コマンドテーブル・ハンドラーの解析は、[SA-004-command-and-engine-boundaries.md](SA-004-command-and-engine-boundaries.md) と [appleevent-command-dispatch.md](appleevent-command-dispatch.md) を参照。

## その他の確認済み分岐とフィールド

| モード | 追加入力・分岐 | 確認した呼び出し・応答フィールド |
|---:|---|---|
| 4 | `sPkc` を読まない。応答ディスクリプターは `'null'` と異なる必要がある | `sPsr:long` 4 バイト、`sPfr:long` 4 バイト、`sPso:utf8` 可変長バイト |
| 7 | `sPpn` が正確に `utxt` または `utf8` | `FUN_017af4ac(currentSong, NSString)` |
| 8 | 同じテキスト解析 | `FUN_017b1c9c` |
| 9 | 同じテキスト解析 | `FUN_017afd88` |
| 10 | 同じテキスト解析 | `FUN_017b1e8c` |
| 11 | 同じテキスト解析 | `FUN_017b174c` |
| 12 | 同じテキスト解析 | `FUN_017b201c` |
| 13 | テキストパラメーターを読まない | `FUN_017b22f8(currentSong)` |
| 14 | 同じテキスト解析 | `FUN_017b19c0` |
| その他すべてのモード | ファイル・リージョン分岐 | `sPfi` が正確に `bmrk`、`furl`、`fsrf` のいずれか。任意の `sPve`、`sPtn`、`sPss`、`sPst`、`sPsp` は正確に `long`。必須の `sPrg` は正確に `utxt` または `utf8`。その後 `FUN_00591de0` |

テキストは、UTF-16 の `CFStringCreateWithCharacters` または UTF-8 の `CFStringCreateWithBytes` を通じて NSString に変換される。**モード 7・8・9・10・11・12・14** の共通復帰経路では、ハンドラーは null でない応答に `sPer:long = 0` を入れる。処理関数の戻り値を、信頼できる操作ステータスとして伝えてはいない。モード 13 とファイル・リージョン分岐は、helper 呼び出し後にハンドラーの成功値 0 を返す別経路で、`sPer` を追加しない。テキスト・ファイルのディスクリプター型が違う場合も、何もせず成功を返すことがある。応答と helper 内部の処理は、[テキスト操作の解析](SA-AE-MODES-001-text-operations.md)・[ファイルとリージョンの解析](SA-AE-FILE-001-file-region.md)に整理した。

モード 4 では、`sPsr` は `FUN_003b1c58(currentSong)` の戻り値であり、`sPfr` は currentSong の `+0xc4` にある符号付きバイトを 0..11 に制限した値である。`sPso` は、`FUN_01079a2c` が返した文字列の UTF-8 表現。バイナリからは、この対応関係を証明できる。省略形のキーが人間にとって何を意味するかは、まだ動的に検証していない。

**モード 4 が読み取り専用だとは確立していない。** `sPso` を作る前に、`FUN_010e3628(currentSong, -1, 0)` を呼ぶ。対象を絞った逆コンパイル結果には、テンポ状態の作成・正規化、現在の song の状態への書き込み、`ChangeTempo_und` というラベルが含まれる。専用の実験で動作を解決するまでは、この分岐を状態変更の可能性があるものとして扱う必要がある。

他の分岐にも、明示的なファイル書き込みや、インポート・エクスポートらしいコードがある。モード 8 は `writeToFile:atomically:encoding:error:` を呼び、モード 9 はメタデータのプロパティリスト（`FileChecks`）を更新し、モード 11 は MIDI ファイル型を確認して解析済みデータをインポートし、モード 12 は一時ファイルと `.aac` のパスを作る。これらは静的な観測であり、完全に検証された操作定義ではない。この調査では、これらのモードを実際のアプリに送って試していない。

## 残る不明点

- owner・current-song の元の C++ 型名。上で述べたセレクターで裏付けられるオフセットは、すべて型名なしで証明している。
- コマンド以外のモードの入力・応答が持つ意味、対応する値、単位。
- 間接登録、またはシステム・フレームワークが登録するワイルドカードハンドラーの有無。
- 実行時のハンドラーテーブルの内容と、確認されていない登録の戻りステータス。
- 専用テストプロジェクトで別途記録した実験以外のコマンドについて、信頼できる操作成功・読み戻し。

この静的解析では、`Sources/` の変更、システム保護の無効化、アプリケーションの改変、実際の音楽制作プロジェクトの使用はいずれも行っていない。
