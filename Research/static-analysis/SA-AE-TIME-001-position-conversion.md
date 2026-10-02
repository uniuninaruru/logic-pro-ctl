# SA-AE-TIME-001: AppleEvent ファイル配置の位置変換

[日本語](SA-AE-TIME-001-position-conversion.md) · [English](SA-AE-TIME-001-position-conversion.en.md)

| 項目 | 内容 |
|---|---|
| 日付 | 2026-10-02 |
| 基準 | Logic Pro Creator Studio 12.3.1 / build 6682、`Logic.framework` ARM64 |
| 基準SHA-256 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| 範囲 | file/region helperからの位置変換wrapper、変換core、context初期化、fallback map |
| 実行 | 保存済みread-only/noanalysis出力の静的監査のみ。Logicへのイベント・接続・実機操作なし |
| manifest | [appleevent-time-analysis-manifest.json](appleevent-time-analysis-manifest.json) |

この調査で確定したのは**入力・出力の算術と内部cacheへの書き込み**です。sample単位、BPM、PPQ、実際の曲のrateへの追従はまだHypothesisです。内部関数を外部の読み取りAPIとして使えることや、file配置の成功を確立していません。

アドレスは基準ビルドのslide前のイメージアドレスです。先行の[ファイル・リージョン分岐](SA-AE-FILE-001-file-region.md)と[登録解析](appleevent-registration.md)を前提にします。Cの推定prototype、alias、関数名だけからABIや単位を決めません。

## 1. 根拠と関数の境界

| ローカル出力 | 対象 |
|---|---|
| `q-appleevent-time-core-001.c` / `q-appleevent-time-core-001-machinecode.txt` | `0x019adc00`、`0x019fd568`、`0x019ade8c`、`0x019ae130` |
| `q-appleevent-time-constructor-001.c` / `q-appleevent-time-constructor-001-machinecode.txt` | `0x01a125c4` |
| `q-appleevent-modes-callees-001-machinecode.txt` | wrapper `0x007abc8c` / `0x007ac29c` |
| `q-appleevent-modes-001-machinecode.txt` | callerの`0x00592328..0x00592388` |

これらは`Research/raw/ghidra/`のローカル領域に置き、全decompile・大量の機械語はGitへ追加しません。manifestで解析対象と出力を照合します。

## 2. ARM64で復元したABI

| 関数 | 入力registerの役割 | 出力・確認位置 |
|---|---|---|
| `FUN_019adc00` | `x0=song`、`w1=対象selector` | `x0=map候補`。fallbackでは`0x027771c0`を返す（`0x019ade6c..0x019ade78`）。Cの`void`は不正確 |
| `FUN_019fd568` | `x0=context`、`x1=anchor`、`x2=position`、`x3=map`、`x4=optional cache` | `x1!=0`なら`convert(position)-convert(anchor)`。再帰2回と差分は`0x019fd668..0x019fd698` |
| `FUN_019ade8c` | `x0=context`、`x1=anchor`、`x2=整数domainの増分`、`x3=map`、`x4=optional cache` | **変換後の絶対位置ではなくdelta**。`0x019ae0e0`の`sub x0,x9,x1`で返す |
| `FUN_01a125c4` | `x0=context`、`x1=初期rate様の整数` | `+0`と`+8`へ保存し、cache nodeをglobal listへ結ぶ（`0x01a125f4..0x01a12628`） |

`FUN_019fd568`のCは呼出し後のregisterを元のparameter名へaliasし、差分が同じ変数同士の引き算のように見えます。機械語は1回目の返値を`x23`へ保ち、2回目の返値から引きます。各絶対変換に独立した`+1`・`FCVTZS`・`ASR16`があるため、一般のintervalを単純な比例式へまとめると丸めを失います。これを0や絶対値と解釈しません。

wrapper `FUN_007abc8c`は`x3==0`なら`FUN_019adc00(song,-1)`からmapを取得し、contextを`0x0266b680`、`x4=0`にして`FUN_019fd568`へtail-callします（`0x007abcb0..0x007abcec`）。`FUN_007ac29c`もmapを取得し、同context・`x4=0`で`FUN_019ade8c`へtail-callします（`0x007ac2c8..0x007ac2fc`）。

file helperは`FUN_007ac29c(song,anchor,sPss,-1)`のdeltaを受け、`0x00592344`でanchorへ加えます。逆変換wrapperで入力と比較し、必要ならraw位置を`0x100000000`増やし、正の残差を32-bit補正値へ保存します（`0x00592328..0x00592388`）。これは単純な整数単位変換だけではなく、配置時の補正を含む境界です。

## 3. contextの初期化とrateの未解決点

両wrapperの初回初期化は、**即値`0xac44 = 44100`**をconstructorの`w1`へ渡します（`0x007abd34..0x007abd38`、`0x007ac334..0x007ac338`）。Ghidraの`FUN_0000ac44`参照注釈は、この場所では関数pointerを示しません。

constructorは`str x1,[x0]`で整数を保存し、64-bit整数の`625*x1`を`SCVTF`でdoubleへ変換して`[x0,+8]`へ保存します（`0x01a125f4..0x01a12614`）。以降のcoreはこのdoubleをscaleとして読みます。

`0x01a12618..0x01a12628`はcontext内の`+0x10`、`+0x48`、`+0x80`を順に結び、最後にglobal `0x02777108`を`context+0x80`へ更新します。単一のcontext pointerを登録するだけではなく、3つの内部nodeを連結する処理です。初期化にはguard・atexit登録もあります。

**未解決:** このcontextのrate/scaleを後から更新する処理と、連結したglobal listの利用側は今回追跡していません。初期44100は実際のproject sample rateが44100である証拠でも、48/96 kHzの曲で固定44100が使われ続ける証拠でもありません。

