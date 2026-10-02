[日本語](SA-AE-MODES-001-text-operations.md) | [English](SA-AE-MODES-001-text-operations.en.md)

# SA-AE-MODES-001 — AppleEvent mode 7–14 の静的な入力・処理・応答

`aUeV/Spt2` の mode 7–14 は、設定の読み込み、XML の生成と書き出し、FileChecks の保存、プラグイン設定の適用、MIDI ファイルの処理、音声出力候補、ウィンドウ経由の処理、ファイルと対象レコードの更新へ分岐する。これは ARM64 の呼び出しと書き込みの記録であり、操作の完全な意味、実行成功、完了、Undo、再試行の安全性を証明するものではない。全行 `runtime_verified=false`、製品 capability への追加は行っていない。

共通の応答 `sPer:long=0` は操作の成功を示さない。mode 13 はその応答を書かない。mode 8 は文字列生成の下位処理にも対象レコードを書き換える分岐があるため、読み取り専用として扱えない。

## 対象と証拠

| 項目 | 内容 |
|---|---|
| 調査日 | 2026-10-02、Asia/Tokyo |
| バージョン | Logic Pro Creator Studio 12.3.1 / build 6682 |
| イメージ | `Contents/Frameworks/Logic.framework/Versions/A/Logic`、thin ARM64 |
| 保存済み Executable SHA-256 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| Ghidra program / language | `Logic.arm64` / `AARCH64:LE:64:AppleSilicon` |
| アドレス | このイメージのスライド前アドレス。実行時ポインターではない |
| 今回の方法 | Ghidra headless `-readOnly -noanalysis` の限定逆コンパイル、命令／pointer 出力、分岐、レジスターの受け渡し、セレクター参照の照合。命令／pointer 用 script は保存済み program 名・Executable SHA-256 を guard |
| 実行 | この調査では AppleEvent 送信、Logic の実行時操作、接続、製品コード変更をしていない。headless 出力は分析 DB の再解析・変更をせず、ローカル raw 証拠を保存 |

バイナリ識別は [SA-IDENTITY-001](SA-IDENTITY-001-binary-inputs.md)、登録と共通入口は [appleevent-registration](appleevent-registration.md) を参照。今回の出力、log、script の hash と provenance は [appleevent-mode-analysis-manifest.json](appleevent-mode-analysis-manifest.json) にある。ローカル証拠は以下。`Research/raw/` は Git 対象外であり、この記録では必要なアドレスと短い命令だけを整理する。

- [q-appleevent-modes-001-machinecode.txt](../raw/ghidra/q-appleevent-modes-001-machinecode.txt): ハンドラー、8 個の helper、命令バイト。header が上記 SHA-256 を示す。
- [q-appleevent-modes-callees-001-machinecode.txt](../raw/ghidra/q-appleevent-modes-callees-001-machinecode.txt): `0x001a1dcc`、`0x01a15c7c`、`0x017b0308`、`0x004b2a08`、`0x01b215e0` の命令・参照。
- [q-appleevent-mode-strings-001.txt](../raw/ghidra/q-appleevent-mode-strings-001.txt): 同じ Executable SHA-256 を確認した、9 個の CFString の本体・pointer・length と完全な FileChecks セレクター文字列。data の変更なし。
- [q-appleevent-xml-block-001-machinecode.txt](../raw/ghidra/q-appleevent-xml-block-001-machinecode.txt)、[q-appleevent-xml-block-001.c](../raw/ghidra/q-appleevent-xml-block-001.c): mode 8 の block `0x017b0598` と iterator `0x01a15eb0`。block ABI と iterator の store は命令出力で照合。
- [q-appleevent-xml-node-001-machinecode.txt](../raw/ghidra/q-appleevent-xml-node-001-machinecode.txt)、[q-appleevent-xml-node-001.c](../raw/ghidra/q-appleevent-xml-node-001.c)、[q-appleevent-xml-strings-001.txt](../raw/ghidra/q-appleevent-xml-strings-001.txt): `0x0154d8fc` の factory / child 境界、newline、type / format の pointer table と文字列。完全な XML schema の出力ではない。
- [q-appleevent-text-modes-001.c](../raw/ghidra/q-appleevent-text-modes-001.c)、[q-appleevent-object-resolvers-001.c](../raw/ghidra/q-appleevent-object-resolvers-001.c): 読みやすい制御フローの補助。推定された C の引数型・戻り型・変数名は証拠として優先しない。
- [appleevent-text-modes.tsv](../protocol/appleevent-text-modes.tsv): 8 モードの小さな対応表。

