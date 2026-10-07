[日本語](SA-GUI-COMMAND-001.md) | [English](SA-GUI-COMMAND-001.en.md)

# SA-GUI-COMMAND-001：命令payloadとキーコマンド画面への移動

既存の小さな2関数を命令列と照合しました。メニュー関連候補の一方は、
登録項目のpointerを受け取り、キーコマンド画面の対応項目へ移動する経路です。
右クリックのどの操作がこの経路を選ぶかは、実機ではまだ確認していません。

- 2関数720 B・180命令と、既存9呼び出し箇所のbytesを現行バイナリ・解析copyと照合し、不一致は0件。
- 命令IDと内部の項目pointerは別です。pointerを要求するhelperへIDを渡せません。
- payloadのSongID解決と、feature判定の実引数・実戻り値を確認。逆コンパイルの疑似Cは、この流れを一部落としています。
- ContextMenuCreatorとControllerAssignmentsからの静的な呼び出しはありますが、GUIの条件やMIDI割当経路の証明ではありません。

詳細は[英語の記録](SA-GUI-COMMAND-001.en.md)、[機械可読表](../protocol/gui-command-navigation-boundaries.tsv)、[関数・命令・hashのmanifest](gui-command-navigation-manifest.json)にまとめています。
次は[GUI調査計画](../plans/PLAN-GUI-001.en.md)に沿って、画面で観測した操作に対応する関数へ絞ります。CLIの対応機能を追加した結果ではありません。
