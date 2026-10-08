[日本語](onboarding-rdco-001.md) | [English](onboarding-rdco-001.en.md)

# RDCO さんへ：このプロジェクトの進め方と、今までに分かったこと

宛先：RDCO（ChatGPT、Remote Desktop Commander 経由）。書き手：Claude（Logic の画面操作と実機の実験の担当）。日付：2026-10-08。Logic は 12.4（ビルド 6707）。
**目的は、Logic Pro に汎用のプログラム可能な窓口を作ること**（CLI、MCP、将来は SDK から同じ核を使う）。機能の数より、信頼できる読み戻しを優先する。

## 1. 担当と作法

| 参加者 | 主な担当 |
|---|---|
| Codex | 静的解析、Swift の製品コード（`logicctl`・`logicd`・MCP）、資料の整理と公開、`cs_assignments.py` |
| Claude | Logic の画面操作と実機の実験、実験記録（`Research/experiments/EXP-*`） |
| RDCO | 必要なときに、独立した確認・調査・レビュー（担当の範囲は連絡帳で決める） |

**2026-10-08 から、Codex が全体のリーダー**（ユーザーの指示）。作業の割り当て・優先順位・担当の衝突は Codex が決め、Claude と RDCO は連絡帳の Codex の指示に従う。ユーザーが直接出した指示は、常に最優先。Codex が先に書いた案内（連絡帳の `CDEX118`）も合わせて読む。

- 連絡帳は `chatgpt-claude.md`（Git の対象外）。`python3 Tools/research-scripts/board_new.py --reader rdco` で未読だけ読める（名前は半角の英数字、`-`、`_`）。**1 回に 1,000 文字で切れるので、「続きあり」と出る間は繰り返す。本文は、ファイルから全文読む。見出しだけ、先頭だけで済ませない。** 操作の前に必ず読む（「止めて」「担当を取る」の連絡を見落とすと、実験が重なって結果が無効になる。実際に起きた）。
- 担当のファイルとリソース（Logic の画面、MIDI、Ghidra、ビルド）は、連絡帳で先に宣言する。黙っていることは許可ではない。
- 連絡は短い英語と ID が基本。ユーザーへの説明は日本語。
- Git：先に `git fetch`。自分のファイルだけを、パスを明示してコミットする（`git add -A`、`git commit -a`、`stash`、`reset`、強制 push は使わない）。他の人のファイルを直さない。`Research/raw/` は Git の対象外。生ログ・機器名・ユーザー名・パス・UUID・ロケールはコミットしない。表には件数だけ書く。

## 2. 守ること（AGENTS.md の要点）

- 操作してよいのは専用テストプロジェクト `LogicCLI-Test.logicx` だけ。ウインドウの題名が「LogicCLI-Test」のときだけ操作する。曲の切り替え、閉じる、保存はしない。
- 再生を始めない。音が出る操作をしない（ユーザーが授業中などのことがある）。
- Logic の実行ファイルの変更、SIP、コード署名、`sudo` は、理由を説明して許可を得るまで行わない。設定ファイル `com.apple.logic.pro.cs` へ**直接書き込まない**（Apple も、設定の変更は Logic の中で行うものとしている）。
- 持続する設定の変更（ピックアップモードなど）は、ユーザーが直接許可したものだけ。戻す。
- 製品コード（`Sources/`）は `Research/` と `Tools/` に依存させない。CLI は標準出力に JSON、標準エラーに診断。書き込みは必ず読み戻して確認し、読めなければ `verified: false`。
- 実験は 1 回に 1 条件だけ変える。観察（根拠のファイル付き）と、仮説（確信度付き）を分ける。
- **GUI や機能の操作は、先に Apple の公式ガイドを読む**（`support.apple.com/ja-jp/guide/logicpro/...`。ガイドは 12.3 まで。12.4 の挙動は実機で確かめ、どちらの記述か区別する）。英語版と日本語版で食い違うことがある（例：`Lo7` を含まないメッセージの受信値が、日本語版は 0、英語版は 1）。

## 3. 状態を 3 つに分ける（最重要）

「MIDI を送った」「Logic に割り当てられた」「値が実際に変わった」は別の事実。結果には、段階ごとに確認の状態を持たせる。
- **トグル型のコマンドは自動で再送しない。** ループブラウザは、0 以外の CC を受けるたびに開閉する。再試行が状態を元に戻すことがある。
- 読み戻せない値は `verified: false` と書く。

## 4. 今までに分かったこと（記録へのリンク）

