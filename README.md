# logicctl — Logic Pro をコマンドで操作する

**日本語** · [English](README.en.md)

Logic Pro の再生・停止やミキサー操作を、ターミナルやAIエージェントから行うためのCLIです。
**操作したあとにLogicの状態を読み返し、合っていたかをJSONで返します。**

```mermaid
flowchart LR
    A[あなた・AIエージェント] --> B[logicctl<br/>コマンドを受け付ける]
    B --> C[logicd<br/>Logicとの接続を保つ]
    C --> D[Logic Pro]
    D -->|実際の状態| C
    C -->|結果のJSON| B
```

## まず使う

macOS 13以降・Swift 5.9以降が必要です。検証した環境は **Logic Pro 12.3.1 / build 6682、macOS 27.0** です。

```sh
swift build -c release
.build/release/logicctl status
.build/release/logicctl track list
```

`status` でLogicの起動と接続を確認し、`track list` で操作したい番号・名前を確認します。
`logicd` は最初の利用時に自動起動します。仮想MIDIポート `logicctl-mcu` はLogicが自動で検出します。

```sh
.build/release/logicctl transport play
.build/release/logicctl transport stop
.build/release/logicctl track volume 1 -6
```

## 何ができる？

| やりたいこと | コマンド例 | メモ |
|---|---|---|
| 接続を確認 | `logicctl status` | Logicのバージョン・接続状態・対応機能 |
| 全体の状態を見る | `logicctl state` | 再生状態・選択中のトラック・一覧 |
| 再生 / 停止 | `logicctl transport play` / `stop` | 通常はMCU経由 |
| トラック一覧 / 詳細 | `logicctl track list` / `get 1` | 番号は1から |
| 選択 | `logicctl track select 1` | 自動録音待機の設定により録音待機も移動 |
| ミュート / ソロ | `logicctl track mute 1 on` / `solo 1 off` | `on`・`off`で指定 |
| 音量 | `logicctl track volume 1 -6` | dBで指定。無音は `-inf` |
| パン | `logicctl track pan 1 -0.5` | 左 `-1` ← 中央 `0` → 右 `1` |
| 常駐プロセスを停止 | `logicctl daemon stop` | 次の利用で再起動 |

音量の許容差は既定で0.1 dBです。例：`track volume 1 -6 --tolerance 0.2`。
`--json` はどこに置いても使えます。指定がなくても出力はJSONです。

### 再生・停止をAppleEventで送る

```sh
.build/release/logicctl transport play --backend appleevent
.build/release/logicctl transport stop --backend appleevent
```

| 経路 | 指定 | 操作できる範囲 | 結果の確認 |
|---|---|---|---|
| MCU：仮想MIDIのコントロールサーフェス | 省略、または `--backend mcu` | 上の通常コマンド | LogicからのLED・フェーダー・表示の応答 |
| AppleEvent：macOSのアプリ間メッセージ | `--backend appleevent` | **再生・停止のみ** | **MCUの応答で確認** |

AppleEvent経路は **12.3.1 / 6682だけ**で有効です。MCUの接続も必要です。
指定した経路で失敗した場合は、その結果を返します。送信を自動で繰り返しません。

古い `logicd` が動いていると `daemon_upgrade_required` を返します。
新しいビルドで `logicctl daemon stop` を実行してから、元のコマンドを再実行してください。

## 結果をどう読む？

```json
{
  "ok": true,
  "verified": true,
  "command": "transport.play",
  "backend": "appleevent",
  "readback_backend": "mcu",
  "requested": {"playing": true},
  "observed": {"playing": true, "recording": false}
}
```

| フィールド | 意味 |
|---|---|
| `ok` | コマンドが成功したか |
| `verified` | 書き込み後の状態を読み返し、要求と一致したか |
| `requested` | こちらが求めた状態 |
| `observed` | Logicから確認できた状態 |
| `backend` / `readback_backend` | 操作に使った経路 / 検証に使った経路 |
| `error` / `message` | エラーの識別子 / 日本語の説明 |

**送信成功だけでは `verified: true` になりません。** 状態が不明なら、確認できていない結果として返します。
読み取りだけのコマンドは、正常でも `verified: false` です。
AppleEventの再生・停止は、既に要求どおりなら送信を省略します。`result.sent: false` で確認できます。

終了コードは `0`：成功、`1`：操作・検証・接続の失敗、`64`：CLIの書式・オプションの誤りです。詳しくは[仕様](docs/specification.md)。

## 使う前に知っておくこと

- トラック番号は **Logicのミキサー上のチャンネルストリップ順**です。Stereo OutやMasterも含みます。
- MCUの名前は最大6文字・ASCII中心です。日本語の名前はそのまま取得できません。
- 音量の確認はLogicの表示に合わせて0.1 dB単位です。間の値は、より細かく確認できません。
- ソロ中は、点滅するミュートLEDから状態を断定できず `mute: null` になることがあります。
- 選択や操作のあと、表示が戻るまで数秒待つことがあります。Undoで戻した名前は、再接続まで古い場合があります。
- Undoのミキサー設定により変更履歴が異なり、近い操作がまとまる場合があります。戻したい値は先に記録してください。
- 純粋なネイティブ状態取得、Logic Remoteの独自接続、プラグイン操作は調査中です。

## 仕組みと調査を読む

| 読みたいこと | 入口 |
|---|---|
| コマンド・JSON・エラーの仕様 | [やさしい仕様](docs/specification.md) |
| どの部品が何をする？ | [図で読むアーキテクチャ](docs/architecture.md) |
| どこまで分かった？ 次に何を調べる？ | [調査ガイド](Research/README.md) |
| 接続経路の根拠 | [詳しいアーキテクチャ調査](Research/architecture.md) |
| AppleEventの実機結果 | [EXP-AE-001](Research/experiments/EXP-AE-001-private-command-dispatch.md)・[EXP-AE-002](Research/experiments/EXP-AE-002-cli-backend.md) |
| ネイティブ状態取得の候補と制約 | [SA-AE-STATE-002](Research/static-analysis/SA-AE-STATE-002-native-transport-state.md) |

## 開発・検証

```sh
./scripts/test.sh
swift build -c release
python3 Tests/integration/test_cli_backend_compat.py .build/release/logicctl
python3 Tools/research-scripts/test_fourcc_scan.py
```

製品コードは `Sources/`、調査記録は `Research/`、調査ツールは `Tools/` にあります。
実機での開発・実験には専用の `LogicCLI-Test.logicx` を使います。[開発ルール](AGENTS.md)。
Ghidra解析は、API登録・名前付きメソッド・メッセージを起点に進め、静的な根拠と実機結果を区別して記録します。

daemonのログ：`~/Library/Logs/logicctl/logicd.log`。
環境変数 `LOGICD_PATH` でdaemonの実行ファイル、`LOGICCTL_SOCKET` で接続先を指定できます。
調査用の生MIDI送信は `logicctl debug mcu <hex>[; <hex>…]` です。

## ライセンス

MIT。[LICENSE](LICENSE)を参照してください。
