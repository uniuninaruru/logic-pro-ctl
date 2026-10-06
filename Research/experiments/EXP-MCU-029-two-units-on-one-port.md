[日本語](EXP-MCU-029-two-units-on-one-port.md) | [English](EXP-MCU-029-two-units-on-one-port.en.md)

# EXP-MCU-029: 同じポートに Mackie Control が 2 台 — LCD が混ざり、走査が偽の complete を返す

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-07 01:20〜01:31（JST） |
| Logic バージョン | 12.3.1 (6682) |
| macOS バージョン | 27.0、arm64 |
| Logic Remote バージョン | 該当なし（直前に研究用ピアの受信 PLAN-05 E3 があった。この実験の間は接続なし） |
| テストプロジェクト | LogicCLI-Test.logicx（ウインドウの題名を画面で確認） |
| 初期状態 | 停止中。選択は Ballad（3）。曲は 14 本（Remote の `/ati` と画面。出力と Master を含む） |
| 1つの操作 | 曲を変える操作はしていない。MCU の読み取り、Bank Left を 1 回、フェーダーのタッチ、logicd の再起動（MIDI のトレース付き）を 2 回 |
| 期待する変化 | `state` が 14 本を返す |
| 再現回数 | 偽の complete：3 回（EXP-MCU-028 の 2 回と今回 1 回）。2 種類の画面のダンプ：2 回（16:23:59Z・16:30:01Z） |
| 承認 | 実機の使用はユーザーがこのチャットで直接「全て許可」。Logic の設定は読むだけ（変更していない） |

## 観察

- `logicctl state`（16:21:01Z）は `ok: true`・`complete: true`・**6 本**・`bank_steps: 0` を返し、名前は 1=Trk07・2=Trk06・3=Trk05・4=Trk09・5=St Out・6=Master だった。画面では 1=Piano・2=Synth・3=Ballad。EXP-MCU-028 の `state`（16:03Z・16:05Z）は**8 本**（Piano〜Trk10）で complete だった。どちらも 14 本の一部。
- `logicctl debug mcu`：LCD の名前の行は位置 9〜14 の名前、LED の選択と REC は 3 番目の枠（位置 1〜8 の表示なら Ballad）。Bank Left を押しても、3 秒待っても LCD は変わらなかった。
- logicd をトレース付きで再起動すると、接続直後のダンプで Logic は**内容の違う全面の LCD の書き込み**（オフセット 0、111 バイト）を同じポートに送った。2 回の再起動で同じ順序だった：

  | 時刻（UTC） | 名前の行 |
  |---|---|
  | 16:23:59.216 / 16:30:01.127 | Piano Synth Ballad Trk08 Audio AmpdUp Bass Trk10（位置 1〜8） |
  | 16:23:59.254 / 16:30:01.169 | Trk07 Trk06 Trk05 Trk09 St Out Master（位置 9〜14） |
  | 16:23:59.318 / 16:30:01.243 | Piano Synth Ballad Trk08 Audio AmpdUp Bass Trk10（位置 1〜8） |

  1 台だった 10-02 のトレース（EXP-MCU-024）では、ダンプの全面の書き込みは**同じ内容が 2 回**だった。
- Logic のコントロールサーフェスの設定ファイルを**読むだけ**で調べると（写しを作業用の場所に取り、文字列だけを数えた）、「Control Surface: Mackie Control」「Control Surface: Mackie Control #2」「Control Surface: logicctl-research-peer」の 3 つの装置の記述があった。
- 10-04 の走査（EXP-MCU-027）は 12 本・`bank_steps: 4` で正しかった。10-04 15:57Z から 10-06 16:03Z の間、logicd は起動していない。
- 修正後の logicd（16:30:01Z 起動）：`status` は `mcu.surface_conflict: true`。`state` と `track list` は `surface_conflict` で断られ、ボタンは何も押されなかった。
- 生の記録：`Research/raw/mcu-two-units/`（トレース・診断・JSON）、`Research/raw/live-arm/e4-arm/`（16:21 の `state`）。Git の追跡対象外。

## 仮説（Hypothesis）

仮説（Hypothesis）: **Logic は `logicctl-mcu` に Mackie Control を 2 台つないでいて、2 台目が 1 台目の右隣（位置 9〜16）を表示する。** 2 台とも同じ番号の LED と同じ LCD の書き込みを同じポートに送るので、logicd の LCD は最後に書いた方の名前になる。14 本の曲は 2 台で全部表示できるので、Channel Right も Bank Right も何も起きず、走査は「端に着いた」と判断する。
確信度: 高。
根拠: 内容の違う 2 つの全面の書き込み（2 回とも）、名前が位置 9〜14 と一致、設定ファイルの「Mackie Control #2」、Bank Left の無反応。
反例: 2 台目を外しても 2 種類の書き込みが続くなら、別の原因がある。
次の検証実験: ユーザーが設定で「Mackie Control #2」を外したあと（あるいは外してよいと言ったあと）、logicd を再起動して、ダンプが 1 種類・`surface_conflict: false`・`state` が 14 本・`bank_steps` 6 になるかを確かめる。

仮説（Hypothesis）: 2 台目は 10-04 以降に加わった。いつ・何が加えたか（Logic の自動の装置探し、研究用ピアを登録したときの設定画面の操作など）は分からない。
確信度: 低。
根拠: 10-04 の走査は 1 台の動き。
次の検証実験: なし（設定ファイルに履歴は無い）。外したあとに再び現れるかを見る。

## 製品への含意

- 「Channel Right と Bank Right がどちらも無反応なら端」という判定は、**装置が 1 台**であることを前提にしていた。2 台目があると、偽の `complete: true` を返す。
- logicd は、接続時のダンプ（1 秒以内の全面の書き込み）に違う名前の行が 2 つ以上あれば `surface_conflict` として、`status` と調査用の `debug mcu` 以外をすべて断る。テスト：`Tests/LogicCoreTests/SurfaceConflictTests.swift`。
- 1 台目の 8 本だけを使う、2 台目を拡張として扱う、といった回避はしていない。LED と LCD の通り道が 2 台で共有されているため。
- 検出の限界：検出は「2 台がいっしょにダンプを送る」ことに頼っている（logicd がポートを作り直したときは、2 回ともそうだった）。logicd が動いている間に 2 台目が加わり、2 台目だけがダンプを送った場合は、1 台が接続をやり直したのと区別できず、検出できないおそれがある（未確認）。疑わしいときは `logicctl daemon stop` で logicd を再起動すれば、2 台そろったダンプで判定し直せる。曲の切り替えでも内容の違うダンプが来るため、「接続の前後で名前が違う」を条件にはしていない。