- MCU（Mackie Control）の経路で、トラック一覧・音量・パン・ミュート・ソロ・選択・録音待機・トランスポートを読み書きできる。`logicctl`、`logicd`、`docs/` を参照。
- 汎用 MIDI の割り当て：
  - [EXP-CA-001](../experiments/EXP-CA-001-generic-cc-fixed-message.md)：1 つの値だけで学習した行は「固定メッセージ」で、同じメッセージを受けるたびに現在値へ 1 を足す（「回転」モード）。
  - [EXP-CA-002](../experiments/EXP-CA-002-variable-cc-and-pickup.md)・[EXP-CA-003](../experiments/EXP-CA-003-value-mode-pickup-ab.md)：**値を変えて複数送って学習すると `Lo7` の行になる。** パン、音量、Channel EQ の Master Gain を動かせた。「選択したトラック」に追従する。ピックアップモードがオンだと、対象を切り替えた直後は、現在値に一致するか、またぐまで無視される。
  - フィードバック（Logic から MIDI を返す）は、汎用の入力ポートでは、1 形式・1 回の試行では確認できていない。
- キーコマンド：[EXP-KC-001](../experiments/EXP-KC-001-key-command-inventory.md)（12.4 の一覧。27 グループ・2,176 件）、[EXP-KC-002](../experiments/EXP-KC-002-midi-to-key-command-loop-browser.md)（MIDI の CC をキーコマンドに登録して実行できる）。
- 設定ファイル：[EXP-CS-001](../experiments/EXP-CS-001-prefs-file-live-diff.md)（Logic を終了しなくても書き換わる。割り当て 1 件は `RDAF` レコード 1 つ。**有効な複製かどうかは、見出しの長さの欄で確かめる**）。
- ノートの入力（ステップ入力、速さ）：[EXP-MIDI-032](../experiments/EXP-MIDI-032-controller-note-input.en.md)・[EXP-MIDI-033](../experiments/EXP-MIDI-033-step-region-edit.en.md)（Codex）。
- 外部の参考実装 `koltyj/logic-pro-mcp` のレビュー：[logic-pro-mcp-reference-001](logic-pro-mcp-reference-001.en.md)。

## 5. 画面操作で起きた失敗（繰り返さないために）

- 手前のアプリが Logic でないまま、クリックと文字入力を送ってしまい、別のアプリ（ChatGPT）に入った。**操作の前に、手前のアプリを確認する**（`lsappinfo info -only name "$(lsappinfo front)"`）。画面全体を操作するバッチは、最初の画面確認とは別の呼び出しで始める。
- 背景のまま文字を入力すると、別の場所（一覧）に入る。ウインドウが重なっているとき、座標でのクリックは上のウインドウに当たる。**ボタンは、要素の番号で押す**（`AXPress`）。
- ⌘K は 12.4 では「ミュージックタイピング」を開く（文字キーで音が鳴りうる）。ウインドウはメニューから開く。
- 「メッセージを登録」を、行を選んだまま押すと、選択行の再登録ではなく**新しい行**ができる。
- ループブラウザを開くと、ライブラリのパネルが隠れて戻らない。
- 学習は、値を 1 つしか送らないと固定メッセージになる。複数の値を 0.4 秒おきに送る。

## 6. 道具

- `python3 Tools/research-scripts/board_new.py --reader rdco`：連絡帳の未読。
- `.build/out/Products/Debug/logicctl`：CLI（`logicctl --help`）。`logicd` は必要なとき自動で起動する。ビルドの置き場は共有なので、使う前に連絡帳で知らせる。
- `Tools/research-scripts/mcu-probe.swift`（仮想 MIDI ポート。`MIDI_PORT=名前` で名前を変える）、`mcu_trace.py`、`midi-note-probe.swift`、`cs_assignments.py`（Codex、読み取り専用）、`logic-plugin-inspect.swift`（Codex、画面の読み取りだけ）。
- Ghidra は共有。`Tools/ghidra/with-project-lock.py` の鍵を通す。

## 7. RDCO さんに頼みたいこと（最初の候補。連絡帳で合意してから）

1. **読み取りだけの確認**：Logic の公式ガイド（日本語・英語・12.3）と、`EXP-CA-*`・`EXP-KC-*`・`EXP-CS-001` の記述を突き合わせ、食い違いや根拠の足りない主張を、ファイルとして報告する（`Research/notes/` に新しいファイルを作る。既存のファイルは直さない）。
2. **読み戻しの調べ**（観察だけ）：プラグインのウインドウの値を、画面のアクセシビリティから読めるか。Codex の `logic-plugin-inspect.swift` と重ならないよう、先に連絡帳で分担する。
3. **Python の整形**：GitHub の Pylint が、`Tools/research-scripts/*.py` に出す指摘を一覧にする（直すのは、持ち主と合意してから）。

質問は連絡帳に書いてください。Claude と Codex は、通常の確認のときに答えます。
