[日本語](SA-COMMAND-CATALOG-001.md) | [English](SA-COMMAND-CATALOG-001.en.md)

# SA-COMMAND-CATALOG-001: Logic が登録しているコマンドの台帳と、Remote のコマンド一覧

| 項目 | 内容 |
|---|---|
| 日付 | 2026-10-05 |
| Logic | 12.3.1（6682）、macOS 27.0 |
| 対象（arm64） | `Logic.framework`（arm64 のみ、SHA-256 `2f141e1a…`） |
| 方法 | **静的解析のみ**。Ghidra 12.1.4 の限定逆コンパイルと、バイナリの読み出し。**コマンドは 1 つも実行していない**。Logic にも何も送っていない |
| 成果物 | [`Research/protocol/operation-catalog.tsv`](../protocol/operation-catalog.tsv)（2353 行） |
| 再現 | [`Tools/research-scripts/command_catalog.py`](../../Tools/research-scripts/command_catalog.py)（試験：`test_command_catalog.py`） |
| 関連 | [SA-004](SA-004-command-and-engine-boundaries.md)（ディスパッチャー）・[SA-002](SA-002-control-surface-assign-model.md)・[SA-REMOTE-FRAME-001](SA-REMOTE-FRAME-001.md)（フレーム） |
| 計画 | PLAN-07 の**静的部分**。コマンドごとの状態評価・副作用の解析は、この文書の範囲外 |

**確信度の約束:** 逆コンパイルの内容・バイナリの値と一致する事実は「確認」、そこからの推論は「仮説」と書く。
実機では何も確認していない。

## 1. 要点

1. **コマンド表は、2353 個のエントリーを持つ。** 番号（`befehl`）の範囲は 1〜4078、表の大きさは 4951。異なる番号は 2351 個で、
   2 個の番号だけが 2 つのグループに登録されている（§4）。**4951 個の操作が使えるわけではない。**
2. **各エントリーには、英語の表示名がある。** SA-004 の「エントリーに名前はない」は誤りだった。名前は +8 にある（§2）。
   画面に出るメニュー項目と同じ綴りで、`Open Setup`、`Learn new Controller Assignment` などの形をしている。
3. **既知の番号はすべて登録されている。** SA-004 が挙げた 18 個、Logic Remote の既定の割り当てが送る 14 個は、すべて見つかり、名前も一致した（§5）。
4. **Remote が受け取るコマンド一覧は、この表から作られる。** ただし Tool Menu グループ全体と、100 個の番号は除かれる（§6）。
   除かれる番号の 96 個が登録済みで、91 個の名前が「…」で終わる（ダイアログを開くコマンドが中心。仮説）。
5. **ハンドラーは 793 種類で、1799 個のエントリーが他のエントリーとハンドラーを共有する。** 引数で動作が変わる（§7）。
   したがって「コマンド番号 = 1 つの独立した操作」ではない。

## 2. 表の構造（確認）

### 2.1 コマンド表

- `FUN_00863ec4`（起動時に 1 回）が、グローバルの `DAT_026883b0` を `bzero(…, 0x9ab8)` する。0x9ab8 / 8 = **4951 個**のポインター。
- 続けて 28 個のグループ記述子を順に `FUN_00864230` へ渡す。ここで各エントリーを `table[entry.befehl] = &entry` と登録する
  （機能が使えるかを `CFeatureAvailability::FeatureAvailable` で確かめてから）。
- 28 は、`FUN_00863ec4` のループ（0x540 / 0x30）と、`LgLogicRemoteController keyCommands:`（0x01683e10）のループが同じ数を回すことで裏付けられる。

### 2.2 グループ記述子（48 バイト）

`FUN_008630b4` が、スタック上に 28 個を作る。

| オフセット | 内容 |
|---|---|
| +0x00 | エントリー配列へのポインター |
| +0x08 | エントリー数 |
| +0x10 | 機能の識別値（`feature`）。意味は未解析（`0x7f`、`0x7049`、`0x2021` など） |
| +0x18 | グループ名の CFString |
| +0x20 | 0 |
| +0x28 | 不明な値（0、`0x17`、`0x5a` など） |

### 2.3 エントリー（40 バイト）

| オフセット | 内容 |
|---|---|
| +0x00 | `int16 befehl`（コマンド番号） |
| +0x08 | 名前の CFString（英語の表示名） |
| +0x10 | 0、または別の CFString（ローカライズ表の名前。例：`Localizable_StemSeparation`） |
| +0x18 | ハンドラー（関数ポインター） |
| +0x20 | 引数（整数） |

