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
- logicd は仮想ポートの固有 ID（CoreMIDI の `kMIDIPropertyUniqueID`）を設定していないので、起動ごとに新しい ID になる。16:30 の再起動のあと、設定ファイル（Logic が 16:30Z に書き直した）には、新しい送信側・受信側の ID がそれぞれ 1 回ずつ現れ、「logicctl-mcu」の文字列は 80 個から 82 個に、ファイルは 200 バイト増えた（値そのものは記録しない）。
- 10-04 の走査（EXP-MCU-027）は 12 本・`bank_steps: 4` で正しかった。10-04 15:57Z から 10-06 16:03Z の間、logicd は起動していない。
- 修正後の logicd（16:30:01Z 起動）：`status` は `mcu.surface_conflict: true`。`state` と `track list` は `surface_conflict` で断られ、ボタンは何も押されなかった。
- 生の記録：`Research/raw/mcu-two-units/`（トレース・診断・JSON）、`Research/raw/live-arm/e4-arm/`（16:21 の `state`）。Git の追跡対象外。

## 仮説（Hypothesis）

仮説（Hypothesis）: **Logic は `logicctl-mcu` に Mackie Control を 2 台つないでいて、2 台目が 1 台目の右隣（位置 9〜16）を表示する。** 2 台とも同じ番号の LED と同じ LCD の書き込みを同じポートに送るので、logicd の LCD は最後に書いた方の名前になる。14 本の曲は 2 台で全部表示できるので、Channel Right も Bank Right も何も起きず、走査は「端に着いた」と判断する。
確信度: 高。
根拠: 内容の違う 2 つの全面の書き込み（2 回とも）、名前が位置 9〜14 と一致、設定ファイルの「Mackie Control #2」、Bank Left の無反応。
反例: 2 台目を外しても 2 種類の書き込みが続くなら、別の原因がある。
次の検証実験: ユーザーが設定で「Mackie Control #2」を外したあと（あるいは外してよいと言ったあと）、logicd を再起動して、ダンプが 1 種類・`surface_conflict: false`・`state` が 14 本・`bank_steps` 6 になるかを確かめる。ダンプの判定は `LOGICD_TRACE=1` で logicd を起動し、`python3 Tools/research-scripts/mcu_trace.py dumps ~/Library/Logs/logicctl/logicd.log --since <再起動の時刻>` が「one unit」になることで見る（今夜の 2 回のダンプは「2 units suspected」、10-02 の 1 台のトレースは「one unit」と出る）。

仮説（Hypothesis）: Logic は装置のポートを固有 ID でも覚えていて、logicd が起動するたびに新しい ID の記録が増える。これが 2 台目の追加に関わったかもしれない。
確信度: 低。
根拠: 再起動のたびに設定ファイルが増え、新しい ID が入る（1 回）。ただし文字列の数（82）は、このログにある logicd の起動回数（15）と合わない（調査用の道具も同じポート名を使っていた）。
反例: 固有 ID を固定しても 2 台目が加わる。
次の検証実験: 固有 ID を固定する版の logicd。ただし、試すとさらに装置が加わるおそれがあり、外すにはユーザーの許可が要るので、ユーザーと相談してから。

静的な参考（機械語で確認、[アンカー表](../protocol/logic-cs-autoinstall-anchors.tsv) 34 行）: Logic にはコントロールサーフェスの自動インストールの切り替え（`CSM_006_AutoInstall`、`FUN_00ad6130`）がある。状態の問い合わせ（mode 2）は、内部のバイト `0x26b52cf` の bit 1 が 0 のとき「オン」を返し、このバイトは一度だけの初期化で 0 になる。切り替え（mode 0）でオンに戻すときは `FUN_00a7b48c(0)` と `FUN_00a7e3ac` を呼ぶ（走査の開始と推定）。設定ファイルからこのバイトが読み込まれるかは読んでいない。

仮説（Hypothesis）: 自動インストールが有効なまま、Logic の装置探し（logicd の接続時に、0x10・0x11・0x14・0x15・0x17 の機種へ問い合わせが来ていた）が logicd の返事を新しい装置と見なし、「Mackie Control #2」を加えた。
確信度: 低（仕組みの候補があるだけで、加わった瞬間は見ていない）。
次の検証実験: 自動インストールの経路（`FUN_00a7b48c`・`FUN_00a7e3ac` から装置を加える所）を静的に読む。

