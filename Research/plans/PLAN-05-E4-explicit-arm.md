# PLAN-05 E4: 明示の録音待機を 1 回だけ変えて、Remote の `r` を確かめる

[日本語](PLAN-05-E4-explicit-arm.md) · [English](PLAN-05-E4-explicit-arm.en.md) · [E3 の計画](PLAN-05-E3-manual-selection.md) · [E3 の結果](../experiments/EXP-REMOTE-004-selection-delta.md)

**目的は、選択を変えずに、選択されていないトラックの録音待機だけを 1 回変えたとき、`/gtFaderData` の `r` と `/cs/mixer/record/N` がどう動くかを見ることです。** E3 では、選択の変更に伴って自動の録音待機が移り、`r` の 3 が移りました（EXP-REMOTE-004）。明示の録音待機がどの値になるかは、まだ見ていません。

| 項目 | 内容 |
|---|---|
| 状態 | 計画のみ。2026-10-07 の夜は実行していない（MCU は同じポートの 2 台目で使えず（[EXP-MCU-029](../experiments/EXP-MCU-029-two-units-on-one-port.md)）、画面はロックされていた） |
| 承認 | ユーザーがチャットで直接「全て許可」（実機の使用・E3 のような実験の再試行）。専用曲だけ、元に戻せる操作だけ |
| プロジェクト | 専用 `LogicCLI-Test.logicx` のみ。停止中。保存しない |
| 接続 | 研究用ピア `logicctl-research-peer` を 1 回（e0 で広告名を確かめ、e1 で 120 秒）。初期送信は `/protocolVersion=10` と `/jsonSupport=1` だけ。**同時に動かすピアは 1 つだけ**（ボードで担当を決める） |
| 変える条件 | Synth（位置 2、選択されていないソフトウェア音源）の録音待機を **1 回だけ**オンにする。方法は次のどちらか 1 つ：**A. 画面のトラック・ヘッダーの R をクリック**（MCU なしでできる）、**B. `logicctl track arm 2 on --expect-name Synth`**（2 台目を外し、`surface_conflict: false` を確かめてから） |
| 変えない条件 | 選択（Ballad のまま）、ミュート・ソロ・音量、他のトラックの録音待機、曲 |
| 保存先 | `Research/raw/remote-recv/<日時>-e1/`（受信）、`Research/raw/live-arm/e4-arm/` または `e4ui-arm/`（操作の時刻・画面の確認） |

## 予測（静的解析から。[SA-REMOTE-STATE-001 §8.3](../static-analysis/SA-REMOTE-STATE-001.md)）

| 見るもの | 予測 | 確信度 |
|---|---|---|
| Synth の `r` | 0 から変わる。値は **1**、または点滅の位相によって **0x80**（ソフトウェア音源は「*k* が負」の未読の経路を通るので、値は決め切れない） | 低 |
| Ballad の `r` | MCU では、Ballad の自動の録音待機が外れた（EXP-MCU-028）。A で同じことが起きれば 3 → 0、起きなければ 3 のまま。どちらでも記録する | 低 |
| `/cs/mixer/record/2` | 1 になる（Remote の 8 枠の表示。`bankLeftOffset` が 0 なら枠 2 が Synth、という仮説） | 中 |
| `/sti` | 変わらない（選択を変えないため） | 中 |
| `ip` | 0 のまま（`_BgTrackInfoIndependentPanKey`。入力モニタリングではない） | 中 |

## 手順

1. 画面で専用曲・停止中・選択が Ballad・Synth の R が消灯、を確かめ、時刻と一緒に記録する。B のときは `logicctl status` で `surface_conflict: false` も確かめる。
2. 受信の担当が `run.sh e0 --seconds 8` で広告名を確かめ、`run.sh e1 --seconds 120 --target <広告名>` を始める。`/ati`・`/sti`・`/gtFaderData` の受信を確かめたら、ボードに「記録準備完了」と書く。三つが届かなければ、何もせず終える。
3. 操作の担当が、直前の UTC を記録し、A または B を **1 回だけ**行い、直後の UTC を記録する。B は `verified` と JSON を保存する。画面で Synth の R が点いた（点滅）ことを、点滅の消えた瞬間に注意して確かめる。
4. 約 30 秒待ってから、受信の担当が STOP する（時間切れでもよい）。
5. 受信の終了後に、別の操作として元に戻す：Synth の録音待機をオフにする（A ならもう一度 R、B なら `track arm 2 off`）。Ballad の自動の録音待機が外れていれば、選択を Synth → Ballad と移して戻す（EXP-MCU-028 と同じ）。戻した時刻と画面を記録する。
6. 読み方：`remote_state.py timeline <run> --from <操作の前のフレーム>` で、`/cs/mixer/record|select/N`・`/sti`・`/gtFaderData` の到着順を並べる。`remote_state.py replay` で前後の `r`・`ip`・`control_surface_view` を比べる。中止した E4（何もしなかった 120 秒）を、変化の無い対照に使う。

## 中止する条件

- 題名が「LogicCLI-Test」でない、別の曲が開いている、再生中、画面がロックされている。
- 受信の担当と操作の担当が決まっていない、または別のピアが動いている。
- B で `surface_conflict` が true、`target_mismatch`、`session_changed` のどれか。