## 共通入力と応答の ABI

入口は `0x00590e30`。`0x0276de68` の owner と `owner+0xc0` の currentSong を読む。どちらかが null なら `0x00591054` から **-38** を返す。`sPmo` は正確に `long`。以下の `song` はこの currentSong を指し、公開された安定 ID ではない。

| mode | handler 内の call | helper | 追加入力 | 通常の呼び出し後の reply |
|---|---|---|---|---|
| 7 | `0x005911e8` | `0x017af4ac` | `sPpn:utxt` または `sPpn:utf8` | 非 null reply に `sPer:long=0` |
| 8 | `0x005912b0` | `0x017b1c9c` | 同上 | 同上 |
| 9 | `0x00591198` | `0x017afd88` | 同上 | 同上 |
| 10 | `0x00591290` | `0x017b1e8c` | 同上 | 同上 |
| 11 | `0x00591170` | `0x017b174c` | 同上 | 同上 |
| 12 | `0x005912a0` | `0x017b201c` | 同上 | 同上 |
| 13 | `0x005911d4` | `0x017b22f8` | `sPpn` を読まない | この経路では `sPer` を書かない |
| 14 | `0x005911b8` | `0x017b19c0` | `sPpn:utxt` または `sPpn:utf8` | 非 null reply に `sPer:long=0` |

`sPpn` の `AESizeOfParam` は `0x00590f88`。型比較は `0x00590f98–0x00590fb4`。UTF-8 は `CFStringCreateWithBytes`（`0x0059101c`、encoding `0x08000100`、externalRepresentation `0`）、UTF-16 は `CFStringCreateWithCharacters`（`0x00591100`、actualSize の符号付き 2 除算を character 数に使用）を通る。NSString 化した値を `x23` に保持し、helper に `x0=song, x1=NSString` として渡す。UTF-16 の奇数バイト数を拒否する検査はこの区間には見えない。

受理型以外の `sPpn` は `0x00590fb4 → 0x005911d8` で何も呼ばず handler return `0` となり、この経路は `sPer` も書かない。NSString が nil なら `0x0059113c → 0x005912b4` となり、helper 未実行でも通常の `sPer=0` になり得る。`AESizeOfParam` / `AEGetParamPtr` の非ゼロエラーは exit へ渡る。したがって return `0` も `sPer=0` も「操作が走った」の確認にはならない。

共通末尾の実命令は以下。helper の値から status を作る命令はない。

```asm
005912b4  mov w22,#0x0
005912b8  str wzr,[sp,#0x30]
005912d0  add x3,sp,#0x30
005912d8  mov w1,#0x6572             ; movk を合わせて sPer
005912e0  mov w2,#0x6e67             ; movk を合わせて long
005912e8  mov w4,#0x4
005912ec  bl 0x01aeca4c              ; AEPutParamPtr
005912f0  mov x22,x0
00591070  sxth w0,w22
```

`AEPutParamPtr` 自体の結果だけは handler の符号付き 16 ビット return に伝わる。mode 13 は call 後 `0x005911d8` で `w22=0` として直接 exit する。各 helper の戻り値、ファイルエラー、下位処理の完了は reply に伝わらない。

## 対象解決の確認できた境界

`0x001a1dcc(song, song+0xd4 の uint32, song+0xd8 の uint16)` は、入口で第 3 引数を `sxth` し 1 以上か検査する。song の magic は `0xabc04723` / `0xabc04713`。第 2 引数 `0x7ffffff8` / `0x7ffffffc` は別分岐、それ以外は下位 2 ビットと符号ビットが 0 の値を右に 2 ビットずらして pointer 配列を選ぶ。選択コンテナーの `+0x330/+0x338` の範囲から、`(arg3 & 0x7fff)-1` 番目の **0x50 バイトレコード**を返す（`0x001a1eac–0x001a1ef0`）。失敗は null。

これは `song+0xd4/+0xd8` と内部レコードのデータフローの確認であり、UI のトラック番号、プラグイン slot、リージョン ID の意味や lifetime は未確定。mode 8/9 のコンテナー選択は一部 caller 内にも展開されている。

