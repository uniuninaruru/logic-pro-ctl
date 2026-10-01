# MACore x86_64 の AppleEvent 調査

言語: [日本語](macore-appleevents.md) · [English](macore-appleevents.en.md)

## 結果

調べた MACore の x86_64 スライスには AppleScript の実行を補助するコードがある。ただし、今回の検索では `aUeV`、`Spt2`、`sPmo`、`sPkc` のバイト列も、完全な整数即値も見つからなかった。実際に見つかった AppleEvent への参照は、`NSAppleScript(iPhotoAdditions)` カテゴリーにたどり着く。このコードは `ascr/psbr` イベントを組み立て、AppleScript オブジェクトで実行する。MACore が Logic の非公開 AppleEvent ハンドラーを登録する証拠ではない。

この MACore だけの解析からは、`sPmo = 6` と `sPkc = -3` の意味は確立できない。別の Logic.framework 内の橋渡しは、[appleevent-command-dispatch.md](appleevent-command-dispatch.md) で追跡している。

## 対象の識別情報と再現

| 項目 | 記録値 |
|---|---|
| 日付 | 2026-10-01 |
| アプリケーションのメタデータ | `CFBundleShortVersionString = 12.3.1`, `CFBundleVersion = 6682`。インストール済みアプリの `Contents/Info.plist` から取得 |
| 元ファイル | `/Applications/Logic Pro Creator Studio.app/Contents/Frameworks/MACore.framework/Versions/A/MACore` |
| 元ファイルのアーキテクチャ | `x86_64 arm64`。`file` と `lipo -info` で確認 |
| 元ファイルの SHA-256 | `76ab2a5f50b3ef120786369b5bf8b53dfc87a3b4107438e0894ab5f9b8095c52` |
| 抽出したスライス | `Research/raw/20261001-083956-macore/MACore.x86_64` |
| スライスのアーキテクチャ | `x86_64`。`file` と `lipo -info` で確認 |
| スライスの SHA-256 | `ed6674bc1e19bc64b53a23bd8a53d097248e3664db16b184342f3897f10edb05` |
| 再現用ツール | `Tools/research-scripts/macore_x86_appleevents.py` |
| 生の記録 | `Research/raw/20261001-083956-macore/manifest.json` と、同じディレクトリー内の完全なツール出力。ディレクトリー名の時刻は UTC |

リポジトリのルートから、その時点で特定したアプリのパスを指定して実行する。

```sh
python3 Tools/research-scripts/macore_x86_appleevents.py \
  --app '/Applications/Logic Pro Creator Studio.app'
```

スクリプトは `lipo -thin x86_64 -output <raw directory>/MACore.x86_64` を使い、その後 `file`、`lipo -info`、`otool -tvV`、`otool -l`、`otool -ov`、`nm -m`、`strings -a` の結果を記録する。アプリケーションバンドルは読むだけである。イベント送信、プロセスへのアタッチ、製品ソースの変更は行わない。スクリプト開発中の 3 回の実行で、同じスライスのハッシュと、FourCC の検索件数ゼロを得た。最終実行では、デコードしたセレクター参照も記録している。

## 観測: 対象の四つの定数

出典: 抽出したスライスのバイト、`manifest.json`、`disassembly.txt`。

FourCC は、4 文字で表す識別子である。次の表では、文字列としての並びと整数として保存されたバイトの並びの両方を確認している。

| FourCC | 整数 | ビッグエンディアンのバイト | リトルエンディアンのバイト | どちらかの並びでの生バイトの一致数 | `otool -tvV` 内の完全な整数・文字列の一致数 |
|---|---|---|---|---:|---:|
| `aUeV` | `0x61556556` | `61 55 65 56` | `56 65 55 61` | 0 | 0 |
| `Spt2` | `0x53707432` | `53 70 74 32` | `32 74 70 53` | 0 | 0 |
| `sPmo` | `0x73506d6f` | `73 50 6d 6f` | `6f 6d 50 73` | 0 | 0 |
| `sPkc` | `0x73506b63` | `73 50 6b 63` | `63 6b 50 73` | 0 | 0 |

