[日本語](SA-REMOTE-FRAME-001.md) | [English](SA-REMOTE-FRAME-001.en.md)

# SA-REMOTE-FRAME-001: Logic Remote のフレーム — タグ・圧縮・型・順序

| 項目 | 内容 |
|---|---|
| 日付 | 2026-10-02 |
| Logic | 12.3.1（6682）、arm64 |
| 対象 | `MACore.framework`（arm64 スライス SHA-256 `99a4a9ad…`、ユニバーサル全体 `76ab2a5f…`） |
| 方法 | **静的解析のみ**（Ghidra の限定逆コンパイル、ObjC メソッド表の照合、逆アセンブル）。Logic には何も送らず、接続もしていない |
| 実装 | `Sources/LogicCore/Backends/Remote/RemoteFrame.swift`（デコーダーのみ）、試験 `Tests/LogicCoreTests/RemoteFrameTests.swift` |
| 固定データ | `Tests/Fixtures/logic-remote/`（**合成**。実機の記録ではない。生成: `Tools/research-scripts/make_remote_fixtures.py`） |
| 機械可読の定義 | `Research/protocol/logic-remote.ksy`（Kaitai。**未コンパイル**）、`Research/protocol/logic-remote.schema.json` |
| 関連 | [SA-REMOTE-SESSION-001](SA-REMOTE-SESSION-001.md)（接続）・[SA-002](SA-002-control-surface-assign-model.md) §3（概要）・[SA-005](SA-005-logic-remote-state-push.md)（状態の送信） |

> **受信での照合（2026-10-05、[EXP-REMOTE-001](../experiments/EXP-REMOTE-001-receive-initial-state.md)）:** Logic からの 5,947 フレームを、この文書どおりの `RemoteFrameParser` がすべて復号した（失敗 0）。形式の選び方（§2）は観測と一致：`/jsonSupport` の交換の前は plist、その後は JSON、`NSData` を含むものは plist、数値キーの辞書（`/gtFaderData`、`/colorIndexMap`）はキー付きアーカイブ。圧縮していないペイロードはすべて 1,024 バイト以下。試験の固定データは今も合成で、生の記録は Git に入れていない。

**確信度の約束:** 逆コンパイルのコードと一致する事実は「確認」、そこからの推論は「仮説」。通信では未確認。

## 1. フレームの構造（確認）

```text
フレーム   = タグ(1バイト) + ペイロード
タグ       = bit 7: ペイロードが MAZP コンテナ ／ bit 0〜6: 形式
形式       = 1 プロパティリスト ／ 4 JSON ／ それ以外 キー付きアーカイブ（送信側は 2 を使う）
MAZP       = "MAZP"(4) + ヘッダー長 u16 BE(=10) + 展開後の長さ u32 BE + zlib ストリーム
展開後の内容 = 辞書 { アドレス : 引数 }  ／  辞書の配列（順序つきの一括）
```

| 部分 | 根拠 |
|---|---|
| 受信：タグ・形式・展開の分岐 | `MAPeerRouter::processReceivedData:fromPeer:`（0x000f7ac8） |
| 送信：形式の選択と圧縮の判断 | シリアライザ `FUN_000f98c8`（0x000f98c8） |
| 展開：MAZP の解釈 | `-[NSData maUncompressedData]`（IMP 0x56698）。メソッド表で突き合わせた |
| 圧縮：MAZP の生成 | `-[NSData maCompressedDataWithCompressionLevel:]`（IMP 0x5659c） |
| 汎用の zlib/gzip 展開 | `-[NSData decompressedData]`（IMP 0x56390）。`inflateInit2(47)`。MAZP とは**別の**関数 |

## 2. 送信側が形式を選ぶ順序（確認）

1. 全接続先が JSON に対応済み（`canUseJSON`、[SESSION §4](SA-REMOTE-SESSION-001.md)）で、かつオブジェクトが JSON として有効 → **形式 4（JSON）**。
2. そうでなく、バイナリ plist（形式 200）として有効 → **形式 1**。
3. どちらも不可（例：辞書のキーが数値）→ **形式 2（キー付きアーカイブ）**。ルートのキーは `NSKeyedArchiveRootObjectKey`。
4. ペイロード（タグの後）が **1024 バイトを超える**とき、レベル 9 で MAZP に圧縮する。
   圧縮後が元より**小さくなったときだけ**、タグの bit 7 を立てて置き換える。

JSON に非対応の相手が一人でもいる間は、形式 4 は使われません（接続直後の最初のメッセージは plist になるはずです。仮説）。

## 3. 受信側の規則（確認）と、このパーサーとの違い