`0x01a15c7c` は別の pointer 配列 `song+0x788 → +0x1e0/+0x1e8` を参照し、record `+0x69==0x11` と signed byte `+0x335<13` を検査する。さらに `+0x150/+0x158` の配列と record の signed short `+0x320` を使って object を返す。第 3 引数が非 null なら中間 container を out parameter に書く（`0x01a15d84`）。失敗時の return と out parameter は 0。名前付けされていない内部構造を、安定した外部識別子として扱わない。

## 各 mode の観察と Hypothesis

表の confidence は候補名の確信度であり、実行成功の確信度ではない。機械語で直接確認した call/store は下記の詳細に分ける。

| mode | Hypothesis（未検証の操作意味） | confidence | 機械語で確認した主要な境界 |
|---|---|---|---|
| 7 | 選択先への channel setting / patch 読み込み | medium-high | `loadSettingFromURL:…importFlags:`、songID、track と ginst の in/out pointer |
| 8 | 選択対象の Patch / Channels XML をファイルへ書き出す | high（XML 経路） | XML selector → Patch wrapper → NSString → file write、対象 byte と iterator cache / entry の store |
| 9 | 指定 plist の FileChecks メタデータ更新 | medium-high | `createFileChecksForTrack:inSong:inSeqID:`、plist 読み書き |
| 10 | 対象のプラグイン設定 / preset を読み込んで適用 | medium-high | `.aupreset`、loader、適用 call、object flag store、通知文字列 |
| 11 | 現在位置・現在 track を使う MIDI インポート | medium-high | MIDI file type、parser、song/buffer/track/position を下位関数へ、song flag store |
| 12 | 現在 track の一時出力と AAC 変換 | medium | temporary CFileRef、生成候補、拡張子変更、変換候補、削除 call |
| 13 | type `0x7049` のウィンドウを使う editor 処理 | low | `fenster` と `0x005e559c` への tail call |
| 14 | 選択先のファイル参照と名前等の更新 | medium | filename / parent directory の文字列、buffer store、複数 setter 候補 |

### mode 7 — `0x017af4ac`

`0x017af4e4` で対象レコードを解決し、`+0x20` の 32 ビット値を `w22` に読む。pathExtension と CFString `0x0233f748` を options `1` で比較し、一致すると `0x017af538 → 0x002c66f8(song,id,1,0)` を呼ぶ。pointer/data 出力でその CFString は **`cst`**、length `3`、payload `0x01d5c656` と確認した。

`ChannelSettingsUtilities` の逆コンパイル class 名に対応する receiver を作り、song `+0x860` で `initWithSongID:`。選択フィールド `song+0xd8` は `-1` と `0` を `-1`、それ以外を 1 減算した signed 値として、`intoTrack:` に渡す local に入れる。`0x017af5cc → 0x01b59e00` は **`loadSettingFromURL:withCategory:intoTrack:withGinst:inFolderWithID:enablePatchMerging:importFlags:`**。category `0`、track / ginst local の pointer、folder 値 `song+0x10`、patchMerging `0`、stack 上の importFlags `0x10c` を渡す。

正常末尾 `0x017af5e0–0x017af5fc` に明示的な `w0/x0=0` はない。逆コンパイルの `return 0` は操作 status の証拠にならない。caller は helper 後に `0x0065d80c` の値と counter を比べる loop、条件付きで `0x0065d5a8` 等を呼ぶ（`0x00591220–0x00591284`）。この loop を設定読み込みの完了待ちと呼べる根拠はまだない。

### mode 8 — `0x017b1c9c` → `0x017b0308`

`0x017b1db0` の generator 戻りを retain して `x20` に保存する。`0x017b1de4` の write receiver はその **生成文字列**であり、song ではない。`maStringByResolvingSymlinksAndAliasesInPath` 後の path に、`writeToFile:atomically:encoding:error:`（`0x017b1df4 → 0x01bcd400`）を atomically `1`、numeric encoding `4`、NSError pointer で呼ぶ。結果 bit 0 が 0 なら NSLog。正常末尾 `0x017b1e38–0x017b1e50` に明示的な status return はない。

