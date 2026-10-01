# Logic Pro の外部操作経路 — 調査構成図

[日本語](architecture.md) | [English](architecture.en.md)

「確認済み」には観測した事実だけを記す。各事実には根拠を添える。
根拠は `Research/raw/<run>/` の実行記録（gitignore 対象）、
`Research/static-analysis/` のコミット対象ファイル、または結果を得たコマンド。

これまでの実行: `20261001-130602`（discover.sh）、`20261001-131349-a2`、
`20261001-131833-a2`（discover2.sh）。いずれも同じ Logic プロセス
（pid 25338。実行間に再起動していない）が対象。

現在の製品コードの構成は [docs/architecture.md](../docs/architecture.md) を参照。
この文書には、未採用・未検証の調査候補も含まれる。

## 1. 環境

| 項目 | 値 | 根拠 |
|---|---|---|
| macOS | 27.0（26A5416b）、Darwin 27.0.0、arm64（T8142） | `sw_vers`、`uname -a` |
| アプリ | /Applications/Logic Pro Creator Studio.app | `ls /Applications` |
| 実行ファイル | `Logic Pro Creator Studio`（73 KB のスタブ、arm64 のみ） | `file`、`lipo -info` |
| バージョン | 12.3.1（CFBundleVersion 6682）、ProjectName `MALogic_App` | version.plist |
| Bundle ID | `com.apple.mobilelogic`（`com.apple.logic10` ではない） | Info.plist |
| 署名 | Apple Mac OS Application Signing、Team F3LWYJ7GM7、hardened runtime（flags 0x10000） | `codesign -dvv` |
| Sandbox | `com.apple.security.app-sandbox = false` | entitlements |
| 初回調査時のツール | Command Line Tools のみ。Swift 6.4、Python 3.14。tshark と Xcode はなし。EXP-AE-002 の統合ビルド時には Full Xcode を選択済み | 初回の `xcode-select -p`、`which`、EXP-AE-002 |

メイン実行ファイルはスタブ。Logic のコードは `Contents/Frameworks/` にある。
主なものは `Logic.framework`（40.7 MB）、`MAAudioEngine`（18.3 MB）、
`MAPlugInGUI`（10.3 MB）、`MAMixer`（5.8 MB）、`MACore`（4.6 MB）。

## 2. 経路の全体図

```text
                         Logic Pro Creator Studio（pid 25338、sandbox なし）
                                         |
  +---------------+---------------+------+---------+-----------------+-----------------+
  |               |               |                |                 |                 |
TCP *:51463     UDP *:7000     CoreMIDI        Apple Events      NSXPCConnection    AX / CGEvent
_apple-lgremote _osc._udp      仮想 src+dst     NSAppleScript     "helperTool" を     （未調査）
._tcp (Bonjour) (Bonjour)      (Logic Proの仮想 Enabled=true、    initWithMachService
MultipeerConn.  ControlSurface 出力 / 仮想入力)   .sdef は未発見    Name: で接続
(MACore)        OSC (Logic.fw) + コントロール                      → インストーラー
  |               |              サーフェス・プラグイン (16) +     ヘルパー（仮説）
Logic Remote    TouchOSC 等      Lua MIDI Device
(iPad/iPhone)                    Scripts (98)
```

## 3. 外部との接点

### 3.1 TCP 51463 — Logic Remote（`_apple-lgremote._tcp`）

| 状態 | 内容 |
|---|---|
| 確認済み | Logic は IPv4+IPv6 の `*:51463` で待ち受ける（全インターフェース。loopback 限定ではない）。Bonjour インスタンス `174jnk4ko0l8w` はこのホストの 51463 に解決される。TXT: `/hostType=0 /protocolVersion=10 _d=<computer name>`。2 回の実行で再現 |
| 確認済み | `MACore` は `MCSession`、`MCPeerID`、`MCNearbyServiceAdvertiser`、`MCNearbyServiceBrowser` をインポートし、文字列 `apple-lgremote` を含む（static-analysis/ipc-imports.txt） |
| 確認済み | `Logic.framework` に `LgLogicRemoteController`、`LgLogicRemoteMessageRouter` と、128 個の `handleUM_*` セレクターがある（static-analysis/handleUM-selectors.txt） |
| 確認済み | `/transport/pauseplay`、`/mixer/plugins/...`、`/keyCommand/commandsQuery`、`/logicClock/currentTempo` など、169 個の OSC 形式のアドレス文字列がある（static-analysis/osc-address-strings.tsv） |
| 確認済み | ポートとインスタンス名は起動ごとに変わる。51463 / `174jnk4ko0l8w` → 52476 / `08n2x7g7zvtu4`（EXP-A3-001）。UDP 7000 は不変 |
| 不明 | Info.plist に宣言されている `_apple-lgremote._udp` が広告されることはあるのか。どの実行でも見つかっていない。トラックごとの volume/mute/pan の運び方も不明。`/mixer/volume` のような文字列は見つからなかった |
| Hypothesis（仮説） | このサービスは MultipeerConnectivity（MPC）。インスタンス名は base36 の peer ID、`_d` は表示名で、先行事例の MPC 形式と一致する。Logic Remote のアプリメッセージは OSC 形式のアドレスで、MPC セッションデータ内を流れる。確信度は中（静的解析と Bonjour のみ。通信記録はまだない） |

