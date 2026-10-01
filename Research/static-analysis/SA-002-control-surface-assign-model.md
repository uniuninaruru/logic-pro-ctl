# SA-002: コントロールサーフェス共通の Assign モデルと Logic Remote のアプリ層フレーム

[日本語](SA-002-control-surface-assign-model.md) | [English](SA-002-control-surface-assign-model.en.md)

| 項目 | 内容 |
|---|---|
| 日付 | 2026-10-01 |
| Logic | 12.3.1（6682） |
| バイナリ（arm64 スライス） | `PlugIns/MIDI Device Plug-ins/{Logic Control,Logic Remote,TouchOSC}.bundle`、`Frameworks/MACore.framework/Versions/A/MACore` |
| ツール | Ghidra 12.1.4 headless（`Tools/ghidra/analyze.sh`）。`Tools/ghidra/switch_table.py`、`Tools/ghidra/remote_table.py` でテーブルを復元 |
| 抽出したテーブル | `Research/protocol/cs-assign-{mcu-switches,remote,touchosc}.tsv` |

## 1. 各サーフェス・プラグインが Assign レコードを作る

- Logic Control の `DDESCR_LC::FillTemplate(Assign*, TControlID, unsigned char)` と、
  Logic Remote / TouchOSC の `_CSDefault` は、いずれも **MACore** 内の
  `AssignSerializedCore::Init` を呼ぶ。インポート名は
  `@rpath/MACore.framework/.../MACore::AssignSerializedCore::Init`。
  MACore が公開するのは `AssignHeader::Init` と `AssignSerializedCore::Init` のみ。
- 3 つとも、シリアライズされた Assign の次のフィールドに書き込む。

| オフセット | サイズ | 書き込み元 | 意味（仮説） |
|---|---|---|---|
| +0x3a | int | MCU switch-info `+0xc`、Remote/TouchOSC の要素 `+0x00` | kind |
| +0x3e | short | MCU ストリップ番号 / Remote の要素 `+0x04` | sub（ストリップのオフセット、または kind 9 のコマンド番号） |
| +0x40 | int | MCU switch-info `+0x10`、Remote の要素 `+0x08` | param |
| +0x52 | int | `TControlID`（MCU）/ テーブル番号（Remote） | サーフェス上の control id |
| Init() の結果 | bytes | MCU: `01 03 90 <note> F5`、`E0|n …` | 入力メッセージのテンプレート（MIDI） |

## 2. 共通の番号体系

kind 5 は、バンク位置を基準にしたチャンネルストリップのパラメーター。
各テーブルにある param は次のとおり。

| Param | Logic Remote | TouchOSC | Logic Control（MCU） |
|---|---|---|---|
| 3 | `/cs/mixer/solo/` | `/1/solo` | — |
| 7 | `/cs/mixer/volume/volume`、mastervolume（sub 20480） | `/1/volume` | フェーダー（FillTemplate が 7 を書く） |
| 9 | `/cs/mixer/mute/`、mastermute | `/1/mute` | — |
| 10 | `/cs/mixer/volume/pan` | `/1/pan` | — |
| 28–35 | `/cs/mixer/sends/send1…8` | `/2/sendlevel/1…` | — |
| 56–67 | — | `/2/insertbypass/…` | — |
| 128 | — | — | `Ch. n Mute` |
| 129 | — | — | `Ch. n Solo` |
| 259 | `/cs/mixer/select/` | `/1/select/1/1` | `Ch. n Select` |
| 260 | `/cs/mixer/record/` | `/1/recenable` | `Ch. n Record/Ready` |
| 264 | `/cs/mixer/automation/` | — | `Read/Off` |
| 288–295 | `/cs/mixer/sends/sendbypass1…8` | — | — |
| 528–551 | — | `/3/frq/…`、`/3/gain/…`（EQ） | — |

Logic Remote のテーブルにあるその他の kind は次のとおり。

- 9: コマンド。`sub` がコマンド番号になる。
  `/cs/transport/stop` 5、`/cs/transport/play` 3、`/cs/transport/cycle` 15、
  `/cs/transport/record` 7、`/cs/transport/click` 474、`/undo` 761、`/redo` 796、
  `/duplicateTrack` 1728、`/cs/transport/track-` / `+` 1272/1273、
  `/transport/marker-` / `+` 1330/1329、solo/mute reset 1040/1041。
- 10: バンク移動。1: ページ。2/3: グループのヘッダー。
- 0: 表示専用のフィードバック。
  `/cs/mixer/trackname`、`/cs/mixer/level`、`/cs/mixer/panval`。

**Hypothesis（仮説）:**

- H1: kind 5 と param は、すべてのコントロールサーフェスに共通する
  Logic のチャンネルストリップ・パラメーター空間を表す
  （volume 7、pan 10、select 259、rec 260、automation 264）。
  確信度は、7/259/260/264 では**高**（独立した 3 テーブルで一致）、
  その他では中。反例として、mute/solo は Remote と TouchOSC では 9/3、
  MCU では 128/129。トグル操作と値指定など、2 種類のパラメーターなのかは未確認。
- H2: kind 9 の `sub` は Logic のキーコマンド ID。確信度は中
  （Logic.framework に `/keyCommand/actionNum` はあるが、まだ対応関係を追えていない）。
- どちらも brief §16「共通のコマンド・状態表現」の候補。

## 3. Logic Remote のアプリ層フレーム（MACore `MAPeerRouter`）

`session:didReceiveData:fromPeer:` から呼ばれる
`MAPeerRouter::processReceivedData:fromPeer:` の処理は次のとおり。

- byte 0 は形式を表す。bit 7 が立っている場合は、ペイロードが圧縮されている
  （`-[NSData maUncompressedData]`）。下位 7 bits は、**4 = JSON**
  （`NSJSONSerialization`）、**1 = property list**（`NSPropertyListSerialization`）。
  その他では、クラスの許可リストを使って `NSKeyedUnarchiver` で復元する。
- bytes 1… がペイロード。復元したオブジェクトが **NSArray** なら、
  `routeMultipleMessagesArray:fromPeer:` で順序どおりに処理する。
  **NSDictionary** なら、各 key/value を `routeMessage:withArgument:fromPeer:` に渡す。
  key は OSC 形式のアドレス、value は引数。
- `MAPeer` は `protocolVersion` と `supportsJSON` を持つ。
  ルーターは `waitForProtocolVersionIfNeededForPeerWithID:` で相手の
  プロトコルバージョンを待つ。
- コントロールサーフェスの通信は `CPlugInUserCommunicator_OSC(_ObjcBridge)` が橋渡しする
  （`routeOSCMessage:withArgument:`、`sendOSCMessage:withArgument:`）。
  プラグイン・パラメーターの通信も扱う
  （`SetParameterFloatingValue`、`BroadcastParameterValueChange`、`GetParameterInfo` など）。

**Hypothesis H3（仮説）:** MPC セッション上の Logic Remote メッセージは、
`<1 byte format><JSON or plist of {"/cs/…": arg}>` という形式。
確信度は中（静的解析のみ）。次の検証は、実際の Logic Remote で通信を記録するか、
MPC 通信を再現したあと、自前の MPC peer を接続すること。

## 次に調べること

- Logic.framework: Assign kind 5/9 の使用先と、
  `routeMessage:withArgument:` の到達先（`LgLogicRemoteMessageRouter`）。
- `maUncompressedData` のアルゴリズム。
- H1 の mute/solo の違いと、H2 のキーコマンド ID。