## 4. map走査と確認済み算術

両coreはmapを**16-byteずつ走査**し、timestampのbit63が立つslotを飛ばし、`0x7fffffffffff0000`でtimestampをmaskします（`0x019fd724..0x019fd72c`、`0x019adefc..0x019adf04`）。走査slot幅と論理record幅は同一とは限りません。denominatorは現在のrecord基準`+0x10`のsigned32で、整数符号拡張後にdoubleへ変換されます。

contextのscaleを`S`、現在のdenominatorを`D`、raw位置差を`d`とすると、spanの整数domain寄与は次の順です。

```text
q = arithmetic_shift_right(d, 16) + 1
span = arithmetic_shift_right(trunc_toward_zero(S * double(q) / double(D)), 16)
```

機械語は`ASR16 → +1 → SCVTF → FMUL → signed32 denominator → FDIV → FCVTZS → ASR16`です。途中recordの累積は`0x019fd73c..0x019fd768`、最後のspanは`0x019fd780..0x019fd7ac`。`+1`を落とした連続式や、単純な四捨五入に置き換えません。

逆方向はanchorを含むrecordを探し、正の入力なら前へ、負の入力なら後ろへ走査します。spanを超える分を減らした後、残りの整数domain量`n`から次のraw位置差を作ります。

```text
positive remainder: delta = trunc_toward_zero(double(n << 16) * double(D) / S) << 16
negative remainder: subtract the analogous delta for the remaining magnitude
return new_position - anchor
```

正側の最終演算は`0x019ae0bc..0x019ae0e0`、負側は`0x019ae100..0x019ae124`です。floatはdouble、`FCVTZS`は0方向への整数化、右shiftは算術shiftです。左shiftも64-bit register上の演算なので、任意の巨大入力を無限精度の式と同一視しません。

## 5. 算術の例と単位のHypothesis

これは**確認した式から作ったsyntheticなローカル算術例**で、native関数の実行や実機結果ではありません。一定`D=1200000`、constructorの初期値`R=44100`、`S=625*R=27562500`とし、record境界を跨がない場合の逆方向deltaを評価します。

| 整数domain入力 | raw delta | `raw delta / 2^32` |
|---:|---:|---:|
| 0 | 0 | 0 |
| 1 | 186974208 | 0.0435333251953125 |
| 22050 | 4123168604160 | 960 |
| 44100 | 8246337208320 | 1920 |

`625 = 600000 / 960`なので、**Hypothesis、確信度: 中**として`D=BPM*10000`、整数domainがsample、raw位置が960 PPQをQ32で符号化した値、という組み合わせは算術と整合します。たとえば120 BPMの1秒は2拍→1920tickとなります。ただしこの一致だけで単位・tempo field・project sample rate対応・epochを確定しません。

## 6. cache・fallbackの変更と限界

`x4==0`でmapのsentinel条件に該当せずmain threadなら、coreはcontext内のcacheを選びます。primaryは`+0x10`、intervalの2回の評価には`+0x48`/`+0x80`も使います（`0x019fd594..0x019fd6e8`、`0x019adf58..0x019adfa0`）。non-main threadや特定sentinelの場合にはcacheを使わない分岐があります。

cache不一致ではgeneration様fieldとmap pointerを更新し、走査後にはrecord pointerと累積整数値を書きます（`0x019fd608..0x019fd61c`、`0x019fd778..0x019fd77c`、`0x019adee0..0x019adef0`、`0x019adf50`）。算術関数でも内部状態を書き換えるため、純粋関数とは扱いません。

map resolver `FUN_019adc00`は参照countのatomic更新・virtual call・map準備calleeを含みます（`0x019adce8..0x019add60`）。fallbackへ進むとsong `+0xc4`のformat値と`+0xcc`の整数を`FUN_019ae130`へ渡し、global record `0x027771c0`を返します（`0x019ade5c..0x019ade78`）。下位callee全部の副作用は未監査です。

fallback初期化は`FUN_019ae9dc`を2回呼び、1回目は`x0=0x027771c0`・anchor引数`0x960000000000`、2回目は**1回目の返値`x0`に`0x20`を加えた宛先**・sentinel引数`0x3fffffff00000000`を渡します（`0x019ae254..0x019ae284`）。calleeの返値・field配置は未監査です。nonzero denominator入力はsigned比較で`50000..9900000`へclampし、`0x027771d0`へstoreします。0は既存値を保持します（`0x019ae194..0x019ae1b8`）。format値が`-1`でない場合は別のglobal fieldも更新します（`0x019ae1bc..0x019ae1cc`）。

これはglobal/cacheの変更を確認した結果であり、保存されるtempo mapやsong dirty flagが必ず変わるという主張ではありません。同時に、全経路の読み取り専用保証にもなりません。file/regionのcallerの0返信が実行成功を保証しない点は先行記録から変わりません。

## 7. 次の限定確認

1. `0x0266b680`とglobal登録nodeの参照を追い、rate/scale更新・cache generation invalidation・寿命を確認する。
2. denominatorを作るrecord constructorとsong `+0xcc`のsetterから、値の単位とtempo変更との対応を監査する。
3. 先にローカルfixtureでflat/multiple-record/bit63/正負・境界・丸めを再現し、算術仕様を検証する。実機のsnapshotと同一とは称さない。
4. その後に専用曲の別実験でsample rate・tempo・positionを1条件ずつ比較し、独立readbackと保存再読込で確認する。

単位・epoch・対象scope・副作用と実行結果が未確定な間は、`sPss`をsampleとして外部APIへ公開したり、native位置APIの互換性を約束したりしません。