### 3.2 UDP 7000 — OSC コントロールサーフェス（`_osc._udp`）

| 状態 | 内容 |
|---|---|
| 確認済み | Logic は UDP `*:7000` に bind する（IPv6 ソケット）。Bonjour `_osc._udp` のインスタンス `<computer name>` はこのホストの 7000 に解決される。TXT は `AppleLogic=LogicProX mfk=1` |
| 確認済み | `Logic.framework` は `socket`、`bind`、`NSNetService` をインポートし、`ControlSurfaceOSC`、`Starting OSC ports for device %@: In=%d, out=%d`、`Sending OSC Message %@ = %@ to '%@'` を含む |
| 不明 | 機器を設定しない状態で、7000 がどの OSC アドレスを受け付けるか。未知の送信元を拒否するのか、無視するのか、自動で機器として追加するのか |
| Hypothesis（仮説） | 7000 は Logic が文書化している OSC コントロールサーフェスの入力（TouchOSC の経路）。ミキサーパラメーターに対応付けるには、Logic の Controller Assignment（Learn）が必要。確信度は中（公開 TouchOSC 文書と文字列） |

### 3.3 CoreMIDI

| 状態 | 内容 |
|---|---|
| 確認済み | Logic は仮想 source `Logic Proの仮想出力` と destination `Logic Proの仮想入力` を 1 つずつ公開する（Tools/research-scripts/midi-endpoints.swift）。この Mac には他のエンドポイントがない |
| 確認済み | `Contents/PlugIns/MIDI Device Plug-ins/` に 16 個のコントロールサーフェス・プラグインがある（Logic Control = MCU、HUI、Logic Remote、TouchOSC など）。`~/Library/Preferences/com.apple.logic.pro.cs` は IFF に似たファイルで、これらのモジュールと `Lua` を列挙する。チャンク ID は byte 順が逆で、`MROF` = `FORM` |
| 確認済み | Lua 5.2 の MIDI Device Scripts が 98 個ある（`MACore.framework/Resources/MIDI Device Scripts/*/*.device/config.lua`）。`controller_info()` に `items`（name、objectType、midiType、MIDI bytes）と `supports_feedback` を定義する。文字列から、Logic が "Export Assignments To Lua Script" を行えることも分かる |
| 確認済み | Logic は新しい CoreMIDI ポートごとに Mackie の機器照会を送る。仮想 source+destination を作り model 0x14 として応答するプローブは、GUI 設定なしで Logic Control サーフェスとして自動登録される（EXP-MCU）。mute（note 0x10）とフェーダー（pitchbend + touch）の書き込みは動作し、LED / フェーダーの応答と LCD テキストで確認できた |
| 不明 | Logic がユーザーディレクトリから Lua スクリプトを読み込むか。スクリプトで項目をミキサーパラメーターへ結び付け、フィードバックも取得できるか |

### 3.4 Apple Events / AppleScript

| 状態 | 内容 |
|---|---|
| 確認済み | `NSAppleScriptEnabled = true`。`sdef` は Standard Suite、Text Suite、Type Definitions、Type Names を返すが、4 つの非公開 FourCC は含まない。以前の bundle 調査では対応する `.sdef`、`.scriptSuite`、`.appintents` メタデータも見つからなかった。根拠: EXP-AE-001 とその raw SDEF |
| 確認済み | Logic.framework は呼び出し `0x004f11fc` で、`aUeV/Spt2` とハンドラー `0x00590e30` を明示的に登録する。Ghidra の逆コンパイルと ARM64 の逆アセンブルが一致。根拠: `static-analysis/appleevent-registration.md` |
| 確認済み | `sPmo=6` はコマンド処理を選ぶ。負の `sPkc` は符号反転後、符号付き 16-bit の内部コマンド ID に縮められる。`-3` は play、`-5` は stop。native の AESendMessage と MCU 読み戻しで両方を 2 回ずつ確認した。正の番号 `11` / `1` も play / stop に対応し、検証済み。根拠: EXP-AE-001、`static-analysis/appleevent-command-dispatch.md` |
| 確認済み | active owner または currentSong のポインターが null なら、パラメーターを読む前にハンドラーが `-38` を返す。標準の `documents` scripting で開いている `LogicCLI-Test.logicx` が 1 件見え、元のイベントも現在は成功する。以前のセッションでどの null 状態だったかは記録していない。根拠: EXP-AE-001 と登録処理の解析 |
| 確認済み | 正常な返信だけでは実行を証明できない。パラメーターの descriptor 型が違っていても、0 を返して何もしない場合がある。raw sender は書き込みを未検証とし、実験用 wrapper が独立に MCU トランスポートを確認する。根拠: EXP-AE-001 の native 14 ケース比較 |
| 確認済み | 製品の `logicctl transport play\|stop --backend appleevent` は、logicd 経由で native 書き込みを行い、独立した MCU フィードバックで検証する。専用テストプロジェクトで play/stop 2 組、状態変更不要の 2 操作、既存 MCU 経路がすべて通った。対応を確認した構成は厳密に 12.3.1/6682。根拠: EXP-AE-002 |
| 不明 | その他の mode の完全な意味、副作用のないプロジェクト状態の読み取り、AppleEvents を使う mixer/plugin/automation/track/seek API。mode 4 はテンポデータへ副作用を及ぼす可能性があり、実機では試していない |

