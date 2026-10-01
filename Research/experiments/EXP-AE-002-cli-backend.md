[日本語](EXP-AE-002-cli-backend.md) | [English](EXP-AE-002-cli-backend.en.md)

# EXP-AE-002: 製品 CLI の AppleEvent トランスポートと MCU による読み戻し

| 項目 | 内容 |
|---|---|
| 日時 | 2026-10-01、Asia/Tokyo。最初の実機検証は18:30:46 JST開始、統合後の再検証は22:28:19 JST開始 |
| Logic バージョン | Creator Studio 12.3.1 (6682)、実行中の PID 37546 |
| macOS バージョン | 27.0 (26A5416b)、arm64。EXP-AE-001 と同じ環境 |
| 選択した開発ツール | `/Applications/Xcode.app/Contents/Developer`。この統合ビルドには完全な Xcode を使用可能 |
| Logic Remote バージョン | 該当なし |
| テストプロジェクト | `/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx` |
| 初期状態 | `playing=false`、`recording=false`。スクリプティング上のドキュメントは1つだけ |
| 1つの操作 | 各ケースで `transport play` または `transport stop` の要求を1回。AppleEvent を明示的に選択 |
| 期待する変化 | MCU の応答で要求した再生／停止状態と一致し、recording=false を維持 |
| 再現回数 | ネイティブの再生／停止2組、再生の変更なし1回、停止の変更なし1回。比較用 MCU 操作1組 |
| 最終状態 | `playing=false`、`recording=false` |

## 確認できた結果

製品の Swift CLI／デーモン経路で、ネイティブの AppleEvent による再生・停止を実行し、MCU バックエンドで独立して状態を検証できるようになりました。[EXP-AE-001](EXP-AE-001-private-command-dispatch.md) で確認したイベントを製品へ統合した成果です。ネイティブの状態取得 API を確認したわけではありません。製品の `Sources/` は、実行時に `Research/`、`Tools/`、Python、`osascript` に依存しません。

実装の根拠: `Sources/LogicCore/Backends/AppleEvent/AppleEventTransportBackend.swift`、`Sources/LogicCore/Backends/MCU/MCUBackend.swift`、`Sources/logicctl/main.swift`。
テストの根拠: `Tests/LogicCoreTests/AppleEventBackendTests.swift`、`Tests/integration/test_cli_backend_compat.py`。

ネイティブバックエンドが許可するのは Logic 12.3.1／ビルド6682と、内部コマンド3（再生）・5（停止）だけです。イベントは `aUeV/Spt2`、パラメータは符号付き int32 の `sPmo=6` と `sPkc=-3/-5` です。実行中の PID を対象にし、読み戻しの準備中に Logic が再起動していないことも確認します。操作前のトランスポート状態が欠けている、または不明な場合は書き込みを拒否します。初期化時の LED 既定値は観測として扱いません。

## 実機での観察と根拠

生データは意図的に Git の追跡対象から除外しています。
`Research/raw/20261001T093046Z-appleevent-cli/preflight.json` と `live.json`。

旧デーモン PID 63565 の status は成功しましたが、AppleEvent 対応の能力情報がありませんでした。AppleEvent を明示した停止は終了コード1、`error=daemon_upgrade_required`、`verified=false` を返しました。CLI は対応確認の段階で戻り、トランスポート要求を送信しません。後述の模擬ソケットによる独立した記録でも、この旧形式の経路で状態変更を送らないことを検証しています。

旧デーモンを停止した後、リリース版 CLI はデーモン PID 6853 を起動しました。最初の status は新しい能力情報を公開しましたが、MCU がまだ未接続だったためトランスポート状態を含みませんでした。次の status で MCU の接続と両トランスポート LED の状態が確定してから、実機操作を始めました。

各トランスポート書き込みの前には、標準スクリプティングで、同じドキュメントが1つだけ開いており、そのパスがテストプロジェクトと完全に一致することを確認しました。ネイティブの書き込み自体は、AppleScript を使わず `AESendMessage` で送ります。実際の音楽制作プロジェクト、録音コマンド、シーク、ミキサー、プラグイン操作は試していません。

| 生データのケース名 | コマンド／バックエンド | 操作前 → 観測した playing | 送信 | 結果 |
|---|---|---|---|---|
| `native_stop_noop` | stop/appleevent | false → false | false | verified=true、recording=false |
| `native_play_1` | play/appleevent | false → true | true | verified=true、recording=false |
| `native_play_noop` | play/appleevent | true → true | false | verified=true、recording=false |
| `native_stop_1` | stop/appleevent | true → false | true | verified=true、recording=false |
| `native_play_2` | play/appleevent | false → true | true | verified=true、recording=false |
| `native_stop_2` | stop/appleevent | true → false | true | verified=true、recording=false |
| `default_mcu_play` | play/既定 MCU | false → true | MCU 書き込み | verified=true、recording=false |
| `explicit_mcu_stop` | stop/明示 MCU | true → false | MCU 書き込み | verified=true、recording=false |

