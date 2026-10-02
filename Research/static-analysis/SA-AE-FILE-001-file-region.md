# SA-AE-FILE-001: AppleEvent のファイル・リージョン分岐

[日本語](SA-AE-FILE-001-file-region.md) · [English](SA-AE-FILE-001-file-region.en.md)

| 項目 | 内容 |
|---|---|
| 日付 | 2026-10-02 |
| 対象 | Logic Pro Creator Studio 12.3.1 / build 6682、`Logic.framework` ARM64 |
| 基準SHA-256 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| 外部入口 | `aUeV/Spt2` → `FUN_00590e30` → `FUN_00591de0` |
| 方法 | 既存Ghidra programのread-only/noanalysis出力を読む静的調査。Logicへのイベント送信・接続・実機操作なし |
| ローカル根拠 | `Research/raw/ghidra/q-appleevent-file-region-001.c`、`q-appleevent-file-units-001.c`、`q-appleevent-object-resolvers-001.c`、`q-appleevent-modes-001-machinecode.txt`、`q-appleevent-modes-callees-001-machinecode.txt` |
| 型の扱い | Cの推定prototypeは仕様として採用しない。以下の「確認」はアドレス付きARM64命令とAPI参照による静的確認。実機動作・単位の意味は別途検証が必要 |

アドレスはこのビルドのslide前のイメージアドレスです。登録・currentSongの前提は[既存の登録解析](appleevent-registration.md)を参照してください。この分岐を一般的なregion編集APIや読み取りAPIとして公開できる段階ではありません。

## 1. 入口と型チェック

callerはmode 4、6、7〜14を別処理へ振り分け、それ以外を`sPfi`の解析へ渡します。比較は`0x00590ef8..0x00590f6c`、`0x005911c0..0x005911cc`、`0x00591300..0x00591398`。ファイル入力の分岐は`0x005913c0..0x00591458`です。

| field | 正確なdescriptor型 | 既定値・保存先 | 機械語で確認した経路 |
|---|---|---|---|
| `sPfi` | `bmrk` / `furl` / `fsrf` | `CFileRef` at `0x02633cf0` | 型比較`0x005913e0..0x00591410`。`furl`のCFileRef化`0x00591598..0x005915f4`。bookmark解決`0x005915fc..0x00591690`。FSRef設定`0x00591414..0x00591454` |
| `sPve` | optional `long` | 1、`0x02633ce0`の下位16 bits | `0x00591698..0x005916fc`。入力の下位16 bitsを`strh`で保存 |
| `sPtn` | optional `long` | 1、u32 at `0x02633d5c` | `0x00591704..0x00591764` |
| `sPss` | optional `long` | 0、u32 at `0x02633d64` | `0x0059176c..0x005917c8`。helperでは`ldrsw`による符号付き読み出し |
| `sPst` | optional `long` | 0、u32 at `0x02633e68` | `0x005917d0..0x0059182c` |
| `sPsp` | optional `long` | 0、u32 at `0x02633e6c` | `0x00591834..0x00591890` |
| `sPrg` | `utxt` / `utf8` | Pascal文字列buffer at `0x02633d68`、capacity `0x100` | 型比較`0x00591894..0x005918d0`。UTF-8変換`0x005918d4..0x00591934`。UTF-16変換`0x005919dc..0x00591a14`と`0x00591ab4..0x00591ad0`。Pascal化`0x00591ad4..0x00591af4` |

optional fieldは、`AESizeOfParam`が成功し、型が正確に`long`の場合だけ`AEGetParamPtr`で取得します。省略・型違いでは既定値を保つ分岐です。取得に失敗すると、callerは取得エラーを戻す経路へ進みます。型確認は、サイズ・値域・安全な実行の完全な検証ではありません。