### 3.5 XPC / Mach / distributed notifications

| 状態 | 内容 |
|---|---|
| 確認済み | アプリ内の `.xpc` service は、`MAContentDownloading.framework/XPCServices/com.apple.musicapps.MAContentInstallation.xpc` だけ。どの framework も `xpc_connection_create*` や Network.framework の `nw_*` をインポートしていない |
| 確認済み | `Logic.framework` は `_helperToolConnection` と `initWithMachServiceName:options:` で `NSXPCConnection` を使う。文字列に `com.apple.ServiceManagement.blesshelper` があり、bundle に `Contents/Library/LaunchServices/com.apple.musicapps.InstallerHelperTool` を含む |
| 確認済み | Logic、MADSP、MAKeymap、MAToolKit、MAToolKitHighLevel が `NSDistributedNotificationCenter` をインポートする |
| Hypothesis（仮説） | Logic.framework 内で唯一の XPC クライアントは、操作用サービスではなく、特権を持つインストーラーヘルパーに接続する。確信度は中（文字列が根拠。逆アセンブルでは未確認） |
| 不明 | 投稿 / 監視する distributed notification の名前 |
| 注記 | 内部の XPC 操作用サービスは見つかっていない。プロジェクトの規則に従い、存在を前提とした設計はしない |

### 3.6 プロセスとローカル IPC

| 状態 | 内容 |
|---|---|
| 確認済み | Logic に子プロセスはない。接続済みの匿名 unix-domain socket pair が 5 組ある（`lsof -U`）。関連するシステムプロセスは `coreaudiod`、`MIDIServer`、`AUHostingServiceXPC_arrow`、2× `AudioComponentRegistrar` |
| 不明 | 5 組の unix socket の接続相手 |

### 3.7 Accessibility / CGEvent

- トランスポートには AX checkbox の「再生」「録音」と button の「停止」がある。
  チャンネルストリップには AXSlider の「ボリュームフェーダー」「パン」と
  AXSwitch の「ミュート」がある。
- インスペクターのストリップにある「ミュート」AXSwitch は、AXPress で切り替わる。
  トラックヘッダーの「ミュート」AXCheckBox は、AXPress で変化しなかった（EXP-MCU-003）。
- この shell のプロセスには AX の許可がない（`AXIsProcessTrusted() == false`）。
  AX backend を使うには、ユーザーがホストアプリへ Accessibility の権限を与える必要がある。

## 4. 現時点の根拠に基づく操作経路の比較

| 順位 | 経路 | 状態を読めるか | 書き込めるか | 状況 |
|---|---|---|---|---|
| トランスポート実装済み | 非公開 AppleEvent `aUeV/Spt2` | 現在のトランスポート読み戻しは MCU | **はい、検証済み**: play/stop | EXP-AE-001 で mode6 のコマンド処理を確認。EXP-AE-002 で明示選択する製品統合を検証。MCU 書き込みへ自動で切り替える処理はない |
| 1 | Logic Remote（TCP 51463 上の MPC） | 可能性あり（Remote はミキサー状態を表示） | 可能性あり | MPC 通信の先行事例あり（2022、当時の protocolVersion は不明）。アプリ層は非公開。実際の Logic Remote による通信記録が必要 |
| 2 | 仮想 MIDI 経由の MCU（Logic Control プラグイン） | **はい、検証済み**: フェーダーの応答、LED、LCD（名前、dB） | トラック 1 の mute と volume は**検証済み** | handshake で自動登録され、GUI 設定は不要（EXP-MCU-001…009）。v0.1 の採用 backend |
| 3 | UDP 7000 の OSC | 割り当てを介したフィードバックのみ | 割り当て経由 | パラメーターごとに Controller Assignments が必要 |
| 4 | Lua MIDI Device Script | 不明 | 割り当て経由 | ユーザースクリプトの配置場所を確認する必要あり |
| 5 | Accessibility | はい（UI の値） | はい | 壊れやすい。他の経路が公開しない項目に対する最終手段 |
| 6 | CGEvent / キーコマンド | いいえ | はい | 書き込みだけ。単独では書き込み後の検証を満たさない |
| — | Native XPC | — | — | 操作用サービスは観測されていない |

