[日本語](README.md) | [English](README.en.md)

# 研究用ピア（Logic Remote の受信専用）

PLAN-05 の承認範囲（[承認用の計画書](../../Research/plans/PLAN-05-approval-brief.md)）で使う、小さな macOS アプリです。初期2通の後は**受信だけ**を行い、製品（`Sources/`）には入っていません。前回の結果は [EXP-REMOTE-001](../../Research/experiments/EXP-REMOTE-001-receive-initial-state.md)。受信中の手動選択を追加する場合は [E3-1 の計画](../../Research/plans/PLAN-05-E3-manual-selection.md) の範囲を確認します。

| 段階 | すること | 送るもの |
|---|---|---|
| `e0` | `apple-lgremote` の広告を探して記録する。招待しない | なし |
| `e1` | 自分の名前（既定 `logicctl-research-peer`）で招待する。人が Logic のダイアログで「接続」を押す。接続と初期2送信の成功後、`--seconds` の間（最大 120 秒）受信する | `/protocolVersion = 10` と `/jsonSupport = 1` の 2 通だけ（各 1 回）。それ以外を送ろうとすると停止する |

```sh
Tools/remote-research-peer/build.sh                       # ビルドだけ。起動・接続しない
Tools/remote-research-peer/test.sh                        # 実lifecycleの8ケース。通信しない
Tools/remote-research-peer/run.sh e0 --seconds 15
Tools/remote-research-peer/run.sh e1 --seconds 60 --target "<e0 で見つかった名前>"
touch Research/raw/remote-recv/<日時>-e1/STOP              # 途中で止める
python3 Tools/research-scripts/remote_capture.py report Research/raw/remote-recv/<日時>-e1
```

出力は `Research/raw/remote-recv/<日時>-<段階>/`（Git の追跡対象外）：`events.jsonl`（時刻つきの出来事）、`frames/NNNN.bin`（受信したデータそのまま）、`decoded.jsonl`（製品の `RemoteFrameParser` で復号した結果）、`summary.json`。`run.sh` は毎回、自作の研究用 app をビルドし直し、Swift 入力2ファイルと builder の hash がビルド前後の二時点で一致することを確認します。`build-inputs-before.json` と `build-provenance.json` に、その入力・署名後 executable・Info.plist・runner の SHA-256、サイズ、compiler version を残します。前後の値が異なる場合は起動しません。ビルド中ずっと不変だったことを保証する検査ではありません。`--out` と `--stage` は wrapper が管理し、追加引数による上書きを拒否します。

## 終了と記録の読み方

- すべての通信 callback、終了処理、受信記録は main の直列キューで扱います。終了状態を確定してから切断し、後で処理される callback は送信・記録を行いません。終了後の証明書 callback には `false` を返します。STOP ファイルは0.5秒間隔で確認するため、ファイル作成そのものと停止の確定は同時ではありません。
- `sent` は送信 API がエラーを返さなかった1通です。`sent_initial: true` は2通ともこの条件を満たした意味で、Logic の受理や ACK を保証しません。直列化または送信が失敗すれば `send_failed` を記録し、`initial_send_failed`・`exit_code: 2` で終了します。受信 window へは進みません。
- `receive_window` の時刻から `--seconds` を数えます。baseline の受信や人の操作待ちもこの時間に含みます。起動全体の120秒制限ではなく、広告待ち・接続待ちは前にあります。baseline や操作 marker はピアの自動機能ではありません。
- summary の `exit_code` がピアの終了結果です。`run.sh` は summary が無い・壊れている場合に2、ピアの終了結果が非0ならその値を返します。`open -W` の終了状態だけではピアの成功を判定しません。終了結果0でも、baseline が揃ったことや実験の成功を意味しません。

2026-10-05 の整備では、native peer を作らないオフラインビルドで、本番と同じ lifecycle gate・初期2送信手順・frame 直列化を fake transport/recorder と実行し、8ケースを確認しました。終了フラグと成功カウントをそれぞれ壊したコピーでは試験が失敗しました。native の callback 配信や実際の通信は、この検証には含めていません。

## 注意

- **既存の Logic Remote 端末と同じ名前は使わない**（確認ダイアログを避けるなりすましになる）。
- 「接続」を押すと、Logic はこの名前を**コントロールサーフェスの装置として登録**し、設定に残る（`com.apple.mobilelogic` の `ControlSurfaceDevicesDict`、`com.apple.logic.pro.cs`）。削除は Logic の「コントロールサーフェス設定」から行う想定（未実施）。
- 実験は専用プロジェクト `LogicCLI-Test.logicx` だけを開いた状態で行う。
- 署名は自分のアドホック署名（`codesign -s -`）。Logic や他のアプリの署名は変えない。