`sPrg`はこの入口で必要ですが、**既存regionの名前を検索するselectorとは確認していません**。helperの非MIDI分岐では、ファイル側の構造に名前を書き込みます。UTF-16/UTF-8で作ったCFStringは、`CFStringGetSystemEncoding`の符号化でPascal文字列へ変換されます。`CFStringGetPascalString`の戻り値は調べずに続行します（`0x00591adc..0x00591b10`）。したがって任意のUnicode名が完全に保持されるとも、変換失敗時の内容が正しいとも言えません。

`sPve`の保存は確認できますが、helper内に保存先の直接読み出しは見つかっていません。略称からversionなどの意味を確定しません。

## 2. 対象の決め方

helperは現在のsongと補助関数が選んだ構造を使います。`0x00591e18..0x00591e40`で`FUN_004f1cf4(0x7049)`を呼び、返された構造の`+0x70 == 0x7049`なら`+0x74`、そうでなければsongの`+0x10`から32-bitの対象値を読みます。この構造の正式な型は未確定です。UI/focusに関係するという解釈はHypothesis、確信度: 中です。

- `sPtn <= 0`は1へ変更する（`0x00591e44..0x00591e64`）。
- songの識別値`0xabc04723` / `0xabc04713`を確認する（`0x00591e68..0x00591e88`）。
- 対象値`0x7ffffff8` / `0x7ffffffc`には特別な解決経路がある。その他は上位bitと下位2bitsを拒否し、`id >> 2`でpointer配列を引く（`0x00591e8c..0x00591f24`）。
- 解決した構造の`+0x330..+0x338`はstride `0x50`の配列。型byteなどを使って数を数え、`FUN_019fb130(entry, owner)`の結果を使って、入力ordinalを別の1-based indexへ変換する（`0x00591f34..0x00592170`）。最終値は16-bitとして扱い、bit15が立つ場合は処理を終了する（`0x00592174..0x0059217c`、`0x005923a8`）。

**確認した境界:** `sPtn`は単純にMCUのmixer位置やstable track IDとして使われる値ではありません。入力ordinalが現在の対象配列とpredicateによって変換され、mode 2ではsong/選択由来の値で上書きされる場合があります。

**追加の機械語確認:** `FUN_019fb130`は純粋な読み取りpredicateではありません。次の対象候補と現在候補の`+0x12` byteの差が2以上の経路では、`0x019fb294`の`strb w9,[x8,#0x12]`が現在候補へ書き込みます（比較・store `0x019fb280..0x019fb2a0`）。この関数はhelperの対象決定中に呼ばれるため、fileの取込より前に内部metadataが変わる可能性があります。disk上のdirty状態との対応は未検証です。

**Hypothesis、確信度: 中:** この配列とpredicateは表示上のtrack階層・可視性・畳み込みに関係します。type byte、`+0x12`、flag `+0x14`の意味は未確定です。

小resolver `FUN_001a1dcc`も、song/対象値/1-basedの16-bit indexから同じstride `0x50`の候補を返す経路を持ちます（callee機械語`0x001a1dcc..0x001a1ef0`、C出力`q-appleevent-object-resolvers-001.c`）。これは対象の種類の推測を助けますが、stable track IDやmixer位置の一致を示しません。

## 3. modeごとの位置の選び方

下の表は**分岐とデータの出所**であり、実機で確定したmode名ではありません。

