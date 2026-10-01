[日本語](EXP-AE-001-private-command-dispatch.md) | [English](EXP-AE-001-private-command-dispatch.en.md)

# EXP-AE-001: テストプロジェクトを開いた状態での aUeV/Spt2 コマンド実行

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-01、Asia/Tokyo |
| Logic | Creator Studio 12.3.1 (6682)、`com.apple.mobilelogic` |
| macOS | 27.0 (26A5416b)、arm64 |
| テストプロジェクト | `/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx` |
| 初期状態 | `playing=false`、`recording=false`。スクリプティング上のドキュメントは1つだけ |
| 変更する条件 | 各ケースで、イベントクラス、イベント ID、パラメータ1つの有無・型・値、または初期の再生状態のうち1つだけを変更 |
| 読み戻し | 既存の `logicctl status`。バックエンドは MCU で、AppleEvent の応答とは独立 |
| 最終状態 | `playing=false`、`recording=false` |

## 結果

当初報告されていた `aUeV/Spt2, sPmo=6, sPkc=-3` は、テストプロジェクトを開いた状態では成功し、再生を開始しました。非公開コマンドの送信に AppleScript を使わず、ネイティブの `AESendMessage` でも再現できました。直接指定（`-3` 再生、`-5` 停止）と、正のマッピングインデックス（`11` 再生、`1` 停止）の両方を、トランスポートの応答で検証しました。

このイベントは Logic.framework に明示的に登録されています。エラーメッセージから推測してイベントの意味を決めたものではありません。

以前の `-38` は、今回のプロジェクトを開いた状態では再現しませんでした。静的解析では、アクティブな owner ポインターまたはその `currentSong` ポインターが null の場合、`sPmo` や `sPkc` を調べる前に早期リターンする箇所を特定しました。ただし、以前のユーザーのセッションでどちらが null だったかまでは分かりません。

## ドキュメントと UI の観察

最初の読み取り専用ドキュメント問い合わせは、Logic がオーディオインターフェースを利用できるか確認する通知を表示している間、待機しました。コンピューター操作ツールで通知を確認した後、ウィンドウは `LogicCLI-Test - トラック`、URL は `file:///Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx/` でした。

以下の標準スクリプティング問い合わせは、次を返しました。

```text
1, LogicCLI-Test, /Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx
```

```applescript
tell application id "com.apple.mobilelogic"
    set n to count documents
    if n > 0 then
        return {n, name of document 1, path of document 1}
    else
        return {n, "NO DOCUMENT"}
    end if
end tell
```

この実行中の Creator Studio は、開いているプロジェクトを Cocoa スクリプティングのドキュメントとして公開しています。SDEF には Standard Suite、Text Suite、Type Definitions、Type Names があり、4つの非公開 FourCC は一度も現れません。
生データの SDEF: `Research/raw/20261001-appleevent-dynamic/sdef.xml`。

## AppleScript での再現と負の対照実験

生データ: `Research/raw/20261001-appleevent-dynamic/osascript-controls.json`。

| ケース | イベント | パラメータ | osascript 終了コード／エラー | MCU のトランスポート |
|---|---|---|---|---|
| 基準 | `aUeV/Spt2` | `sPmo=6, sPkc=-3` | 0、エラーなし | 停止 → 再生 |
| ID だけ変更 | `aUeV/ZZzz` | 同じ | 1、`-1708` | 再生のまま |
| クラスだけ変更 | `ZZzz/Spt2` | 同じ | 1、`-1708` | 再生のまま |
| 基準を繰り返す | `aUeV/Spt2` | 同じ | 0、エラーなし | 再生のまま |

最初の一連の実行は `logicctl transport stop` で終了し、`verified=true` を返しました。応答は `restore-stop.json` にあります。以降は、プロジェクト確認を伴うネイティブの停止処理で状態を戻しました。今回試した状態では、成功した再生コマンドを繰り返してもトグル動作にはなりません。

## ネイティブ送信の検証表

生データ: `Research/raw/20261001-appleevent-dynamic/native-results-final.json`（最終コードでの再実行）。最初の検証表は `native-results.json` に残しています。
すべてのケースで `AESendMessage` のステータスは0です。ハンドラーの結果は、応答の `errn` パラメータから別に読み取りました。整数パラメータのディスクリプタ型は `long`（符号付き32ビット）、文字列の対照ケースは `utxt` です。

| ケース | 変更した入力 | 応答 errn | 読み戻し playing | 期待結果の検証 |
|---|---|---:|---|---|
| 未知のイベント ID | `aUeV/ZZzz` | -1708 | false | 一致 |
| 未知のイベントクラス | `ZZzz/Spt2` | -1708 | false | 一致 |
| mode がない | `sPmo` なし | -1701 | false | 一致 |
| mode の型が違う | `sPmo=utxt:"6"` | 0 | false | 一致。成功扱いだが何も変更しない |
| key がない | `sPkc` なし、`sPmo=6` | -1701 | false | 一致 |
| key の型が違う | `sPkc=utxt:"-3"` | 0 | false | 一致。成功扱いだが何も変更しない |
| key が0 | `sPkc=0` | 0 | false | 一致。成功扱いだが何も変更しない |
| 直接指定の再生1 | `sPkc=-3` | 0 | true | 一致 |
| 再生中に再生 | `sPkc=-3` | 0 | true | 一致 |
| 直接指定の停止1 | `sPkc=-5` | 0 | false | 一致 |
| 直接指定の再生2 | `sPkc=-3` | 0 | true | 一致 |
| 直接指定の停止2 | `sPkc=-5` | 0 | false | 一致 |
| マッピング経由の再生 | `sPkc=11` | 0 | true | 一致 |
| マッピング経由の停止 | `sPkc=1` | 0 | false | 一致 |

