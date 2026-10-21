[日本語](EXP-CA-005-first-cc-after-launch.md) | [English](EXP-CA-005-first-cc-after-launch.en.md)

# EXP-CA-005：Logic 起動後の最初の CC 23 は無視されるか（判定不能：ポートが Mackie Control と重なっていた）

詳細は [英語版](EXP-CA-005-first-cc-after-launch.en.md)。

- 日時：2026-10-21 08:53–08:58 JST。Logic 12.4（6707）、新規プロジェクト「名称未設定 6」（ユーザー承認、保存なし）。トラック Ballad、Channel EQ の Master Gain は AX 値 240（0.0 dB）、ピックアップ ON。
- 操作：既存の CC 23 → Master Gain の行の入力ポート `logicctl-cc` から、60・66・64 を 1 つずつ送り、約 1.5 秒後に AX で読んだ。
- 結果：どれも変化なし。66 で反映されるという予測は外れた。割り当て画面を開いて送ると、メッセージは Mackie Control の「VPots」ゾーンの「VPot 8」（対象「フェーダーバンク 8」のフェーダー、入力 `logicctl-cc`）に一致した。直後に Logic は Mackie の LCD 更新を返した。
- 解釈（仮説、確信度：高）：10 月 8 日以降に、同じポート名に Mackie Control のサーフェスが入り、その VPot 8 が CC 23 を先に受け取っている。トラックが 1 本なので何も変わらない。起動直後のリセットの予測は未検証のまま。
- 生データ（Git 対象外）：`Research/raw/ca005/`、`Research/raw/cs-diff/s3.bin`。
