# 非公開 AppleEvent からトランスポートコマンドへの橋渡し

言語: [日本語](appleevent-command-dispatch.md) · [English](appleevent-command-dispatch.en.md)

## 結果

静的解析の証拠から、`sPmo = 6` を指定した `aUeV/Spt2` が、Logic の既存のコマンドディスパッチャーにつながることを確認した。ディスパッチャーは、コマンド番号に応じて処理を振り分ける共通の入口である。`sPkc` が負の値の場合、ハンドラーは符号を反転し、符号付き 16 ビットのコマンド ID に絞り込んでから実行を依頼する。別途識別した `DfDocument` のトランスポートメソッドも、同じディスパッチャーにコマンド ID 3（再生）、5（停止）、7（録音）を渡している。

したがって、このバイナリでは `sPmo = 6, sPkc = -3` が、ドキュメントの再生コールバックと同じコマンドを選択する。停止・録音に対応する入力は、それぞれ `-5`、`-7` である。これはパラメーター名からの推測ではなく、バイナリから追跡した接続である。実際の実行成功、トランスポート状態の読み戻し、必要なプロジェクト状態は、それぞれ別の証拠で確認する必要がある。この文書では、イベントを送る動的実験は行っていない。

## 証拠の出典と来歴

| 項目 | 記録値 |
|---|---|
| 日付 | 2026-10-01 |
| アプリケーションのバージョン | 12.3.1 (6682)。インストール済みの `Contents/Info.plist` から取得 |
| イメージ | `Contents/Frameworks/Logic.framework/Versions/A/Logic`, arm64 |
| インストール済みイメージの SHA-256 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| Ghidra で解析したコピー | `/Users/nagataharuto/GhidraProjects/logicctl/bin/Logic.arm64` |
| 解析したコピーの SHA-256 | インストール済みイメージの SHA-256 と一致。今回改めて確認 |
| Ghidra の出力 | `Research/raw/ghidra/q-appleevent-spot-handler.c`, `q-cmd.c`, `q-cmdtable.c`, `q-menu.c`, `Logic.arm64.functions.tsv` |
| 独立した命令列のスナップショット | `Research/raw/20261001-084358-command-dispatch/{spot_handler,play,stop,record,dispatcher,command_registration}.asm` |
| 来歴マニフェスト | `Research/raw/20261001-084358-command-dispatch/manifest.json`。実行コマンドと、ソース・出力ファイルの SHA-256 を含む |

メソッド名と関数範囲は、Ghidra の Objective-C 解析と関数一覧の出力に基づく。選択した命令は、一致する解析用コピーに対して Xcode の `llvm-objdump` で改めて逆アセンブルした。以下のアドレスはすべて、このイメージの優先 VM アドレスであり、実行中プロセスの ASLR による移動量（slide）を加えていない。

## 1. 登録されたイベントとモード 6 のハンドラー

出典: `q-appleevent-spot-handler.c`。クエリ対象は `0x590e30` と、その登録側の呼び出し元 `FUN_004f0d24`。登録側には次の呼び出しがある。

```c
_AEInstallEventHandler(0x61556556, 0x53707432, FUN_00590e30, 0, 0);
```

これらの値は `aUeV` と `Spt2` に対応する。`0x590e30` のハンドラーは、パラメーター `0x73506d6f`（`sPmo`）を、ディスクリプター型 `0x6c6f6e67`（`long`）として読み、モードをグローバル `0x2633d60` に保存する。その後、次の分岐を選択する。

```c
if (DAT_02633d60 == 6) {
    /* size/type validation omitted from this excerpt */
    _AEGetParamPtr(event, 0x73506b63, 0x6c6f6e67,
                  &actualType, &keyCommand, size, &actualSize);
    if ((int)keyCommand < 0) {
        command = -(short)keyCommand;
    } else {
        /* bounded positive values use a separate lookup table */
        command = *(short *)(&DAT_01cbeb70 + keyCommand * 2);
    }
    FUN_008663d4((int)command, song, 0, 2, 0);
}
```