エントリーの配列は、13 グループが**静的な配列**（バイナリの中）、15 グループが**構築関数**（スタックへ書いてコピー）。どちらも読んだ。

- 静的：Various Windows、Main Window Tracks and Various Editors、Various Editors、Views Showing Time Ruler、Views Showing Automation、Event Editor、
  Step Sequencer、Smart Tempo Editor、Sampler、Step Input Keyboard、Tool Menu、Control Surface Install Window、MIDI Monitor Window
- 構築関数：Global Commands（`FUN_00f59df0`）ほか 14 個（§3 の表）

### 2.4 ハンドラーの呼び方（仮説）

`FUN_00864230` は、登録するとき各ハンドラーを `handler(&DAT_026920d8, 0, 引数, 0x8000)` の形で呼ぶ（状態の確認とみられる）。
Tool Menu のハンドラー（`FUN_00f2c010`）は、第 4 引数が `0x4000`（定数を返す）、`0x20000`（ツール名を返す）、`0x8000`（使えるかを返す）、
`0x80`・`0x100` で分岐する。**同じ形の呼び出しで、状態確認・名前の取得・実行を切り替えている**と推定する（確信度: 中。ハンドラー 1 つの読み取りと登録時の呼び出しから）。
SA-004 の「`FUN_00f2c010` は `DAT_01cd1d98` を経由して別名のコマンドへ転送する」は、**Tool Menu のハンドラーに関する記述**で、
全体の「別名の表」ではなかった（§8）。

## 3. グループの一覧

台帳の `group_index` と同じ番号。「Remote」は、Remote の一覧に載りうる件数（§6。機能の有無による除外は静的には判定できない）。

| # | グループ | 件数 | feature | 出どころ | Remote |
|---|---|---|---|---|---|
| 0 | Global Commands | 672 | 0x0 | 構築 `FUN_00f59df0` | 598 |
| 1 | Global Control Surfaces Commands | 8 | 0x0 | 構築 `FUN_00ab8d10` | 7 |
| 2 | Various Windows | 273 | 0x7f | 静的 `0x022ebb18` | 272 |
| 3 | Windows Showing Audio Files | 13 | 0x7a | 構築 `FUN_00275dc8` | 12 |
| 4 | Main Window Tracks and Various Editors | 290 | 0x7e | 静的 `0x025dab78` | 286 |
| 5 | Various Editors | 67 | 0x7d | 静的 `0x025ddc38` | 67 |
| 6 | Views Showing Time Ruler | 80 | 0x7c | 静的 `0x022ee5c0` | 80 |
| 7 | Views Showing Automation | 22 | 0x7b | 静的 `0x025dd8c8` | 22 |
| 8 | Main Window Tracks | 247 | 0x7049 | 構築 `FUN_01003904` | 243 |
| 9 | Live Loops Grid | 18 | 0x27049 | 構築 `FUN_01013edc` | 18 |
| 10 | Mixer | 85 | 0x2021 | 構築 `FUN_01431850` | 85 |
| 11 | MIDI Environment | 50 | 0x1010 | 構築 `FUN_0072eef4` | 50 |
| 12 | Piano Roll | 12 | 0x7042 | 構築 `FUN_007c2504` | 12 |
| 13 | Score Editor | 139 | 0x7048 | 構築 `FUN_014d6350` | 138 |
| 14 | Event Editor | 9 | 0x2081 | 静的 `0x022af250` | 9 |
| 15 | Step Editor | 16 | 0x7043 | 構築 `FUN_00f81ef8` | 14 |
| 16 | Step Sequencer | 91 | 0x606d | 静的 `0x022be908` | 91 |
| 17 | Project Audio | 20 | 0x1015 | 構築 `FUN_002744fc` | 16 |
| 18 | Audio File Editor | 55 | 0x1056 | 構築 `FUN_0045e424` | 55 |
| 19 | Smart Tempo Editor | 32 | 0x2c | 静的 `0x022ef6c8` | 32 |
| 20 | Library | 4 | 0x31 | 構築 `FUN_00a03d98` | 4 |
| 21 | Sampler | 36 | 0x1b | 静的 `0x022e2be0` | 34 |
| 22 | Drum Machine Designer | 16 | 0x30 | 構築 `FUN_00ac1c88` | 16 |
| 23 | Step Input Keyboard | 49 | 0x24 | 静的 `0x022b3938` | 49 |
| 24 | Smart Controls | 6 | 0x32 | 構築 `FUN_0158f860` | 6 |
| 25 | Tool Menu | 29 | `none` | 静的 `0x022ef240` | 0（グループごと除外） |
| 26 | Control Surface Install Window | 2 | 0x10d | 静的 `0x022c0590` | 0（抑制） |
| 27 | MIDI Monitor Window | 12 | 0x110 | 静的 `0x022c14c0` | 12 |
| | **合計** | **2353** | | | **2228** |