generator は `0x017b04b8 → 0x0154d8fc` の object を receiver に、`XMLStringWithOptions:1`（`0x017b04cc`）を呼び、`stringWithFormat:`（`0x017b0518`）で wrapper を作って autoreleased object を返す。別経路は block `0x017b0598` を `0x01a15eb0` に渡し NSMutableString を作る。限定した追加出力で、この block の引数、選別条件、XML append、iterator の store、`0x0154d8fc` の factory / child 境界まで照合した。完全な Channels schema は下位の factory / child 関数の調査待ち。

wrapper は命令の stack varargs と CFString 本体を照合した。format `0x02414488` は `%@%@\n%@`（length `7`）、第 1 object `0x024144a8` は `<?xml version="1.0"?>\n<Patch>\n<Channels>\n`（length `41`）、第 2 object は生成内容 `x20`、第 3 object `0x024144c8` は `</Channels>\n</Patch>`（length `20`）。したがって Patch / Channels の XML wrapper は確定する。生成対象の channel/slot 範囲や再読み込みの可否までは確定しない。

副作用は直接見える。前方の 0x50 バイトレコードを走査し、隣の `+0x12` byte と対象の `+0x12` byte の差が 2 以上なら、`0x017b03ac: strb w9,[x1,#0x12]`。意味は未確定だが、XML 生成を読み取り専用とする分類は不適切。

**block ABI と選別。** caller `0x017b03e0–0x017b041c` の stack block と invoke の受け渡しを照合した。以下の block は iterator が retain した object。callback の C は 3 引数だが、実際の call は 4 引数を渡す。

| 項目 | 命令で確認した内容 |
|---|---|
| invoke | block `+0x10 = 0x017b0598`。iterator `0x01a15fe4–0x01a15ff4` が `x0=block, x1=song, x2=entry, x3=&stopByte` で間接 call |
| string capture | block `+0x20` の NSMutableString。callback `0x017b0690` と `0x017b06f8` が append receiver に読む |
| filter capture | block `+0x28` の uint32 は、元の 0x50 バイトレコード `+0x20` の値。callback `0x017b05ac–0x017b05c4` は entry `+0x30` **または** `+0x48` がこれに一致する場合だけ進む |
| stop byte | iterator `0x01a15f84` で 0 に初期化し、call 後 bit 0 を検査。今回の callback は第 4 引数を使用・更新しない |

callback は entry `+0x69==0x11`、signed byte `+0x335<=12`、song magic を検査し、`base=0x20`（byte<=9）または `0x50` と byte×4 の和が非負か確認する。song `+0x788 → +0x150/+0x158` の pointer 配列、選んだ container の `+0x50/+0x58`、entry signed short `+0x320` から object を得る。entry `+0x30` で `+0x1e0/+0x1e8` 配列の要素を選び、無効・nil の場合は先頭要素に fallback、その `+0x86` の UTF-8 文字列を name 候補にする。

`0x017b06b0 → 0x0154d8fc(object,nameNSString)` の**戻り object**を `XMLStringWithOptions:1`（`0x017b06c4`）へ渡し、戻った XML string を `0x017b06dc` で capture の NSMutableString に append。続く `0x017b0714` は同じ string に CFString `0x02344a28` を append する tail call。別の pointer/data 出力でその内容は **newline**（payload `0x01d70fd1`、length `1`、bytes `0a00`）と確認した。

**iterator の書き込み。** `0x01a15eb0` は song `+0x658` が `0xffffffff` のとき、`song+0x788 → +0x1e0/+0x1e8` の pointer 配列を走査し、`entry+0x69==0x11` の要素を encoded index（array index×4）で連結する。最初の index を song `+0x658`（`0x01a15f10`）、前の entry `+0x6b4` に次の index（`0x01a15f64`）、末尾に `0xffffffff`（`0x01a15f74`）を書く。該当要素がなければ song `+0x658=0xfffffffe`（`0x01a15f80`）。cache が初期値でなければこの構築を省く。

遍歴のたびに有効な type `0x11` entry へ **`0x01a15fdc: str w21,[x2,#0x30]`** を実行し、`+0x6b4` から次の index を読み、その後 callback を呼ぶ。したがって callback の filter で XML に採用されない要素にも、この store は先に実行される。これらは書き込みの存在の確認であり、既存値が毎回変わる、プロジェクトへ永続化される、dirty/Undo を立てるという意味までは証明しない。iterator の正常末尾 `0x01a16000–0x01a1601c` にも明示的な return `0` はなく、逆コンパイルの `return 0` を成功 status として使わない。各 entry を UI の track や安定 entity と同一視しない。

