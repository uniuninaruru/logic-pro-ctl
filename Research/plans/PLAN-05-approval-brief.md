[日本語](PLAN-05-approval-brief.md) | [English](PLAN-05-approval-brief.en.md)

# PLAN-05 承認用の計画書 — Logic Remote の独立ピアで、状態の受信だけを確かめる

| 項目 | 内容 |
|---|---|
| 状態 | **提案。まだ何も実行していない。承認が出るまで接続しない** |
| 日付 | 2026-10-05 |
| 目的 | 静的解析で立てた予測（接続の順序・フレーム・初回送信・曲の切り替え）を、1 回の短い受信で検証する |
| 範囲 | このMac上の Logic（専用プロジェクト `LogicCLI-Test.logicx`）に、研究用のピアを 1 つ接続して**受信するだけ** |
| 根拠 | [SA-REMOTE-SESSION-001](../static-analysis/SA-REMOTE-SESSION-001.md)・[SA-REMOTE-FRAME-001](../static-analysis/SA-REMOTE-FRAME-001.md)・[SA-REMOTE-STATE-001](../static-analysis/SA-REMOTE-STATE-001.md) |

承認していただきたいのは、**下の「E1」「E2」までの段階**です。E0 は接続せずに存在を確かめるだけで、同時に承認をお願いします。E3 以降は、E2 の結果を見てから改めて相談します。

## 1. してよいこと・してはいけないこと

| してよい（承認後） | しない |
|---|---|
| Apple の MultipeerConnectivity で、`apple-lgremote` の広告を探す（E0） | 既存の Logic Remote 端末と**同じ名前を名乗って**確認ダイアログを避けること（なりすまし） |
| 自分の名前で招待を送り、Logic の確認ダイアログでユーザーが「Connect」を押す（E1） | Logic のバイナリ・署名・SIP の変更、`sudo`、プロセスへの注入 |
| `/protocolVersion` と `/jsonSupport` を送り、Logic が送るものを**受信して記録する**（E1・E2） | 編集系のコマンド（再生・停止を含む）、`/keyCommand/actionNum`、`/cs/`、`/fader` など、Logic の状態を変える送信 |
| 専用プロジェクトの 1 つの曲を開いたまま、受信を数十秒記録する（E2） | 制作用のプロジェクトを開いた状態での実験 |
| 受信した生データを `Research/raw/`（Git の追跡対象外）に保存し、整理した結果だけをコミットする | 生の通信データのコミット、個人情報を含むものの公開 |

## 2. 先に知っておいてほしい副作用

1. **Logic の確認ダイアログが出る。** 知らない名前のピアが招待してきたとき、Logic は「接続しますか」と尋ねる（`shouldConnectToPeerID:ofType:`。SA-REMOTE-SESSION-001 §3.2）。**人が「Connect」を押す必要がある**。無人では進まない。
2. **Logic が端末を登録するかもしれない。** 「Connect」を押すと、Logic が「Logic Remote の端末」として名前を覚える（新規登録。同 §3.2）。Logic の設定に残り、削除の方法は未確認。**これは Logic の設定への永続的な変更**で、専用プロジェクトの外にも及びうる。
3. **macOS が「ローカルネットワーク」の許可を求める。** 研究用のピアは、Bonjour と MultipeerConnectivity を使う小さなアプリになる。初回に macOS の確認が出る。
4. **接続は暗号化されない設定で張られる**（同 §3.1）。このMac内の通信だが、ネットワークに出る可能性は未確認。
5. 接続中に Logic が状態を送り続ける。曲を切り替えたり、録音待機を変えたりしない（E2 の間は Logic を操作しない）。

## 3. 段階

| 段階 | 内容 | 送るもの | 記録するもの | 中止の条件 |
|---|---|---|---|---|
| **E0** | `MCNearbyServiceBrowser` で `apple-lgremote` を探す。**招待しない** | なし | 見つかったピアの名前と `discoveryInfo`（`/hostType`、`/protocolVersion`） | 何も見つからない → ここで終了 |
| **E1** | 自分の名前で招待し、ユーザーが Logic のダイアログで「Connect」を押す。接続したら `/protocolVersion = 10` と `/jsonSupport` を送る | 上の 2 つだけ | 接続状態の変化の順序と時刻、最初に受信するメッセージ | ダイアログが出ない／拒否された → 終了。予期しないダイアログ → 中止 |
| **E2** | 接続したまま、初回送信を最大 60 秒受信する。**送信はしない** | なし | すべての受信フレーム（時刻・形式タグ・MAZP の有無・解凍後の中身） | 60 秒、またはユーザーの合図、または切断 |
| E3（後日） | 曲の切り替え、1 トラックのミュートに対する差分の受信 | 未定 | 差分 | E2 を見てから改めて相談 |

