[日本語](README.md) | [English](README.en.md)

# 研究用ピア（Logic Remote の受信専用）

PLAN-05 の承認範囲（[承認用の計画書](../../Research/plans/PLAN-05-approval-brief.md)）で使う、**受信だけ**の小さな macOS アプリです。製品（`Sources/`）には入っていません。結果は [EXP-REMOTE-001](../../Research/experiments/EXP-REMOTE-001-receive-initial-state.md)。

| 段階 | すること | 送るもの |
|---|---|---|
| `e0` | `apple-lgremote` の広告を探して記録する。招待しない | なし |
| `e1` | 自分の名前（既定 `logicctl-research-peer`）で招待する。人が Logic のダイアログで「接続」を押す。接続したら `--seconds` の間（最大 120 秒）受信する | `/protocolVersion = 10` と `/jsonSupport` の 2 通だけ（各 1 回）。それ以外を送ろうとすると停止する |

```sh
Tools/remote-research-peer/build.sh                       # .build/remote-research-peer/LogicctlResearchPeer.app
Tools/remote-research-peer/run.sh e0 --seconds 15
Tools/remote-research-peer/run.sh e1 --seconds 60 --target "<e0 で見つかった名前>"
touch Research/raw/remote-recv/<日時>-e1/STOP              # 途中で止める
python3 Tools/research-scripts/remote_capture.py report Research/raw/remote-recv/<日時>-e1
```

出力は `Research/raw/remote-recv/<日時>-<段階>/`（Git の追跡対象外）：`events.jsonl`（時刻つきの出来事）、`frames/NNNN.bin`（受信したデータそのまま）、`decoded.jsonl`（製品の `RemoteFrameParser` で復号した結果）、`summary.json`。

## 注意

- **既存の Logic Remote 端末と同じ名前は使わない**（確認ダイアログを避けるなりすましになる）。
- 「接続」を押すと、Logic はこの名前を**コントロールサーフェスの装置として登録**し、設定に残る（`com.apple.mobilelogic` の `ControlSurfaceDevicesDict`、`com.apple.logic.pro.cs`）。削除は Logic の「コントロールサーフェス設定」から行う想定（未実施）。
- 実験は専用プロジェクト `LogicCLI-Test.logicx` だけを開いた状態で行う。
- 署名は自分のアドホック署名（`codesign -s -`）。Logic や他のアプリの署名は変えない。