逆アセンブル結果の検索には、完全な 16 進値、符号なし 10 進値、FourCC の文字列そのものを含めた。任意の計算で作られる値や、複数に分かれた即値を組み直す処理は行っていない。

## 観測: AppleEvent API とセレクター

出典: `symbols.txt`、`strings.txt`、`objc-metadata.txt`、`disassembly.txt`、`manifest.json` 内のデコード済み selref 記録。

指定した AppleEvent 関連語に一致するインポートシンボルは、Foundation の `_OBJC_CLASS_$_NSAppleEventDescriptor` だけだった。近接するシンボル一覧には、`_OBJC_CLASS_$_NSAppleScript` のインポートもある。

保存したシンボル・文字列・メタデータの出力では、次の名前は見つからなかった。

- `NSAppleEventManager`
- `setEventHandler:andSelector:forEventClass:andEventID:`
- `AEInstallEventHandler`, `AERemoveEventHandler`
- `AEGetParamPtr`, `AEGetParamDesc`, `AEGetAttributePtr`
- `AESend`, `AESendMessage`

インポートされたディスクリプタークラスを参照する逆アセンブル行は 13 行あり、次のセレクター文字列もある。

- `executeAppleEvent:error:`
- `initWithEventClass:eventID:targetDescriptor:returnID:transactionID:`
- `setParamDescriptor:forKeyword:`
- `executeHandlerWithName:andArguments:error:`
- `executeHandlerWithName:inScriptAtURL:withArguments:error:`

### 見つかった参照は AppleScript 呼び出しにたどり着く

`otool -ov` は、カテゴリーの VM アドレス `0x1b8e50` にある `iPhotoAdditions` と、クラス `_OBJC_CLASS_$_NSAppleScript` を記録している。メソッドは次のとおり。

| メソッド | 実装の VM アドレス | 証拠 |
|---|---:|---|
| `-[NSAppleScript(iPhotoAdditions) executeHandlerWithName:andArguments:error:]` | `0x11e450` | インスタンスメソッド名は selref `0x1beec0` を経由して間接的に参照される。デコードした参照先は `0x1746f8` |
| `+[NSAppleScript(iPhotoAdditions) _createScriptAtPath:errorInfo:]` | `0x11e680` | クラスメソッド名は selref `0x1bd510` を経由する。デコードした参照先は `0x170369` |
| `+[NSAppleScript(iPhotoAdditions) executeHandlerWithName:inScriptAtURL:withArguments:error:]` | `0x11e7a0` | クラスメソッド名は selref `0x1beec8` を経由する。デコードした参照先は `0x174723` |

最初のメソッドから、イベントを組み立てる具体的な証拠を得られる。

| 命令アドレス | 観測した操作 |
|---:|---|
| `0x11e4b8` | selref `0x1bd4f0` を通じてセレクター `initWithEventClass:eventID:targetDescriptor:returnID:transactionID:` をロード |
| `0x11e4c9` | `%edx = 0x61736372`。ASCII では `ascr`。レシーバーとセレクターの次に来る最初のメソッド引数 |
| `0x11e4ce` | `%ecx = 0x70736272`。ASCII では `psbr`。その次のメソッド引数 |
| `0x11e4dc` | コンストラクターを呼ぶ |
| `0x11e560` | selref `0x1bd500` を通じて `setParamDescriptor:forKeyword:` をロードし、`%r14` に保持 |
| `0x11e570` | パラメーターのキーワード `%ecx = 0x736e616d`。ASCII では `snam` |
| `0x11e575` | この setter を呼ぶ |
| `0x11e5b4` | パラメーターのキーワード `%ecx = 0x2d2d2d2d`。ASCII では `----` |
| `0x11e5b9` | 変換した引数で同じ setter を呼ぶ |
| `0x11e5d0` | selref `0x1bd508` を通じて `executeAppleEvent:error:` をロード |
| `0x11e5e2` | 保存したメソッドのレシーバーに対して、組み立てたイベントとエラーポインターを渡して呼ぶ |