## 4. 番号の重複

異なる番号は 2351 個。次の 2 個だけが、2 つのグループに登録されている。

| 番号 | 名前 | グループ → ハンドラー（引数） |
|---|---|---|
| 1846 | Set Region Anchor to Playhead | Main Window Tracks → `FUN_0100e960`（0）／Audio File Editor → `FUN_0046db58`（2） |
| 1858 | Set Region Anchor to Region Start | Main Window Tracks → `FUN_0100f468`（0）／Audio File Editor → `FUN_0046db58`（3） |

同じ番号でも、**どのウィンドウ（グループ）にフォーカスがあるかでハンドラーが変わる**ことを示す。
表は 1 つの番号に 1 つのエントリーしか入れない（`table[befehl] = &entry`）ため、後から登録した方が残る。**どちらが残るか**は、登録順（グループ 8 → 18）から後者（Audio File Editor）とみられるが、
機能の有無の判定が絡むので静的には確定できない（仮説。確信度: 低）。番号だけでコマンドを一意に決められない例として、PLAN-10 以降で扱う。

## 5. 既知の番号との照合

SA-004 が挙げた番号と、Remote の既定の割り当て（[`cs-assign-remote.tsv`](../protocol/cs-assign-remote.tsv)、割り当ての種類 9）の番号を、台帳と突き合わせた。

| 番号 | 台帳の名前 | グループ | ハンドラー（引数） | Remote の割り当て |
|---|---|---|---|---|
| 3 | Play | Global Commands | `FUN_00f60470`（0） | `/cs/transport/play` |
| 4 | Pause | Global Commands | `FUN_00f6057c`（0） | |
| 5 | Stop | Global Commands | `FUN_00f606c0`（0） | `/cs/transport/stop` |
| 7 | Record | Global Commands | `FUN_00f5fda0`（0） | `/cs/transport/record` |
| 10 / 11 | Rewind / Forward | Global Commands | `FUN_00f609f4` / `FUN_00f60b04`（0） | |
| 12 / 13 | Fast Rewind / Fast Forward | Global Commands | `FUN_00f60c10`（0 / 1） | |
| 15 | Cycle Mode | Global Commands | `FUN_00f6149c`（0） | `/cs/transport/cycle` |
| 20 | Replace | Global Commands | `FUN_00f616b4`（0） | |
| 29 | Send discrete Note Offs (Panic) | Global Commands | `FUN_00f4f944`（0） | |
| 51 | Catch Playhead Position | Various Windows | `FUN_00f2bbf0`（0） | |
| 474 | Metronome Click | Global Commands | `FUN_00f4eae0`（0） | `/cs/transport/click` |
| 535 | Play or Stop | Global Commands | `FUN_00f607c8`（0） | |
| 542 | Flashback Capture as Recording | Global Commands | `FUN_00f60348`（0） | |
| 761 / 796 | Undo / Redo | Various Windows | `FUN_004f0640`（0 / 6） | `/undo`、`/redo` |
| 1040 | Clear/Recall Solo | Global Commands | `FUN_00f61bac`（0） | `/cs/mixer/soloactive`、`soloreset` |

Remote の割り当てにあるその他の番号も、すべて登録されている：1041 Mute off for all、1272/1273 Select Previous/Next Track、
1329/1330 Go to Next/Previous Marker、1728 New Track with Duplicate Settings（Remote 側の 14 個で、登録されていない番号は **0**）。

## 6. Logic Remote のコマンド一覧（確認）

Remote から Logic への問い合わせは、`LgLogicRemoteMessageRouter routeMessage:withArgument:`（0x011e0118）が `/keyCommand/…` で振り分ける。