**XML node factory の限定確認 — `0x0154d8fc`。** `x0` の内部 object を `x22`、`x1` の name を retain して保持する。name が nil なら object `+0x73` から `stringWithCString:encoding:`、numeric encoding `0x1e` で作る。`0x0154d9c8 → 0x01af4980` の receiver は逆コンパイルで `MAXMLElement` とされた class slot。引数は `x2=name, x3=typeCFString, x4=formatCFString, x5=emptyCFString`。この stub の完全な selector と XML の tag / attribute 名は今回の出力にない。

| ラベルの選択 | 命令と pointer/data で確認した対応 |
|---|---|
| type | unsigned short `((object の uint16 type & ~0x8)-0x40)` が 7 未満なら table `0x02326220–0x02326250`。index 0–6 は `AudioTrack`, `Other`, `Aux`, `Instrument`, `Output`, `Bus`, `Master`。範囲外は CFString `0x02362368` の `Other` |
| format | object byte `+0x89` が 5 未満なら table `0x02326258–0x02326278`。index 0–4 は `Mono`, `Stereo`, `Left`, `Right`, `Surround`。範囲外は空 CFString `0x02338b48` |

これらは XML object の factory に渡される channel-like な分類ラベル。`AudioTrack` 等の文字列だけで UI の track entity、安定 ID、公開 schema と同一視しない。

二つの group は object の signed short `+0x4e` / `+0x4c` を count とし、pointer 範囲 `+0x30/+0x38` からそれぞれ index `i + signed(+0x4c) + signed(+0x4a)` / `i + signed(+0x4a)` を選ぶ。type bit `0x40` があり type `!=0xc0`、index が範囲内、child pointer 非 null の場合、`0x0154da68` / `0x0154daf4` から `0x0154dcb4(child,object)` を呼ぶ。戻り child が非 null なら配列に追加。配列が非空なら `0x0154db2c → 0x01af4b40` の wrapper を `0x0154db44` で root の `addChild:` に渡す。この child 生成関数と wrapper stub は未調査なので、子要素の意味・schema は未確定。

続く新しい配列は signed short `+0x4a` の group を走査するが、この区間に child 生成や `addObject:` はない。通常の空 `arrayWithCapacity:` の内容はこの本体では増えず、`0x01af4b80` / `addChild:` は非空 count を条件にしたコードとしてのみ残る。実行時の包含を確認したとは扱わない。`0x0154dbfc` の `_IsALPCheckForEmptySlots` が非ゼロなら、`0x0154dc14 → 0x01b16080` に内部 object と XML root を渡す。この追加処理も未調査。

この node 本体に入力 `x22` を直接更新する store は見えないが、下位 call の副作用まで否定しない。確認したのは name・type・format の選択、XML root を返す ABI、二つの child group と未調査の追加処理までである。

### mode 9 — `0x017afd88`

`0x017afeb0 → 0x01b215e0` のセレクタースロットは `0x0254a130`。命令レポートが解決した完全な文字列は `0x01edba48` の **`createFileChecksForTrack:inSong:inSeqID:`**。逆コンパイルの pointer 名は `…inSong:` までなので、省略された名前を採用しない。実引数は `x2=0x001a1dcc の戻り`, `x3=song`, `x4=選択 container pointer`（`0x017afe9c–0x017afeac`）。セレクターの Track / SeqID という語だけでは、その表現型を確定しない。

alias 解決した path の NSData を読み、`propertyListWithData:options:format:error:` に options `2` を渡す。dictionary がある場合、collection があると `allObjects` を CFString `0x02406048` の key に set、nil なら既存 key を remove する。key は pointer/data 出力で **`FileChecks`**、length `10`、payload `0x01e28056` と確認した。保存は plist serializer（`0x017b005c`、format `200`, options `0`）→ NSData `writeToFile:options:error:`（`0x017b0090`、options `1`）。読み込み・serialize・write の失敗の一部は NSLog へ出る。