E1・E2 は、**一度の接続**で続けて行う。終わったら接続を閉じる（ピアを終了する）。

## 4. E2 で検証する予測

静的解析の仮説を、受信した内容と突き合わせる。**外れたら、そのまま記録する**（資料を書き換えて合わせない）。

| # | 予測（根拠） | 合格の見方 |
|---|---|---|
| P1 | E1 で、`/protocolVersion` は接続の直後に Logic から **10** で届く（SESSION §4） | 最初の数メッセージに `/protocolVersion = 10` と `/jsonSupport` がある |
| P2 | Logic は、バージョンを待ってから初回送信を始める（STATE §3.4） | `/protocolVersion` を送った後に `/mixer/hideRecordButtons` などが届く |
| P3 | 初回送信の順序は STATE §3 の表と同じ（`/hostType`、`/ati`、`/allTrackCount`…） | 受信順が表に一致する。違いは行ごとに記録 |
| P4 | `/ati` は 13 本の並行配列で、長さが等しい（STATE §4） | [スキーマ](../protocol/logic-remote-state.schema.json)で検査して合格 |
| P5 | `/ati` と `/allTrackCount`・`/trackCount` が**二重に**届く（STATE §3.2） | 同じ内容のものが 2 回ある |
| P6 | `/sti` の引数は、MAZP 圧縮の NSKeyedArchive（STATE §5） | 解凍して辞書になる |
| P7 | `/gtFaderData` の `g` のキーは `/ati` の `gindex` と同じ値（STATE §8） | 集合が一致する |
| P8 | `/multiTempo` の向き（STATE §6）、`/logicClock/currentTempo` の単位 | 既知のテンポ（プロジェクトの 120）と並べて読む |
| P9 | `vL` と、MCU の dB 表示の対応（STATE §8.1） | 既知の dB（0 dB など）と並べて読む |
| P10 | 値 0 の省略は、キーコマンドの初回だけ（STATE §7） | `/gtFaderData` の `s`・`m`・`vL` が 0 でも含まれる |
| P11 | 初回送信に終了の合図は無い（STATE §10） | 最後のメッセージが決まった形で終わるか、確認する |
| P12 | `/ati` の `t` は、Master = 5（確信度: 高）、Piano・Bass・Synth = 9（中）、Audio・Trk05〜Trk10 = 1（低。外れれば 4）、St Out = 6 か 10（低）（[SA-REMOTE-TRACKTYPE-001](../static-analysis/SA-REMOTE-TRACKTYPE-001.md) §7） | 専用プロジェクトの 12 ストリップと並べる。外れた値はそのまま記録する |
| P13 | `c` の 4 色は 4 バイトで、R, G, B, A の順。4 バイト目はほぼ `0xff`。色番号 0 のトラックの `tnc`・`tsc` は `8cc0ffff`（計算値。同 §5・§7） | 受信した `c` の `NSData` を並べる。`/colorIndexMap` で色番号を別に照合する |

受信したフレームは、まず [`RemoteFrameParser`](../../Sources/LogicCore/Backends/Remote/RemoteFrame.swift) で復号できるかを確かめる。復号できなければ、その事実が最初の発見になる。

## 5. 実装の見通し（承認後の作業）

- 研究用のピアは `Tools/` の下の小さな macOS アプリ（Swift）とする。製品の `Sources/` には入れない。受信だけを行い、保存先は `Research/raw/remote-recv/<日時>/`。
- 主な手間：`NSLocalNetworkUsageDescription` と Bonjour サービス名（`_apple-lgremote._tcp`／`._udp`）を Info.plist に書く。コード署名は自分の開発用の署名で足りる想定（Logic や他アプリの署名は変えない）。
- 招待の `context` には、端末種別（0〜4 のうち 1 つ。SESSION §3.2 の符号付き比較の注意）を二進 plist で添える。
- 所要時間：実装 1 日未満の見込み。実験自体は数分。

## 6. 承認していただく項目

1. **E0**（接続せず、広告を探すだけ）を行ってよいか。
2. **E1・E2**（自分の名前で接続し、ダイアログで「Connect」を押して受信する）を行ってよいか。
   - ダイアログを押すのは、ユーザー本人か、**明示的に許可された操作**の下での私か。
   - 「Logic が端末を登録する」副作用（§2-2）を受け入れるか。登録された名前を、実験後に Logic の画面から削除できるかは、E1 で確認する。
3. 実験の間、Logic を専用プロジェクトだけにしてよいか（他のプロジェクトを閉じる）。

**承認の範囲を超える操作（編集系の送信、E3 以降、制作用のプロジェクト）は行いません。**