| 項目 | Logic | このパーサー（`RemoteFrameParser`） |
|---|---|---|
| 形式 1 / 4 / それ以外 | 1 = plist、4 = JSON、**それ以外は全部キー付きアーカイブ** | 1 / 4 / 2 だけ。他は `unknownFormat(n)` で区別して報告 |
| キー付きアーカイブの型 | 許可クラス：`NSDictionary`・`NSString`・`NSURL`・`NSNumber`・`NSArray`・`NSIndexPath`・`NSData` | 同じ 7 クラス |
| bit 7 でヘッダー無し | 10 バイト未満は捨てる。**"MAZP" で始まらなければ、そのまま使う** | 10 バイト未満は `truncatedContainer`。ヘッダー無しは `flaggedWithoutHeader` として通す |
| ヘッダー長 | 先頭からその位置を zlib の開始とする（10 を前提としない） | 10 未満・データ長超過は `badContainerHeader` |
| 展開後の長さ | 宣言どおりに確保。**上限なし**（最大 4 GiB）。展開後の実際の長さは**確認しない** | 上限 16 MiB（`declaredSizeTooLarge`）。実際の長さが違えば `sizeMismatch` |
| zlib のチェックサム | `uncompress` が検査する | Adler-32 を自前で検査（`decompressionFailed`） |
| JSON の断片（`"text"` など） | 受け付けない（`NSJSONSerialization` の既定） | 同じ（`decodeFailed`） |
| plist の書式 | 自動判別。**古い形式の ASCII plist も読む** | 同じ。裸の単語は文字列になり、`unexpectedTopLevel` |
| 最上位 | 辞書 → 各キーを配送。配列 → 要素の辞書を**順に**配送 | 辞書 = 1 グループ、配列 = 順序つきの複数グループ。それ以外は `unexpectedTopLevel` |
| アドレスが文字列でない | 未確認（`hasPrefix:` 等で例外の可能性） | `nonStringAddress` |

## 4. 順序・数値キー・バイナリ引数

| 論点 | 確認したこと |
|---|---|
| 順序 | **配列の要素の順序は保たれる**（`FUN_000f94f8`が要素を順に処理）。**辞書の中のキーの順序は定義されない**（辞書の列挙順）。配列の一括は**プロトコルバージョン 7 以上**の相手だけに送られ、7 未満には辞書を 1 つずつ送る（`_sendOrderedMessages…`、0x000f67f0） |
| 数値キー | plist / JSON の辞書は文字列キーのみ。**キーが数値の辞書は形式 2 でしか送れない**。`/gtFaderData` の内側（`NSNumber` の音源 ID をキーとする辞書。[SA-005 §3](SA-005-logic-remote-state-push.md)）がこれに当たるため、**`/gtFaderData` は形式 2 で送られている**と推定する（仮説。確信度: 中。通信で未確認） |
| バイナリ引数 | `NSData` は plist（data）とキー付きアーカイブで運べる。JSON では運べない。パーサーは `.data` として保持する |
| 配信方法 | `useTCP` は信頼できる送信（`MCSessionSendDataReliable` = 0）、偽は信頼性なし（1）。`/mixerLevels` を含む辞書、または `useTCP` が偽のときは、**キーごとに別のデータ**として送る |
| 到着後の処理 | `/alert` は優先度の高い別キュー、それ以外はメインキューで配送。**低レベルのメッセージ**（`/disconnectImmediately`・`/jsonSupport`・`/protocolVersion`）は配送の前に処理される（[SESSION §5](SA-REMOTE-SESSION-001.md)） |

## 5. 試験と限界

- 92 件のうち、フレームの試験は 11 件：正常系（plist・JSON・順序つき配列・数値キーのアーカイブ・圧縮 2 種・ヘッダー無し）と、
  異常系（空・未知形式・壊れた JSON/plist/アーカイブ・10 バイト未満・不正なヘッダー・サイズ違反・サイズ不一致・チェックサム破損・深さ超過）。
- チェックサムの検査を外す欠陥、未知形式を許容する欠陥を入れると、それぞれ試験が失敗することを確認した。
- **固定データは合成**です。この文書の読み取りどおりに作ったものなので、「パーサーがこの読み取りに従う」ことは示しますが、
  「Logic が実際にこの形で送る」ことは示しません。実機の記録（PLAN-05、承認が必要）で置き換えます。
- 展開後の長さを宣言値に設定するだけの Logic の実装と、厳密なパーサーとの違いは、§3 の表のとおりです。

## 6. 不明なこと

| 項目 | 状態 |
|---|---|
| 引数なしの送信で使う既定の値（`NSConstantIntegerNumber`） | 不明。バイナリの定数を読もうとしたが、構造を読み違えて確定できなかった |
| 引数なしの `/jsonSupport` を受けた側が引数を読むか | 不明（読む必要はないと推定。仮説） |
| 日付型（plist の `NSDate`） | Logic が受け取れるか未確認。パーサーは `unsupportedType` |
| リソース送信（`sendResourceAtURL:`、リージョンの転送など） | 別の経路。このフレームでは扱わない |
| MPC 1 回の送信サイズの上限と、Logic が受け取れる最大サイズ | 未確認 |
| `/gtFaderData` が形式 2 であること | **受信で確認**（タグ 0x82 = MAZP 付きのキー付きアーカイブ。EXP-REMOTE-001） |
| `.ksy` の正しさ | 未検証（コンパイラ未導入）。Swift のパーサーが基準 |