`0x017b0094` は write の戻りを `x25` に保存し、`0x017aff80` は `x0=x25` として返す。この bool 候補は実際に ABI 上残るが、caller `0x0059119c` は共通のゼロ status へ分岐して破棄する。ファイルを更新する観察は強いが、収集処理の内部、plist の全 schema、key 内容、song への追加変更は未確認。

### mode 10 — `0x017b1e8c` → `0x004b2a08`

二つの resolver 後、type の bit `0x8` を除いた値 `0x43`、object `+0x48` の index が `0x12` 以下か検査する。`0x002c8a10` / `0x002c90cc` の結果から linked entry を探す。指定 path の CFileRef が `IsFile` 非ゼロなら `0x017b1f94 → 0x004b2a08(CFileRef,entry)`。type や entry が具体的な plugin slot を意味するかは未確定。

下位関数は `.aupreset`（`0x01e0ed4b`）の extension を調べ、`0x004b2adc → 0x004b1234` に file と対象を渡す。buffer が非 null の経路では、対象 `+0xa8` の CFileRef を代入、`0x004b2b38` で `+0x110` を 0、`0x004b2be8 → 0x004afaa0(buffer,entry,2,dictionary)`。その戻りを `w22` で検査し、非ゼロ分岐で entry `+0x18` に `0x40000` / `0x20000` を OR（`0x004b2ce8/0x004b2cf0`）、`0x004b0ad4` に CFString `0x0234cce8` を渡す。pointer/data 出力の完全な内容は **`com.apple.logic.pluginsetting_loaded`**（length `36`、payload `0x01d76217`）。逆コンパイルの symbol 表記から句読点を復元しない。

`0x004b2d20` 以降の下位正常経路は `0`、`0x004b2d3c` の apply 失敗候補は `-1`。buffer なし経路も `0` を返すため、これだけで成功定義は確定しない。mode helper と AE caller はこの値を操作 status として伝えない。適用、変更通知、object 書き込みの境界はあるが、preset の全種類、load の完了、Undo の意味は未確認。

### mode 11 — `0x017b174c`

song / path 非 null、選択フィールド `song+0xd8 != -1`、CFileRef `IsFile` bit 0 を検査する。`0x017b17d8 → 0x001a388c(song,0)` の戻りを position local に保存。FileType を `0x2e4d4944` / `0x6964694d` / `0x4d696469` と比較する。MAMem の parser 候補 `0x004f3ba8`（`0x017b182c`）が **0 を返す分岐**で、`0x017b18cc → 0x002a2ee0` に song、buffer、track pointer、position pointer、`w4=1, x5=0, w6=0x3c`、filename を渡す。

戻り値を確認せず、条件付きで song `+0xe4` に OR `3` / `4`（`0x017b1928/0x017b193c`）、`+0x96` に OR `8`（`0x017b1948`）する。これらは確定した書き込みであり、dirty / Undo / completion bit という名前は未確定。MIDI import という候補は強いが、位置の単位、track を新規作成する条件、テンポの扱い、parser の詳細は未確認。

### mode 12 — `0x017b201c`

選択フィールド `song+0xd8` が `-1` なら処理しない。指定 path の CFileRef と、`NSTemporaryDirectory` から作った **mutable な別の CFileRef** を用意する。track 候補の local はこの選択フィールド minus 1。`0x017b211c → 0x0037b858` に song、folder `song+0x10`、track pointer、一時 CFileRef pointer、flags `0x2200` または `0x40002200` 等を渡す。戻りが非ゼロのときだけ、指定 path の拡張子を消し CFString `0x023469a8` を append した文字列で `0x017b2180 → 0x00354128` を呼ぶ。CFString は pointer/data 出力で **`aac`**（length `3`、payload `0x01d72138`）と確認した。下位二関数の render / convert という操作名は Hypothesis。

生成候補 call の後は、戻り 0 の場合も含めて、一時 CFileRef の `CopyFileSystemPath` を `removeItemAtPath:error:`（`0x017b21d0`、error pointer nil）に渡す。結果を見ない。CFileRef は `0x0037b858` に pointer で渡されるため、**削除時に指す最終 path はまだ分からない**。「安全に一時ファイルだけを消す」とは確定できず、この点を解決する前に実行試験へ進めない。出力ファイルの完成、codec、範囲、上書き、非同期処理、変換失敗は reply から確認できない。