| `sPmo` | 機械語で確認した処理 | アドレス |
|---:|---|---|
| 1 | `FUN_001a388c(song, 0)`の64-bit返値を使う | `0x00592220..0x00592234` |
| 2 | song `+0x38 == -1`なら上記getterを使い、補助関数由来の構造/songの比較によってtrack候補を選ぶ。それ以外はsong `+0x28`と`+0x22`を使う。track候補0/`0xffff`は`0xffff`になる | `0x005921a8..0x005921d0`、`0x00592238..0x00592274` |
| 3 | `sPss`を符号付き32-bitとして読み、`FUN_007ac29c(song, anchor, input, -1)`で変換。逆方向らしい`FUN_007abc8c`で比較し、必要なら位置を`0x100000000`増やして再計算。差分の正値を32-bit補正値として保存 | `0x005921d4..0x005921dc`、`0x00592328..0x00592388` |
| 5 | `FUN_001a924c`の返した構造、song `+0xc4`により0..11へ限定したformat index、table `0x01d58bd0`、global `0x025ecad8`、定数1001を使ってoffsetを計算し、`sPss`から引く。負値・上限超過なら終了。その後mode 3と同じ変換へ進む | `0x005921e0..0x00592324` |
| その他 | 上記の特殊処理を選ばず、既定anchorからファイル分類・取込方向へ進む | `0x00592188..0x005921e4` → `0x00592398` |

anchorは`0x960000000000`、上限は`0x3ffff0ff00000000`。mode 1/2/3/5の対象位置は下限・上限を適用します（`0x0059238c..0x005923a4`）。非MIDIの配置候補ではanchorを引いた位置を使います（`0x005927dc..0x005927e4`、`0x00592858..0x00592860`）。これは時間の符号化・biasの存在を示しますが、tick/beat/sample単位を確定するものではありません。

**Hypothesis、確信度: 中:** `sPss`はsample/time-domainの配置値、mode 5はtimecodeなどの基準offsetを扱う可能性があります。小calleeから`FUN_019adc00`、`FUN_019fd568`、`FUN_019ade8c`を追った[位置変換の追加解析](SA-AE-TIME-001-position-conversion.md)では、初期rate値44100、固定小数点の計算、deltaとanchorの加算、内部cacheへの書き込みを確認しました。単位・epoch・runtimeのrate更新は未確定です。1秒・1beat・1sampleの境界やsample rate/tempo変更への依存も実機未検証です。

**未知modeの到達は機械語で確認済み:** callerが別処理へ分けない0、負値、15以上について、helperのdefault分岐は取込経路を拒否しません。ファイル・対象などの条件次第でMIDI/非MIDI処理へ到達します。未知modeを「何もしない値」とみなして送信・探索しません。これは全入力で変更が成功するという意味ではありません。

## 4. MIDIと非MIDIの変更経路

ファイルを`CFileRef`へcopyし、`CFileUtilFileType`の値が`.MID` / `idiM` / `Midi`ならMIDI分岐へ進みます（`0x005923ac..0x005923f4`）。それ以外は非MIDI分岐です。すべての非MIDIファイルが有効な音声fileとは確認していません。

| 経路 | 静的に確認した変更・呼び出し | アドレス |
|---|---|---|
| MIDI | `FUN_004f3ba8`の結果が0なら、対象の16-bit indexと64-bit位置を`FUN_002a2ee0`へ渡す | `0x005923f8..0x00592410`、`0x0059245c..0x0059249c` |
| MIDI後処理 | 条件が合うとsong `+0xe4`へOR 3とOR 4、`+0x96`へOR 8。途中で`FUN_001be198`を呼ぶ | `0x005924a8..0x00592510` |
| 非MIDI | callbackを伴う`FUN_0106cb7c`、既存候補の`FUN_019cfff0`、fallbackの`FUN_00256820`によりファイル側のobject候補を得る。global flagも変更する | `0x00592574..0x0059260c` |
| 非MIDIのmetadata | objectの`+0x2e8..+0x2f0`にあるstride `0x2f8`の候補を選ぶ。`sPrg`を`+0x30`にUTF-8 copy/fixし、`sPst`を`+8`、0を`+0xc`、`sPsp > 0`なら`sPsp-sPst`を`+0x18`、modeで計算した補正値を`+0x20`へ書く | 対象候補`0x0059263c..0x00592724`、書込`0x00592764..0x005927b8` |
| 非MIDIの配置候補 | `FUN_0029c998`で候補を探し、対象・track・位置を比較。一致しない場合に`FUN_0029d5b0`を呼び、その後選択/更新らしい補助処理とglobal flagのclearがある | `0x005927c4..0x005928c4` |