`0x11e7a0` のクラス補助メソッドでも、`0x11e868` / `0x11e86d` に `ascr/psbr` のコンストラクター即値があり、`0x11e99b` で `executeAppleEvent:error:` を呼ぶ。レシーバーは、この補助メソッドがロードした AppleScript オブジェクトである。これらのメソッド名、イベント構築、呼び出し先のレシーバーは、スクリプト内ハンドラーの呼び出しだという分類を裏付ける。Logic が受信するイベントの登録を確立するものではない。

### 逆アセンブラーの注釈に関する注意

この環境では、`otool -tvV` が誤解を招く Objective-C のコメントを出力する。たとえば、`0x11e5e2` の呼び出しを `setCrcDefined:` と表示する。`0x11e5d0` のセレクターロードは、符号化されたポインター `0x100000001746c8` を含むアドレス `0x1bd508` を参照する。このイメージの `LC_DYLD_CHAINED_FIXUPS` は、`__DATA_CONST` と `__DATA` にポインター形式 6（`DYLD_CHAINED_PTR_64_OFFSET`）を指定する。rebase の参照先をデコードすると `0x1746c8` になり、その文字列は `executeAppleEvent:error:` である。

調査スクリプトは、ロードコマンドを独立して解析し、`__objc_selrefs` を特定し、対応している chained rebase ポインターをデコードし、RIP 相対のセレクターロードを解決する。このため、上のメソッド分類は `otool` のメッセージコメントに依存しない。最終マニフェストには、一致するロードが 6 箇所記録されている。

## 観測: コマンド名とメッセージ名

出典: `symbols.txt`。スクリプトは、大文字・小文字を区別しない `command|dispatch|befehl` に一致したシンボル行を、161 行すべて記録する。

このスライスで利用できるローカルシンボルの例:

| シンボル | VM アドレス |
|---|---:|
| `-[MAMessageDispatcher initWithLabel:]` | `0x91d00` |
| `-[MAMessageDispatcher addHandlerForMessagesOfKind:block:]` | `0x91d90` |
| `-[MAMessageDispatcher addHandlerForMessagesOfKind:songID:block:]` | `0x91db0` |
| `-[MAMessageDispatcher dispatchMessage:]` | `0x91f20` |
| `+[MAMessageDispatcher sharedDispatcher]` | `0x92440` |
| `-[MAAssetManager handleSpecialCommand:withAttribute:forAssetSet:withContext:]` | `0xbf0b0` |

シンボル一覧には、Swift の `ObjcCommandImpl`、`ObjcConditionalCommandImpl`、`NullObjcConditionalCommand`、`Dispatchable` のシンボルも含まれる。これらの名前だけでは、AppleEvent の登録も、トランスポートコマンドの意味も確立できない。この MACore スライスには、名前に `befehl` を含むシンボルは見つからなかった。別途追跡した Logic.framework のコマンドディスパッチの証拠は、既存の [SA-004-command-and-engine-boundaries.md](SA-004-command-and-engine-boundaries.md) を参照。その文書のアドレスは、異なるイメージ・アーキテクチャのものである。

## 限界と、次に仮説を見分ける確認

この結果が示すのは、一つの x86_64 フレームワークスライスで、直接の表現と名前付き API 参照が見つからなかったことだけである。Logic にインターフェースが存在しない証明ではない。間接的なセレクター構築、計算された定数、他のロード済みフレームワーク、標準 Cocoa スクリプティングの代替経路、arm64 イメージにだけ存在するコードは、引き続きあり得る。実行中の Apple Silicon アプリは arm64 コードをロードする。x86_64 スライスは解析の補助であり、単独では実行時の動作を確立しない。

**Hypothesis（仮説）:** 観測した MACore の AppleEvent 参照は、`aUeV/Spt2` の処理元ではなく、AppleScript 呼び出し用の補助コードである。
**確信度:** 追跡したカテゴリーのメソッドについては高い。他のすべての MACore 実行経路については未確立。

次に仮説を見分ける確認: 同じパラメーター・ドキュメント状態で、有効なイベントクラス・イベント ID の組と無効な組を比較し、arm64 アプリケーションのフレームワークで登録・ディスパッチを追跡する。無関係なイベントの組からも共通の `-38` 応答が返るなら、元の組が専用の非公開ハンドラーに届いたという仮説は弱くなる。この文書には、動的なイベント実験の記録はない。