仮説（Hypothesis）: 2 台目は 10-04 以降に加わった。いつ・何が加えたか（Logic の自動の装置探し、研究用ピアを登録したときの設定画面の操作など）は分からない。
確信度: 低。
根拠: 10-04 の走査は 1 台の動き。
次の検証実験: なし（設定ファイルに履歴は無い）。外したあとに再び現れるかを見る。

## 製品への含意

- 「Channel Right と Bank Right がどちらも無反応なら端」という判定は、**装置が 1 台**であることを前提にしていた。2 台目があると、偽の `complete: true` を返す。
- logicd は、全面の書き込みが**空でない別の名前の行の上に**（ハンドシェイクを挟まずに）書かれたら矛盾と数え、最新の書き込みの窓（1 秒）に矛盾があれば `surface_conflict` として、`status` と調査用の `debug mcu` 以外をすべて断る。ハンドシェイクで画面は空になるので、1 台が名前を変えて送り直すだけ（名前の変更のあとの再接続）は矛盾にならない。コマンドの**実行の後にも**確かめ、途中で 2 台目のダンプが来たら、読み取りの結果は捨て、書き込みは「届いたかもしれない、確かめられない」として `surface_conflict` にする（Codex の独立レビューの指摘 3 件を受けた修正）。トランスポートの読み戻し（他の経路が使う）も同じく断る。テスト：`Tests/LogicCoreTests/SurfaceConflictTests.swift`。実トレースでは、2 台目の書き込み（16:23:59.254・16:30:01.169）が矛盾として数えられ、10-02 の 1 台のトレースは矛盾 0（`mcu_trace.py`）。
- 1 台目の 8 本だけを使う、2 台目を拡張として扱う、といった回避はしていない。LED と LCD の通り道が 2 台で共有されているため。
- 検出の限界：検出は「2 台がいっしょにダンプを送る」ことに頼っている（logicd がポートを作り直したときは、2 回ともそうだった）。logicd が動いている間に 2 台目が加わり、2 台目だけがダンプを送った場合や、2 台の書き込みの間にハンドシェイクが挟まった場合は、1 台が接続をやり直したのと区別できず、検出できないおそれがある（未確認）。疑わしいときは `logicctl daemon stop` で logicd を再起動すれば、2 台そろったダンプで判定し直せる。曲の切り替えでも内容の違うダンプが来るため、「接続の前後で名前が違う」を条件にはしていない。
- 後確認の限界：実行の後の確認は結果を捨てるだけで、走査の途中で 2 台目のダンプが来ても、走査そのもの（バンクの移動）は最後まで続く。バンクの移動は曲を変えないが、Logic の画面の表示範囲は動きうる（EXP-MCU-023）。
- 誤検出のおそれ：1 台でも、ハンドシェイクを挟まずに、表示中の名前と違う全面の書き込みが届けば（曲の切り替えでそうなるかは未確認。トレースはまだ無い）、`surface_conflict` になる。その場合も読み書きを断るだけで、`logicctl daemon stop` のあとの新しいダンプで解ける。

## 解決（2026-10-07 13:01 JST）

ユーザーがチャットで直接「Claude が外してよい」と答えたので、設定ファイル 2 つの写しを `Research/raw/cs-backup-20261007T035749Z/`（SHA-256 付き、Git の対象外）に取ってから、「コントロールサーフェス設定」で **Mackie Control #2 だけ**を削除した（元の Mackie Control と研究用ピアは残した）。logicd をトレース付きで再起動（04:02:03Z）すると、ダンプは 1 種類（`mcu_trace.py`：one unit、矛盾 0）、`status` は `surface_conflict: false`、`state` は **14 本・complete・`bank_steps` 6**（1=Piano … 14=Master、選択は Ballad）。仮説 1 と、次の検証実験の予測どおり。

解決のあと、保留していた `transport cycle|click on|off` を実機で確かめた（停止中、音なし）：cycle off→（もう一度 off は送らずに確認）→on、click off→on がすべて `verified: true`。off のとき画面のサイクルとメトロノームのボタンが消灯し、on で点灯した。生の記録：`Research/raw/mcu-cycle-click/live-cycle-click.jsonl`。