`sPst/sPsp`のstore対象はファイルobject側のmetadata配列です。**arrange上のregionをIDで指定して、位置・長さを任意に編集するAPIだとは確認していません。** 特に`sPrg`は既存regionの検索より後に名前を書き込むのではなく、ここではmetadataへ先に書き込み、その後に配置候補を照合します。

**Hypothesis、確信度: 中:** `sPst`はファイル内の開始位置、`sPsp`は終了位置、`+0x18`は長さに対応する可能性があります。sample数・byte数・tick数のどれかは未確定です。`sPsp > 0`の確認だけで、`sPsp >= sPst`や有効なfile内範囲をこの場所が検証しているわけではありません。

大きなcallee `FUN_002a2ee0` / `FUN_0029d5b0`のUndo・dirty・region生成の完全な監査は未完了です。上記storeは変更可能性の直接証拠ですが、各flagの人間向け意味やディスク保存結果は実機未検証です。

**metadata選択にも初期化呼び出しがある:** helperは`0x00592678`で`FUN_0042120c`へ`w5=1`を渡します。同calleeはstride `0x2f8`の候補を調べ、候補の先頭shortが0、`+0x24`のsigned byteが非負の経路で、候補`+0x28c`を`CUUIDBase::Init(...,0)`へ渡します（`0x00421264..0x0042130c`）。呼び出し自体は機械語・import名で確認済みですが、initializer内部の正確なstoreとUUIDの意味は今回未監査です。既存候補を探すだけのgetterと扱いません。同calleeの返値は下位32-bit indexと上位flagを組み合わせた形で、失敗候補`0xffffffff`もあります（`0x004212a4..0x004212bc`、`0x00421318..0x0042132c`）。Cの推定return型を単純なpointerとして使いません。

## 5. 成功・失敗の戻し方

`0x00591b10`でhelperを呼んだ直後、`0x00591b14`は`0x005911d8`へ分岐します。そこは`mov w22,0`、`0x00591070`は`w22`をsigned 16-bitへ縮めて戻す経路です。**helperの返値を操作結果へ変換していません。** file/regionのこの正常復帰経路は`sPer`を書きません。テキストmodeの`sPer=0`応答と混同しません。

helperは無効な対象、位置の範囲外、parser失敗などで早期復帰でき、共通の終了は`0x00592424..0x00592458`です。その後もcallerは0を返し得ます。逆にdescriptorの取得エラーはcallerの`w22`を通じて返されます。認識・decode・取込実行・望んだ結果を別々に扱う必要があります。

今は外部の信頼できるreadback、返されたregion ID、完了通知、長時間処理のjob仕様を確立していません。reply成功だけで`verified: true`にはできません。

## 6. 次の限定解析

1. 対象predicate `FUN_019fb130`の確認済みstoreの意味と、`FUN_0042120c`から呼ぶ`CUUIDBase::Init`内部を限定解析する。内部metadataの変更とsong dirty/Undo/保存結果を分ける。
2. 変換wrapperから`FUN_019adc00` / `FUN_019fd568` / `FUN_019ade8c`を一段だけ追い、入力・出力・丸めの単位を決める。関数名からsampleと断定しない。
3. `FUN_0029c998`のblock `FUN_0029ca8c`と、file取込`FUN_0041e870`を限定解析し、file object ID、metadata index、arrange eventを分ける。
4. その後に`FUN_002a2ee0` / `FUN_0029d5b0`を対象とし、生成/置換、Undo、dirty、通知、エラーの境界を整理する。

静的仕様が固まった後の動的検証は別の実験記録で行います。専用曲・1つのfield・複数値/対象を使い、before/after・保存再読込・独立したreadbackで確認します。この記録はイベント送信や未知mode実行を行った実験ではありません。