## 5. 先行事例

`Research/notes/prior-art.md` を参照。

## 6. 未解決の問いと次の実験

1. ~~EXP-A3-001~~ 完了: TCP ポートは起動ごとに変わるため、Bonjour で解決する。
2. **EXP-A3-002**: 実際の Logic Remote 機器を接続し、loopback / Wi-Fi の通信を記録して、
   MPC のフレーム構造と protocolVersion 10 を確認する。
   Logic Remote のある iPad/iPhone と `tcpdump` が必要
   （sudo または BPF へのアクセスが必要。先に許可を求める）。
3. ~~EXP-A3-003~~ EXP-MCU-001…016 として完了。
   v0.1 の MCU backend として実装済み（EXP-CLI-001）。
   次は 8 トラックを超えるバンク移動、Undo の動作、MCU のプラグインモードによるパラメーター操作。
4. **EXP-A3-004**: play/stop 時に Logic が投稿する distributed notification を列挙する
   （`NSDistributedNotificationCenter` observer、読み取りのみ）。
5. ユーザーの Lua MIDI Device Scripts を読み込む場所を見つける。
6. 根拠の位置を特定しながら、Ghidra で native の状態取得経路を引き続き調べる。
   内部の document getter と外部から呼べるメッセージを区別し、
   副作用を確認してから読み取り専用の状態 API として扱う。
   非公開 AppleEvent の mode 4 は、helper がテンポマップデータを変更し得るため対象外。

## 7. v0.1 の実装メモ（logicd MCU backend）

- 古いポートの消滅から約 0.3 s 以内に logicd を再起動すると、
  5 回中 3 回、Logic が沈黙して機器照会を送らなかった。
  数秒待つと必ず照会が来た。現在の logicd は 2.5 s 以内に照会が来なければ
  ポートを作り直す（高速再起動 5/5 回で接続、そのうち 4 回は作り直しによるもの）。
- 同じ名前でポートを作り直すと、Control Surface Setup の単一の "Mackie Control" 項目を
  再利用する（約 10 回の再起動後も重複なし）。
- select のあと、Logic はストリップの下段 LCD セルに最大約 3 s トラック名を表示し、
  その後 pan 値へ戻る。
- handshake 後の数百 ms は、Logic が状態の一括データを送る。
  この期間の LCD 読み取りは上書きされるため、logicd はその後 1 s 待つ。
- Logic の既定の Undo History 設定では、MCU / GUI のミキサー書き込みで
  Undo の項目は増えない。パネルには「パラメータの変更を含める: ミキサー / プラグイン」が
  ある（EXP-UNDO-001）。名前変更の Undo では MCU の LCD 名が更新されなかった。
- 「ミキサー」を有効にすると、MCU の volume/pan 書き込みが Undo に記録される。
  ただし近接した書き込みはまとめられ、一度の Undo で要求していない −11.4 dB に
  戻ったことがある。mute は記録されない（EXP-UNDO-002）。
  GUI での名前変更は MCU の LCD を更新するが、その Undo は更新しない。

## 8. Native トランスポートの統合（EXP-AE-002）

- `logicctl` は薄いクライアントのまま。AppleEvent を明示指定したときは、
  まず daemon の対応機能を確認する。古い daemon が指定を無視し、
  MCU として処理することを防ぐため。
- `logicd` が native sender と持続する MCU 読み戻しセッションの両方を所有し、
  コマンドを 1 件ずつ実行する。製品の Swift コードから調査ツールは呼び出さない。
- Native 送信は正確な `'long'` descriptor を使い、実行中のプロセスを対象にする。
  検証済みの version/build と照合する。送信状態と返信の error は別々に扱う。
- 読み戻しには、現在の handshake のあとに実際に受信した play と record の LED が必要。
  変更したフィールドには新しいフィードバックも必要。
  PID または handshake の世代が変わると検証は無効になり、
  decoder の既定値を検証済みの「状態変更不要」として扱わない。
- handshake の基準値は、同じ MIDI batch の後半にあるフィードバックを保つ。
  新しい LCD の基準値で古い接続状態を拒否し、
  バンク位置のキャッシュも handshake の世代と結び付ける。