| アドレス（Remote → Logic） | 処理（読んだ範囲） |
|---|---|
| `/keyCommand/commandsQuery` | 引数（MAZP 圧縮の NSKeyedArchive）から `groupName` と `requestRange`（範囲）を読む。応答の送り先は `/keyCommand/commandsResponse`。**応答の組み立ての細部は読んでいない** |
| `/keyCommand/commandSearch` | 引数の文字列で、コマンド名を大文字小文字・発音記号を無視して**部分一致**検索する（`rangeOfString:options:0x81`）。`commandName` の昇順に並べ、**大文字小文字を無視して完全一致するもの**を先頭へ寄せる。結果は NSKeyedArchive を MAZP 圧縮（レベル 9）して `/keyCommand/commandResponse` で返す |
| `/keyCommand/localizationRequest` | 引数の `valueArray` の番号を、**20 個ずつ**処理して、ローカライズした名前を `/keyCommand/localizationResponse` で返す |
| `/keyCommand/groupsQuery`、`/keyCommand/keyCommandDictResponse`、`/keyCommand/actionNum` | 振り分けの分岐があることは確認した（`groupsResponse` を送る処理も同じ関数にある）。`groupsQuery`・`keyCommandDictResponse` の本体は読んでいない。**`actionNum` は読んだ**：番号は台帳の `command_id` として、共通のディスパッチャー `FUN_008663d4` に `source` 2 で渡る。結果は待たず、返事も送らない（[SA-REMOTE-KEYCOMMAND-001](SA-REMOTE-KEYCOMMAND-001.md)） |

これらの応答の元は、**§3 と同じ 28 個のグループ記述子**である。`LgLogicRemoteController keyCommands:`（0x01683e10）が組み立てる。

- 辞書の配列を作る。各要素は `{groupName: グループ名, bindingsArray: [[番号, 名前], …]}`。
- `+0x18` のグループ名と、各エントリーの名前（`FUN_00865ba8`）を使う。
- **配列が `0x022ef240`（Tool Menu グループ）のものは飛ばす。**
- 機能が使えないエントリーは載せない（`FeatureAvailable`。静的には判定できない）。
- **`suppressedKeyCommands` の番号は載せない。** このセットは `LgLogicRemoteController -init`（0x01682ad0）で、静的な `NSConstantArray`（`0x02438128`、100 個）から作る。

抑制される 100 個の番号：

```
21 22 30 32 35 36 39 61 62 69 204 403 409 414 476 477 487 488 489 490 497 499 520 540 558 564 639 644 645 652 653
681 685 686 690 751 752 755 756 757 758 759 768 797 1032 1033 1079 1152–1160 1162–1168 1170–1175 1177–1179 1182 1183
1186 1187 1194 1197 1207 1218 1223 1224 1226 1294 1303 1304 1310 1315 1342 1523 1715 1759 1765 1791 1800 1806 1902 3087 3200 3202
```

- 100 個のうち、**登録済みは 96 個**。登録されていないのは 558、639、1033、1162。
- 96 個の名前のうち 91 個が「…」で終わる（`Go to Position…`、`Open Settings…`、`Save Project as…`、`Open Key Command Assignments…` など）。
  **ダイアログを開くコマンドを Remote に出さない**ための除外と推定する（仮説。確信度: 中。名前の綴りからの推論で、ハンドラーの中身は読んでいない）。
- 台帳の `remote_offered` 列は、`yes`（2228）、`no: suppressed`（96）、`no: group skipped`（29）。

**Remote が実際に受け取る一覧は、機能の有無による除外の後で、2228 個以下**になる。実機で確かめていない。

## 7. ハンドラーと引数

- ハンドラーは 793 種類。1799 個のエントリーが、他のエントリーとハンドラーを共有する。
  同じハンドラーを引数違いで使う例：Fast Rewind/Fast Forward（`FUN_00f60c10`、0/1）、Undo/Redo（`FUN_004f0640`、0/6）、
  Record 系（`FUN_00f5feac`、1/2）。
- 最も多く共有されるのは `FUN_0160f17c`（128 個）、`FUN_00601620`（117 個）、`FUN_005a2064`（64 個）、`FUN_005a2c78`（64 個）。
- したがって、**操作を特定するのは「ハンドラー + 引数」**で、コマンド番号は表の添字にすぎない。

## 8. Tool Menu グループ（確認）

29 個のエントリー（番号 2318〜2340、2569〜2571、2683、3034、3035）。ハンドラーは全部 `FUN_00f2c010`、引数が**ツール番号**。
「Set … Tool」（`FUN_00f29a94`、同じツール番号を引数に取る）と**名前も番号も 1 対 1 に対応する**。29 個すべてで確認した。

| ツールメニュー | 対応する Set … |
|---|---|
| 2318 Scissors Tool（1） | 851 Set Scissors Tool |
| 2327 Finger Tool（0x13） | 860 Set Finger Tool |
| 2322 Text Tool（8） | 855 Set Text Tool |
| 2571 Move Tool（0x12） | 2572 Set Move Tool |
| … | …（台帳の `twin_of` 列に全部ある） |