これは読みやすく短縮し、変数名を置き換えた抜粋である。サイズ・型の検証はこの抜粋では省略し、範囲内の正の値は別の参照テーブルを使う。逆コンパイラーが付けた厳密な変数型と完全なエラー経路は、生の出力に残してある。以下のアセンブリは、推定された C の型に依存せず、この動作を裏付ける。

| アドレス | 命令・意味 |
|---:|---|
| `0x590e7c` / `0x590e80` | 基準となる定数 `w23 = 0x73506669` を構成 |
| `0x590e84` / `0x590ecc` | `w1 = w23 + 0x706 = 0x73506d6f`（`sPmo`） |
| `0x590ee4` | このキーワードと `long` 型を指定して `AEGetParamPtr` のスタブを呼ぶ |
| `0x591304` | 保存したモードをロード |
| `0x591308` / `0x59130c` | 6 と比較し、一致しなければこの分岐を離れる |
| `0x591340` | `w1 = w23 + 0x4fa = 0x73506b63`（`sPkc`） |
| `0x591354` / `0x591358` | 要求する型 `0x6c6f6e67`（`long`）を `w2` に構成 |
| `0x59135c` | `AEGetParamPtr` を呼び、値を `[sp + 0x30]` に書く |
| `0x591368` / `0x59136c` | パラメーターをロードして符号ビット 31 を検査。負の値なら `0x591578` に分岐 |
| `0x591578` | `neg w8, w8` |
| `0x59157c` | `sxth w0, w8`: 符号付き 16 ビットのコマンド ID |
| `0x591580`–`0x59158c` | 保存した song ポインターを `x1` に渡し、残りの引数に `0, 2, 0` を渡す |
| `0x591590` | `bl 0x8663d4`: コマンドディスパッチャーを呼ぶ |

正のパラメーターをテーブルから変換する経路も、負の値の経路も、`0x59157c` で合流する。ここで扱う小さい値について、負数による指定方法は正確に対応する。ただし、任意の負の 32 ビット値が有効なコマンド ID になるという主張ではない。

スタブの正体は Ghidra のインポート解析から取得した。汎用的な `llvm-objdump` の「最も近いシンボル」の注釈から名前を推定していない。完全な引数・エラーの取り決めは、別文書の [ハンドラー登録解析](appleevent-registration.md) を参照。

## 2. 独立して確認したトランスポートメソッドの呼び出し箇所

出典: `q-cmd.c`、`Logic.arm64.functions.tsv`、今回保存した範囲限定のアセンブリスナップショット。

| Objective-C メソッド | メソッド入口 | コマンド設定 | ディスパッチャー呼び出し | コマンド ID |
|---|---:|---:|---:|---:|
| `-[DfDocument _playCallbackWithWillFreeze:]` | `0x14fba08` | `0x14fbae4` | `0x14fbaf4` | 3 |
| `-[DfDocument stop]` | `0x14fc100` | `0x14fc2f8` | `0x14fc308` | 5 |
| `-[DfDocument recordCallback]` | `0x14fb364` | `0x14fb550` | `0x14fb560` | 7 |

再生:

```asm
0x14fbae0  mov x1, x0
0x14fbae4  mov w0, #3
0x14fbae8  mov w2, #1
0x14fbaec  mov w3, #2
0x14fbaf0  mov x4, #0
0x14fbaf4  bl  0x8663d4
```

停止:

```asm
0x14fc2f4  mov x1, x0
0x14fc2f8  mov w0, #5
0x14fc2fc  mov w2, #1
0x14fc300  mov w3, #2
0x14fc304  mov x4, #0
0x14fc308  bl  0x8663d4
```

録音:

```asm
0x14fb54c  mov x1, x0
0x14fb550  mov w0, #7
0x14fb554  mov w2, #1
0x14fb558  mov w3, #2
0x14fb55c  mov x4, #0
0x14fb560  bl  0x8663d4
```