### mode 13 — `0x017b22f8`

選択フィールド `song+0xd8` が `-1` なら return。type local `0x7049` と global owner を `0x004f1678` に渡し、戻った object へ `fenster`（`0x017b2340`）。その結果 `+0x74` の値、window pointer、song、`1,1,0,0` を `0x005e559c` に **tail call**（`0x017b237c`）する。window の null 検査はこの helper 内には見えない。

window/editor 関連という候補以外の具体的な操作名は未確定。tail call の return は caller が破棄し、handler return `0`、この経路の `sPer` なし。mode 13 を「テキストが必要」とする schema は誤り。

### mode 14 — `0x017b19c0`

resolver のレコード `+0x20` が正値で、二つ目の resolver が非 null の経路を進む。`0x001ab414` で path を CFileRef にし `IsValid` bit 0 を確認。filename の UTF8String を `0x0022cc34(song,id,name)`、parent directory の lastPathComponent を文字列置換後、別 resolver と `0x0022cadc` の戻った record へ書く。置換は CFString `0x0233a448` の **`/`**（length `1`）→ `0x02338b48` の **空文字列**（length `0`）と pointer/data で確認した。

確定した store は `0x017b1b44: bzero(record+0x62,0x40)`、`0x017b1b54: utf8_strlcpy(...,0x40)`、`0x017b1b5c: utf8_check_and_fix`、`0x017b1b60: strh wzr,[record,#0xae]`。続いて `0x0022c914(song,id,&fileRef)`、保持した CFURL がある場合 `0x002bfdb0(song,url,id,container,object,0)` を呼ぶ。filename、親 directory 名、file reference と対象が関係することは確認できるが、sample/instrument/region のどれを変更するか、何を読み込むかは下位 setter の調査待ち。

## 有限の次工程と受け入れ条件

| gate | 限定した確認対象 | 受け入れ条件 |
|---|---|---|
| M1: XML の未調査境界 | factory stub `0x01af4980`、child `0x0154dcb4`、wrapper stub `0x01af4b40/0x01af4b80`、条件付き `0x01b16080` | wrapper と文字列、block ABI・filter・append、iterator store、node の name / type / format と二つの child group は照合済み。次は各 stub の完全な selector と child schema、empty-slot 分岐の変更範囲を限定して確定。完全な schema や再インポート互換性へ推測で拡張しない |
| M2: 対象の表現 | 二つの resolver の呼び出し元、record の既知型参照 | `+0xd4/+0xd8`、0x50 record、container、object を別々に図示。公開 ID、UI track number、slot に推測で統合しない |
| M3: mode 10 の適用境界 | `0x004b1234` / `0x004afaa0` の entry/exit と named selector | file から buffer、適用結果、rollback、通知を受け渡しとして確定。全 preset 種を扱えるとはまだ言わない |
| M4: mode 11 の import 境界 | `0x004f3ba8`、`0x002a2ee0` の entry/exit と position units | 0 が進行条件である理由、track/position in/out、失敗・変更条件を確定 |
| M5: mode 12 の削除 path | `0x0037b858` の CFileRef 書き換えと `0x00354128` の completion/error | 0/非ゼロの全 return で最終 temporary path、生成・変換の同期性と失敗、削除対象を追う。削除 path 未解決なら live 試験へ進まない |
| M6: mode 13/14 の意味 | `0x005e559c` の入口の args 消費、`0x0022cc34/0x0022cadc/0x0022c914` の小さい setter | window type と action、変更対象・field・file reference、状態更新を確定。engine 全体への無制限展開はしない |
| M7: 条件付き live 検証 | 定義した実験範囲と session の許可がある `LogicCLI-Test.logicx`、専用一時ファイル | 1 条件ずつ、複数値と複数 track、前後差分、失敗・上書き・Undo、独立読み戻し。確認できなければ `verified:false`。既存の許可を生かし、本記録自体は新たな送信・接続の許可を与えない。PLAN-05 の接続許可 gate は別に維持 |

操作カタログへの登録は、各候補の対象選択、入力 schema、副作用、失敗、完了、独立した読み戻しがそろってから判断する。今回の到達点は静的な呼び出し／書き込み境界と、応答が operation success を返していないことの確認である。