「Set Pointer Tool」（850、引数 0）には、ツールメニュー側の対がない。この関係は、SA-004 の言う「別名」にあたる可能性が高いが、
`DAT_01cd1d98`（850〜854 を含む 16 ビットの表）の役割は**未確認**。ここでは「同等の操作を 2 通りで呼べる」とだけ書く（仮説。確信度: 中）。

## 9. 使い方と限界

- 台帳は、**探すための地図**で、実行の許可ではない。`actionNum` で任意の番号を実行する前に、そのコマンドのハンドラー・引数・副作用を別に解析する。
  PLAN-07 の合格条件どおり、**全 ID の実行はしない**。
- 台帳が答えないこと：
  - 各コマンドの**状態の評価**（有効か・押されているか）。ハンドラーに `0x8000` で問い合わせる形と推定したが、ハンドラーの中身は読んでいない（PLAN-10）。
  - **副作用**。保存・削除・書き出しなど。名前の綴りから推測しない。
  - **必要な状況**（フォーカスのあるウィンドウ、プロジェクトの有無）。Tool Menu のハンドラーでは「there is no project open」「there is no focused view」の通知が出る分岐を見たが、一般化しない。
  - `feature` の意味。`FeatureAvailable` に渡す識別値と推定するが、未解析。
  - 表示名の**日本語など別言語**。`/keyCommand/localizationRequest` が実行時に返す。
- 名前は英語の綴りで、末尾の空白や記号を含む。Ghidra のラベル（`cf_OpenSetup`）は空白を落とすので、**ラベルから名前を作らない**
  （`Tools/ghidra/cfstrings.sh` で実際の文字列を取る）。

## 10. 再現

```sh
# 1. グループ記述子と構築関数（共通ロックつき。時刻の違う出力は Research/raw/ghidra に保存される）
Tools/ghidra/query.sh Logic.arm64 q-p7-table 0x00863ec4 0x008630b4 0x00864230
Tools/ghidra/cfstrings.sh Logic.arm64 logic-cfstrings
Tools/ghidra/stackstores.sh Logic.arm64 p7-stackstores 0x008630b4 0x00f59df0 0x00ab8d10 0x00275dc8 0x01003904 0x01013edc \
    0x01431850 0x0072eef4 0x007c2504 0x014d6350 0x00f81ef8 0x002744fc 0x0045e424 0x00a03d98 0x00ac1c88 0x0158f860
# 2. 台帳
python3 Tools/research-scripts/command_catalog.py --out Research/protocol/operation-catalog.tsv
# 3. 試験
(cd Tools/research-scripts && python3 -m unittest test_command_catalog)
```

アドレスはこのビルド（12.3.1／6682、arm64）のものだけ。別ビルドでは、`FUN_00863ec4`・`FUN_008630b4`・`LgLogicRemoteController keyCommands:` から探し直す。
`command_catalog.py` は、抑制セットの要素数（100）が違うときは**止まる**。

## 11. 不明なこと・次の検証

| 項目 | 状態 | 次の手 |
|---|---|---|
| 各ハンドラーの状態評価（`0x8000`）と副作用 | 未解析 | PLAN-10：ID 3／7（Play／Record）から、ハンドラーを 1 つずつ読む |
| 重複 2 個の番号のうち、表に残る方 | 未確定 | 登録時の機能判定を解析する |
| `feature`（グループ記述子 +0x10）の意味 | 未解析 | `CFeatureAvailability::FeatureAvailable` の引数を調べる |
| グループ記述子 +0x28 の値 | 未解析 | 使われ方（`FUN_00864088` ほか）を追う |
| `DAT_01cd1d98`（16 ビットの表）の役割 | 未確認 | 参照元を追う |
| 抑制セットのうち未登録の 4 個（558、639、1033、1162） | 理由不明 | 別のグループ・古い番号か、機能による登録かを調べる |
| Remote の一覧に実際に載る件数 | 未確認 | 受信実験（PLAN-05 の承認後） |
| ローカライズされた名前 | 未取得 | `/keyCommand/localizationRequest` の応答（受信実験） |
| `actionNum` が番号をどう扱うか（条件・戻り値） | **解決**（静的）：[SA-REMOTE-KEYCOMMAND-001](SA-REMOTE-KEYCOMMAND-001.md) | 送ったときの振る舞いは未確認（送信は承認が要る） |