再生コールバックには、同期トランスポートの準備のためにディスパッチャー呼び出しを延期する分岐がある。上に示した通常の分岐は 3 を使う。録音メソッドにも、`0x14fb408` でコマンド 7 を渡し、このディスパッチャーへ早期に末尾呼び出しする別経路がある。停止メソッドのコマンド 5 呼び出しの前後には、後処理と状態更新がある。したがって、これらの ID はコマンドの選択を識別するものであり、すべてのトランスポートモードの完全な動作を表すものではない。

ドキュメントのコールバックは第 3 引数に 1 を渡し、AppleEvent の分岐は 0 を渡す。ディスパッチャーは、この真偽値が非ゼロの場合、下位の実行関数に渡す値を `0x40000000` に変換する。ドキュメントの UI コールバックと直接の AppleEvent 呼び出しを比較する際、この違いは引き続き考慮する必要がある。

## 3. ディスパッチャーとテーブルの証拠

出典: `q-cmd.c`（`FUN_008663d4`）、`q-cmdtable.c`（`FUN_00865cec`）、`q-menu.c`（`FUN_00864230`）、`dispatcher.asm` / `command_registration.asm`。

ディスパッチャーは、内部コマンドを受ける共通の境界である。`0x86640c`–`0x866414` でコマンド ID の上限を `0x1356`（4950 を含む）に制限し、ID を添字にして、`0x26883b0` にあるポインターテーブルからエントリーをロードする。

```asm
0x86640c  mov w8, #0x1356
0x866410  cmp w22, w8
0x866414  b.hi 0x866464
0x866418  adrp x25, 0x2688000
0x86641c  add x25, x25, #0x3b0
0x866420  ldr x24, [x25, w22, sxtw #3]
```

エントリーのオフセット `+0x18` にある別名ハンドラーを識別し、テーブル `0x1cd1d98` を通じて別名を解決してから、下位の実行関数 `0x865cec` を呼ぶ。下位の実行関数は、ビュー・song のコンテキスト、フォーカスされたビュー、コマンドグループを使う。有効な番号だけでは、そのコマンドを現在のプロジェクト状態で使えるとは限らない。

コマンドテーブル構築関数 `0x864230` は 40 バイトのエントリーを扱う。そのループは `0x8642a4` でエントリーポインターを `0x28` ずつ進める。`0x8642d8` でエントリー先頭の符号付き 16 ビットのコマンドフィールドを読み、`0x8642dc` でエントリーポインターを `0x26883b0[id]` に保存する。関数・引数の組は、エントリーのオフセット `0x18` / `0x20` にある。これは `0x8642b0` の `ldp` と `0x864340` の間接呼び出しから確認できる。これらの命令は、名前だけから推定するのではなく、コマンド ID としての解釈を裏付ける。

## 対象を絞った確認の再現

現在インストールされている実行ファイルを特定し、そのハッシュが解析用コピーと一致することを確認してから、次の既存の Ghidra クエリで関連する関数・呼び出し元の出力を再生成できる。

```sh
Tools/ghidra/query.sh Logic.arm64 q-command-bridge \
  0x590e30 0x8663d4 'callers:FUN_008663d4'
Tools/ghidra/query.sh Logic.arm64 q-command-table \
  0x864230 0x865cec
```

同じ Ghidra プロジェクトに対して、ヘッドレスクエリを同時実行しないこと。独立した、範囲限定のアセンブリ確認は次のとおり。

```sh
xcrun llvm-objdump --arch=arm64 --disassemble \
  --start-address=0x14fba08 --stop-address=0x14fbb10 \
  '/Users/nagataharuto/GhidraProjects/logicctl/bin/Logic.arm64'
```

この範囲指定では通常の逆アセンブルモードを使う。この環境では `--macho` を付けると、`llvm-objdump` が指定した開始・終了アドレスを無視し、text セクション全体を逆アセンブルした。範囲限定スナップショットのマニフェストには、各メソッドで機能したコマンドを記録してある。この照合のために、新たな Ghidra クエリを並列実行してはいない。
