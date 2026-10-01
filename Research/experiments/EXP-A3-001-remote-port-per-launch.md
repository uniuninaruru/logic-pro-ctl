[日本語](EXP-A3-001-remote-port-per-launch.md) | [English](EXP-A3-001-remote-port-per-launch.en.md)

# EXP-A3-001: Logic を再起動すると Logic Remote の TCP ポートは変わるか

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-01 13:25 JST |
| Logic バージョン | 12.3.1 (6682) |
| macOS バージョン | 27.0 (26A5416b) |
| Logic Remote バージョン | 該当なし（クライアント未接続） |
| テストプロジェクト | ~/Music/Logic/LogicCLI-Test.logicx |
| 初期状態 | Logic PID 25338（12:34:39 起動）、TCP *:51463、UDP *:7000、`_apple-lgremote._tcp` インスタンス `174jnk4ko0l8w` |
| 1つの操作 | Logic を終了（Logic Pro > 終了）し、`open -a … LogicCLI-Test.logicx` を実行 |
| 期待する変化 | 先行調査では TCP ポートが起動ごとにランダムになるとされる |
| 再現回数 | 再起動1回 |

## 観察

| 項目 | 前 | 後 |
|---|---|---|
| PID | 25338 | 37546 |
| TCP 待ち受け（IPv4+IPv6） | 51463 | 52476 |
| UDP | 7000 | 7000 |
| `_apple-lgremote._tcp` インスタンス | 174jnk4ko0l8w | 08n2x7g7zvtu4 |

起動から3秒以内に待ち受けソケットが現れました。
生データ: `Research/raw/*-exp-a3-001-before/`、`Research/raw/*-exp-a3-001-after/`。

## 仮説（Hypothesis）

仮説: TCP ポートと Bonjour インスタンス名（ピア ID）は起動ごとに生成し直され、UDP 7000 は固定です。
確信度: 「TCP ポートは固定ではない」は高（直接の反例を確認）。「毎回ランダム」は中（n=1）。「7000 は固定」は中（起動2回分。設定可能な OSC ポートかもしれません）。
根拠: 上の表。
反例: なし。
次の検証実験: さらに2回再起動し、コントロールサーフェス設定で OSC ポートを変更できるか確認します。

## logicctl への影響

Remote バックエンドは接続時に Bonjour で `_apple-lgremote._tcp` を解決する必要があります。ポートをキャッシュして使い回してはいけません。
