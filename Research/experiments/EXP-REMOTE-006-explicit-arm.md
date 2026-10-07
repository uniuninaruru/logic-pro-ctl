[日本語](EXP-REMOTE-006-explicit-arm.md) | [English](EXP-REMOTE-006-explicit-arm.en.md)

# EXP-REMOTE-006: 明示の録音待機を 1 回だけ変えたときの `r` と MCU の REC LED（PLAN-05 E4、方法 B）

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-07 13:04〜13:14（JST） |
| Logic | 12.3.1 (6682)、macOS 27.0、arm64。専用 `LogicCLI-Test.logicx`、停止中、音は出していない |
| 承認 | ユーザーがチャットで直接「全て許可」。画面の操作による復元はチャットで直接許可（「画面を 10 秒ほど使ってよい」） |
| 初期状態 | 14 本、選択は Ballad（自動の録音待機：`r` 3、MCU の REC LED 点灯）、Synth は `r` 0 |
| 1つの操作 | `logicctl track arm 2 on --expect-name Synth`（MCU の REC を 1 回押す、04:05:00.312Z） |
| 受信 | 研究用ピア 1 回、`20261007-130449-e1`、7,762 フレーム、`receive_window_over` |
| 生の記録 | `Research/raw/live-arm/e4-arm/`（操作の時刻・JSON）、logicd のトレース（Git の対象外） |

## 観察

- **Remote**：押したあと、Synth の `r` は **128（0x80）と 1 を約 0.73 秒ごとに交互**に取り、`/gtFaderData` は反転のたびに再送された。Ballad の `r` は 3 → 0。`/cs/mixer/record/2` も 1/0 で点滅、`record/3` は 0。`/sti` は変わらなかった。
- **MCU**：Ballad の REC LED は押してから 0.11 秒で消え、Synth の REC LED は 0.86 秒後に初めて点き、その後 7F/00 を約 0.73 秒ごとに繰り返した（点滅）。押したのは 1 回。
- logicd は 0.8 秒待って LED を読んだので「消えている」と判断し、**`verification_failed` を返した**（実際には録音待機になっていた）。
- 復元：MCU で REC をもう一度押す（04:08:23.151Z）と、**解除されず**、0.32 秒後に選択 LED が Synth に移った。`track select 3` で Ballad に戻したが自動の録音待機は戻らず、画面の R を裏から押す（AXPress）のも効かなかった。ユーザーの許可で画面を使い、R を実際にクリックして解除（途中で誤って S を押し、すぐ戻した）。Ballad の自動の録音待機は画面では戻ったが、MCU の Ballad の REC LED は報告されず、logicd の `state` は false のまま。

## 仮説（Hypothesis）

仮説（Hypothesis）: **`r` の 1 と 128 は、同じ明示の録音待機の点滅の 2 つの位相**（SA-REMOTE-STATE-001 §8.3 の予測どおり。`0x261e118` は点滅の位相）。
確信度: 高（受信で 0.73 秒ごとの交互を観察、MCU の LED の点滅と同じ周期）。
反例: 録音中（点滅しない）に別の値になる。

仮説（Hypothesis）: 録音待機の点滅中のトラックの MCU の REC を押すと、解除ではなく選択が移ることがある。
確信度: 低（1 回）。EXP-MCU-028 では MCU で解除できていた。
次の検証実験: 選択されていないトラックで、録音待機→解除を MCU だけで 2 回繰り返す（復元の手段を先に用意する）。

## 製品への含意

- `track arm` の確認を、点滅を前提にした：始めの状態を 1 回の点滅の窓（1.6 秒）で決め、押したあとは窓の中で「点」の報告が 1 回でもあれば録音待機、窓のあいだ「点」が無く消えていれば解除。`track get`／`state` の `rec_armed` も、窓の中で点いていれば true（偽の Logic の試験 `aBlinkingRecLEDCountsAsArmed` など）。実機での再確認は、上の解除の問題を確かめてから。
- Remote で録音待機を読むときは、`r` の 1 と 128 を同じ「明示の録音待機」とみなす。3 は選択に付いてくる自動の録音待機、64 は録音待機できないトラック。
