# SA-001: Logic Control.bundle（MCU プラグイン）の初回 Ghidra 解析

[日本語](SA-001-logic-control-bundle.md) | [English](SA-001-logic-control-bundle.en.md)

| 項目 | 内容 |
|---|---|
| 日付 | 2026-10-01 |
| バイナリ | `Logic Pro Creator Studio.app/Contents/PlugIns/MIDI Device Plug-ins/Logic Control.bundle/Contents/MacOS/Logic Control`（universal x86_64+arm64、765,040 bytes。arm64 スライスを解析） |
| Logic | 12.3.1（6682）。bundle id は `com.apple.music.apps.midi.device.plugin.Logic-Control` |
| ツール | Ghidra 12.1.4 headless。`Tools/ghidra/analyze.sh` → `Research/raw/ghidra/`（逆コンパイルした Apple のコードはコミットしない） |
| 結果 | 142 関数、すべて逆コンパイル済み |

## プラグイン ABI（公開シンボル `nm -gU -arch arm64` より）

各コントロールサーフェス・プラグインで共通の C エントリーポイントは、
`init_dd`、`scan`、`init_dev`、`deinit_dev`、`transfer`、`get_midi`、`peri`、
`CSDefault`、`CSFeedback`、`CSGroupClassForModel`、`CSLabelSize`、`ModID`、
`Version`、`MinHostVersion`、`NameForModel`、`ManufNameForModel`、
`ManufIDForModel`、`FlagsForModel`。Logic Remote.bundle と TouchOSC.bundle も
同じ主要な関数群を公開している。

Logic Control は、さらに `CSTemplate`、`CSLabel`、`CSLongLabel`、
`CSFeedbackText`、`CSLongFeedbackText`、`CSRefresh`、`CSAlert`、
`CSActivating`、`CSEndOffscreen`、`CSFaderDBConversionTable`、
`ScanAllModels`、`SpecialInfo`、`TimerCallback` を公開する。

削除されていない C++ のシンボル名から、ホスト側のデータモデルが見える。

- `DDESCR_LC::CSFeedback(TControlID, long, long, long, AssignFeedbackType, long, AssignHeader const*)`
- `DDESCR_LC::FillTemplate(Assign*, TControlID, unsigned char) const`
- `DDESCR_LC::CSFeedbackText(TControlID, char const*, int, int)`
- `DDESCR_LC::DoHostConnectionQuery(ScanMode)`、`scan(char, ScanMode, char const*, char const*)`

プラグインは Logic の framework から何もインポートしていない（`nm -u`）。
このため、ホストが `init_dd` / `scan` 時にコールバックやデータ構造を渡す
必要がある。受け渡しの詳細はまだ追跡していない。

**Hypothesis（仮説）:** `Assign` / `AssignHeader` / `TControlID` は、
Logic のコントローラ割り当てモデルであり、すべてのコントロールサーフェス
（MCU、Logic Remote、TouchOSC、Lua スクリプト、Controller Assignments）で
共通に使われる。共通のコマンド・状態表現の候補になる（brief §16）。
確信度は中（型名のみが根拠）。次は `FillTemplate` と `CSFeedback` を
逆コンパイルして `Assign` のレイアウトを復元し、Logic Remote.bundle と比較する。

## CSFaderDBConversionTable

一度だけ（`__cxa_guard`）35 要素のテーブルを作る。各要素は 64-bit の
フェーダー値と、32-bit の 16.16 固定小数点 dB 値。テーブルは
`FUN_00000b5c(&table, 0x23)` に渡される。

| value | dB | | value | dB |
|---|---|---|---|---|
| 0 | -144 | | 7177 | -12 |
| 192 | -70 | | 7602 | -10 |
| 457 | -60 | | 8084 | -9.1667 |
| 695 | -57.5 | | 8553 | -8.3333 |
| 994 | -55 | | 9017 | -7.5 |
| 1234 | -52.5 | | 9485 | -6.6667 |
| 1446 | -50 | | 9970 | -5.8333 |
| 1753 | -47.5 | | 10450 | -5 |
| 2027 | -45 | | 12441 | 0 |
| 2285 | -42.5 | | 14459 | 5 |
| 2564 | -40 | | 14939 | 6.25 |
| 2797 | -37.5 | | 15440 | 7.5 |
| 3058 | -35 | | 15904 | 8.75 |
| 3567 | -32.5 | | 16380 | 10 |
| 3990 | -30 | | | |
| 4416 | -26.6667 | | | |
| 4912 | -23.3333 | | | |
| 5293 | -20 | | | |
| 5771 | -18 | | | |
| 6256 | -16 | | | |
| 6701 | -14 | | | |

動的測定（EXP-MCU-009、`Research/protocol/mcu-fader-calibration.tsv`）との比較では、
このテーブルを線形補間し、小数第 1 位に丸めた値が、Logic の LCD 表示と
**58/58 点**で一致した。

**確認済み:** MCU フェーダー値から dB への変換は、このテーブルの線形補間。
チャンネルストリップでは +6.0 dB（値は約 14843）で上限に達する。

反映先: `Sources/LogicCore/Backends/MCU/FaderCalibration.swift` はこのテーブルを
使用している。変更後の実機確認では、トラック 1 の -6 / -3.7 / -12 / -30 / 0 dB を
すべて検証できた（フェーダー値は 9874、10969、7178、3990、12443）。