実際に送信したネイティブ操作4回は、すべて `appleevent_send_status=0` で、有効な AppleEvent 応答を受信しました。**応答に `errn` はありませんでした**。これは `appleevent_reply_error=null` と表します。「エラーフィールドの値0を観測した」という意味ではありません。送信成功、エラーパラメータを含まない有効な応答、MCU の一致する状態がそろえば成功とします。変更不要だった2回は何も送信せず、AppleEvent のステータス・応答フィールドはすべて null でした。停止を繰り返すと再生ヘッドが動く場合があるため、不要な Stop は送信しません。

実機の再生応答例です。要求 ID と無関係なメタデータは省略しています。

```json
{
  "command": "transport.play",
  "backend": "appleevent",
  "readback_backend": "mcu",
  "ok": true,
  "verified": true,
  "requested": {"playing": true},
  "observed": {"playing": true, "recording": false},
  "result": {
    "sent": true,
    "command_id": 3,
    "event_class": "aUeV",
    "event_id": "Spt2",
    "appleevent_send_status": 0,
    "appleevent_reply_received": true,
    "appleevent_reply_error": null,
    "logic_version": "12.3.1",
    "logic_build": "6682",
    "target_pid": 37546
  }
}
```

`final_status` で、デーモンが接続を維持し、再生・録音がともに false だったことを確認しました。この段階ではネットワーク／IPC のパケットキャプチャはしていません。根拠は、記録した CLI の要求・応答、ドキュメント確認、独立した MCU 状態と、後述のソケット記録テストです。

### 最終統合ビルドでの再検証

コミット `373f9ea`（前セッションのサーフェスデータを破棄）を取り込んだ後、22:28 JSTに最終リリースビルドで同じ8ケースを繰り返し、すべて成功しました。
根拠: `Research/raw/20261001T132819Z-appleevent-cli-merged/results.json`。
デーモン PID 16655 は、同じ Logic PID 37546 を対象にしました。デーモン再起動後の最初の `track list` も、空でない12個のストリップ名を返しました。
ネイティブの再生／停止2組は、いずれもステータス0、`errn` のない有効な応答、MCU の状態一致を確認しました。変更不要なネイティブ操作2回は何も送信しませんでした。最終状態は再び playing=false、recording=false。Logic 自体は再起動していません。

セッションのクリア時には、内部のトランスポート LED 基準値も記録します。継続中のカウンターによって、クリアされた既定の消灯状態がスナップショット経由で観測済みと扱われることはありません。両 LED を再び受信する必要があります。デーモンは引き続き、PID／世代、同じ受信バッチの応答、新しい LCD データを確認します。

以前の再検証準備では、AppleScript のアプリ対象を変数で指定したところ、Logic のドキュメントの `path` プロパティを解決できず（`-1728`）、ドキュメント確認で停止しました。デーモン再起動もトランスポート書き込みも行っていません。以下の再現手順では、検出して検証したバンドル ID を使って確認用スクリプトをコンパイルします。

最終的なハッシュ確認付き Ghidra エクスポートも完了しました。
`Research/raw/20261001T093700Z-ghidra-appleevents-hashguard/headless.log` に、期待したプログラムの SHA-256、エクスポート成功、`Discarding changes ... /Logic.arm64` が記録されています。固定の解析起点を使う前に、インストール済みバイナリ、単体のインポート元コピー、Ghidra プログラムのメタデータを確認します。

## 自動検証（実機で試した範囲とは区別）

最終統合後の Swift テストは**52件すべて成功**し、`swift build -c release` も成功しました。注入した送信処理・読み戻し処理で、Logic や LED 状態を取得できない場合、未知のバージョン／ビルド、プロセスの置き換え、状態が偶然一致していても送信／応答エラーがある場合、応答後に状態が変わらない場合、Stop 後も録音が続く場合、欠落・不正な応答、非同期の応答、キャッシュ状態／PID の回帰ケースを検証しています。ディスクリプタのテストでは、イベントを送信せず、実際のイベントの PID と int32 パラメータ型を調べます。

ビルド済み CLI は、分離した模擬 Unix ソケットに対する**8プロセステスト／23ケース**に成功しました。実際の要求を記録し、以下を確認します。

- 能力情報が旧形式、欠落、false、型違いの場合は、旧形式の status 要求だけを送ります。能力確認の status が失敗した場合も、書き込みを拒否します。
- 対応が確認できた明示的な再生・停止では、能力確認と同じ接続上で `backend: appleevent` の状態変更を1回だけ送ります。
- 応答のバックエンドが違う・欠けている場合や AppleEvent の失敗が報告された場合は、再試行も MCU への切り替えもせず、エラーにします。
- 既定の MCU は `backend` フィールドを含まない旧形式の要求を送ります。MCU を明示した場合は AppleEvent の能力確認を省きます。
- 無効なバックエンド／コマンド引数は、ソケットに接続する前に終了コード64を返します。