各ケースは、比較対象のケースから1条件だけを変えています。イベントの前後でトランスポートを確認しました。ネイティブの検証表では14件すべてが期待どおりで、最後は停止、録音オフでした。完全な応答、対象 PID、ディスクリプタ、標準エラー、コマンドの引数列は生データの JSON に残しています。

負の対照実験の結果は、Apple の [`errAEEventNotHandled`](https://developer.apple.com/documentation/coreservices/erraeeventnothandled) の定義と一致します。インストール済み SDK の `CarbonCore.framework/Headers/MacErrors.h` にも、`errAEEventNotHandled=-1708` と `fnOpnErr=-38` が定義されています。

## 入力と動作を結び付ける静的解析の根拠

インストール済みバイナリと、Ghidra で解析したコピーの SHA-256 は同じです。
`2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998`。

ハンドラー登録、型を適用した Ghidra エクスポート、状態チェック、mode、正のマッピング表は `Research/static-analysis/appleevent-registration.md` を参照してください。独立して確認した `DfDocument` の再生・停止・録音の呼び出し箇所と正確な命令列は `Research/static-analysis/appleevent-command-dispatch.md` にあります。

逆コンパイルと ARM64 命令から確認した mode 6 の動作を、簡略化して示します。

```c
if (activeOwner == NULL || activeOwner->currentSong == NULL)
    return -38;

mode = read_exact_long_parameter(event, 'sPmo');
if (mode == 6) {
    key = read_exact_long_parameter(event, 'sPkc');
    if (key < 0)
        command = (int16_t)(0u - (uint32_t)key);
    else if (key >= 1 && key <= 14)
        command = positive_key_table[key];
    else
        return 0;  // 何も変更しない
    dispatch_command(command, currentSong, 0, 2, 0);
    return 0;      // ディスパッチャーの結果は送信元へ返されない
}
```

この疑似コードは、厳密な API エラー・型の分岐と、ほかの mode を省略しています。特に、実際の型チェックでは、ディスクリプタの型が違うとコマンドを実行せずに0を返す場合があります。ネイティブの検証表でも確認できました。負の値は16ビットへ縮小されるため、製品のアダプターでは任意の負の int32 を受け入れず、入力を検証する必要があります。

## 再現手順

専用テストプロジェクトを開き、`/Users/nagataharuto/logicpro cli` で実行します。

```sh
swiftc Tools/research-scripts/appleevent_probe.swift -o .build/appleevent-probe

# 既定は dry-run。送信せずに予定のケースを確認する。
python3 Tools/research-scripts/appleevent_experiments.py matrix \
  --project '/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx'

# 範囲を限定した検証表を送信し、独立して状態を読み戻して停止へ戻す。
python3 Tools/research-scripts/appleevent_experiments.py matrix --send \
  --project '/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx'

# 個別に使えるネイティブ操作。MCU で検証する。
python3 Tools/research-scripts/appleevent_experiments.py play --send \
  --project '/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx'
python3 Tools/research-scripts/appleevent_experiments.py stop --send \
  --project '/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx'
```

ネイティブ送信ツールは、バンドル情報から実行中のアプリを探すか、`--app` / `--bundle-id` を受け取ります。対象を PID で指定し、開いているドキュメントが1つだけで、その正規化したパスがテストプロジェクトと一致することを確認します。リンク先が別名のシンボリックリンクも拒否します。

生の応答だけでは常に `verified=false` です。実験用ラッパーは、期待した応答と独立した MCU の状態が一致したときだけ `verified=true` にします。状態を戻す際も同じプロジェクト確認を使います。録音状態または読み戻しの確認が失敗した場合は失敗を記録し、確認なしに別のプロジェクトへ書き込むことはありません。

Ghidra のエクスポートは、ハッシュを確認する読み取り専用ラッパーで再現できます。

```sh
bash Tools/ghidra/appleevents.sh \
  '/Applications/Logic Pro Creator Studio.app'
```

既存の `Logic.arm64` 解析を再利用し、メモリ上で AppleEvent API の型を修正します。SDK の正確な型と ABI に正規化した型の両方で逆コンパイル結果を出し、owner の相互参照もエクスポートします。データベースの変更は破棄します。インストール済みアプリは読み取るだけです。

## 利用上の限界と次の実験

- このビルドとテストプロジェクトでは、再生と停止を動的に検証できました。
- 静的解析では、`sPkc=-7` は `DfDocument::recordCallback` と同じコマンド ID に到達します。録音イベントは送っておらず、動的には未検証です。
- mode 4 の応答経路には `sPsr`、`sPfr`、`sPso` が含まれますが、テンポデータを変更し得る関数も呼びます。副作用の全体が分かるまでは、純粋な状態取得として公開しないでください。実機では試していません。
- mode 7–14 とファイル／リージョンの分岐には、実機で試す前に追加の静的解析が必要です。この FourCC からミキサー、プラグイン、トラック選択、シークの意味が分かったとは主張していません。
- EXP-AE-001 の調査時点では、製品の `Sources/` は変更していませんでした。任意で選ぶ AppleEvent トランスポートのバックエンドは、確認済みの入力を再利用しつつ、独立した状態検証を維持できます。この実験では MCU が検証を担っています。その後の製品統合は [EXP-AE-002](EXP-AE-002-cli-backend.md) に記録しています。