これらのテストでは、存在しない `LOGICD_PATH` と短い非公開の `/tmp` ソケットを使います。実デーモンを起動したり、Logic にイベントを送ったりすることはできません。権限拒否、送信タイムアウト、読み戻し不能、未対応バージョン、置き換わったプロセスの失敗は模擬ケースであり、**実機で再現したものではありません**。

## 再現手順

リポジトリで、Logic を操作しないビルドと検証を実行します。

```sh
./scripts/test.sh
swift build -c release
python3 Tests/integration/test_cli_backend_compat.py .build/release/logicctl
```

実機の一連の操作では、専用テストプロジェクトだけを開きます。以下は、すべてのトランスポート要求の前にドキュメント数・名前・パスを確認し、CLI の status からバンドル ID を検出し、最後に再生を停止します。このドキュメント確認は実験用のガードで、製品バックエンドの一部ではありません。

```python
import json
from pathlib import Path
import re
import subprocess

cli = str(Path(".build/release/logicctl").resolve())
project = "/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx"

def ctl(*args):
    completed = subprocess.run([cli, *args], text=True, capture_output=True,
                               timeout=20, check=True)
    return json.loads(completed.stdout)

def guarded_transport(action, backend):
    state = ctl("status")
    bundle_id = state["result"]["logic"]["bundle_id"]
    assert re.fullmatch(r"[A-Za-z0-9.-]+", bundle_id)
    assert state["result"]["transport"]["recording"] is False
    # 検出したアプリの用語辞書でコンパイルする。アプリを変数で指定すると、
    # コンパイル時に Logic のドキュメントのプロパティを解決できない。
    script = f'''tell application id "{bundle_id}"
        with timeout of 10 seconds
            return {{count of documents, name of document 1, path of document 1}}
        end timeout
    end tell'''
    guard = subprocess.run(["/usr/bin/osascript", "-e", script],
                           text=True, capture_output=True, timeout=15, check=True)
    assert guard.stdout.strip() == f"1, LogicCLI-Test, {project}"
    args = ["transport", action]
    if backend is not None:
        args += ["--backend", backend]
    result = ctl(*args)
    assert result["verified"] and not result["observed"]["recording"]
    print(json.dumps(result, sort_keys=True))

# status に capabilities がなければ旧デーモンを停止し、status を再実行して
# 新しいリリースデーモンを起動してから、この一連の操作を実行する。
guarded_transport("stop", "appleevent")
guarded_transport("play", "appleevent")
guarded_transport("play", "appleevent")
guarded_transport("stop", "appleevent")
guarded_transport("play", "appleevent")
guarded_transport("stop", "appleevent")
guarded_transport("play", None)
guarded_transport("stop", "mcu")
assert ctl("status")["result"]["transport"] == {
    "playing": False, "recording": False
}
```

## 仮説と未解決事項

**仮説（Hypothesis）:** 外部から呼べる読み取り専用のトランスポート状態取得入口が見つかれば、確認済みのネイティブ書き込みイベントを変えずに、MCU の読み戻しを置き換えられる可能性があります。
**確信度:** そのような外部入口と応答スキーマが特定されるまでは低です。根拠は既存の内部状態・応答経路に限られます。内部の getter が見つかっただけでは、CLI から呼べるとはいえません。

バージョンをまたぐ互換性、ネイティブの録音動作、純粋なネイティブのトランスポート状態取得は、いずれも確認できていません。mode 4 はテンポを書き込む分岐が未解決なので、読み取り専用の status API としては使えません。この成果は、要求を繰り返した際の再生ヘッド位置の安定性や、状態の読み戻し一致を超える時間保証も示しません。

**次の検証実験:** Logic Remote のトランスポート状態のシリアライズと外部メッセージ入口を静的解析し、正確な呼び出し箇所とスキーマを記録します。その後、候補の問い合わせを1つだけ専用プロジェクトで試し、独立した MCU 状態と照合します。副作用と繰り返し時の応答を確認するまでは、その問い合わせを公開したり、読み取り専用と主張したりしないでください。

## 日本語のCLI案内の確認

日本語化後のリリースビルドでも、Swift 52件とCLIプロセステスト8件／23ケースが通りました。
`Research/raw/20261001T135229Z-japanese-cli/results.json` では、`--help` が日本語の案内を標準エラーに出すこと、未知の経路が終了コード64と `error: "usage"`・日本語の `message` を返すことを確認しました。JSONのキー・コマンド名・エラー識別子は固定のままです。

専用プロジェクトを確認して日本語版のデーモン（PID 22345）を起動し、AppleEventの停止要求が「既に要求どおりの状態です。送信していません。」と `sent: false`・`verified: true` を返しました。この確認ではトランスポートイベントを送っていません。最終状態は引き続き再生・録音ともにfalseです。
