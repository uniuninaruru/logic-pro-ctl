# 読み取り結果の契約 — 不明・一部・古いを成功にしない

[日本語](observation-contract.md) | [English](observation-contract.en.md)

[仕様に戻る](specification.md) · [README](../README.md)

`logicctl` の読み取り（`status`・`state`・`track list`・`track get`）は、
**値だけでなく、その値をどこまで信じてよいか**も返します。
エージェントは「空の一覧」「`false`」「短い一覧」を、確認できた事実として扱えます。
確認できなかったことは、確認できなかったとして返します。

## 1. 三つの約束

| 約束 | 意味 |
|---|---|
| 不明は `null` | Logicがこの接続で報告していない値は `null`。`false` や `0` にしません |
| 一覧は証明できたときだけ完全 | 末尾まで確認できなかった走査は、空でも短くても成功にしません |
| 古い状態を使わない | Logicが接続をやり直したら、前の接続の名前・フェーダー・LEDは捨てます |

## 2. `observation`

読み取りの応答には、`result` と並べて `observation` が付きます。書き込みの応答にはありません。

```json
{
  "ok": true,
  "result": [ ... ],
  "observation": {
    "source": "mcu",
    "scope": "mixer_strips",
    "complete": true,
    "observed_at": "2026-10-02T00:14:16Z",
    "session": {"logic_pid": 37546, "handshake_generation": 4,
                "handshake_at": "2026-10-02T00:14:10Z", "bank_offset": 4},
    "strips": 12, "bank_steps": 4, "attempts": 1,
    "end": "channel_right_and_bank_right_silent"
  }
}
```

| 項目 | 意味 |
|---|---|
| `source` | 値を読んだ経路。今は `mcu` |
| `scope` | 何を読んだか。`status`・`mixer_strips`（全ストリップ）・`mixer_strip`（1本） |
| `complete` | その範囲を最後まで読めたか。`false` の結果を全体の真実として使わない |
| `observed_at` | 読み取りを終えた時刻（UTC） |
| `session` | 値が属する接続。Logicのプロセス、接続の世代、接続した時刻、現在のバンク位置 |
| `strips` / `bank_steps` / `attempts` / `end` | 一覧の走査の内訳（一覧・`state` のみ） |

`session.handshake_generation` が変わったら、前に得た値は別の接続のものです。
`observed_at` と合わせて、結果を保存して比べるときの鮮度の目安にします。

## 3. トラック1本ごとの `null`

`track list` / `track get` / `state` の各トラックには、次の2つの配列が付きます。

| 配列 | 意味 | 例 |
|---|---|---|
| `unknown` | Logicがまだ報告していない値。`null` で返す | `["mute", "selected"]` |
| `unavailable` | そのストリップにはない値。`null` で返す | Masterの `["pan"]` |

- `solo`・`selected`・`rec_armed`・`mute` は、LEDをLogicが報告したときだけ `true` / `false` です。
- ソロが存在する間は、ミュートLEDが点滅して状態を断定できないため、`mute` は `null` で `unknown` に載ります。
  ソロ中かどうかは、見えているストリップのソロLEDと、全体のソロ表示で判定します。
- `volume_db` は、Logicのフェーダー値から求めます。値がなければ `null` で `unknown` に載ります。
- `name` はMCUの表示から読むため、**最大6文字・ASCIIだけ**です。
  6文字以上のときは `name_may_be_truncated: true` を返します。
  名前の変更を取り消した直後など、古いままのことがあります。
- `id` は**ミキサー上の位置**で、トラックの追加・削除・並べ替えがあると別のトラックを指します。名前も識別子にはなりません（同名がありえます）。
  各トラックの `identity` がこの性質を示します。書き込みで取り違えを防ぐには `--expect-name` を使います（[対象の契約](target-contract.md)）。

`status` と `state` の `transport.playing` / `transport.recording` も同じです。
Logicが再生・録音のLEDを報告するまでは `null` で、`false` ではありません。

## 4. 一覧・`state` が失敗する条件

`track list` と `state` は、全ストリップを読めたと**証明できたときだけ** `ok: true` です。

1. バンクを先頭に戻す（Bank Leftを、動かなくなるまで）。戻せなければ `bank_home_failed`。
2. Channel Rightで1つずつ進めながら読む。
3. 末尾の確認：Channel Rightに反応がなく、**別のボタン（Bank Right）にも反応がない**。
   反応がないだけでは、押下が失われた場合と区別できないためです。
4. Logic自身がバンクを動かしたと分かった場合（色の更新が想定より多い、読み取り中に動いた）は、
   そのバンクで読んだ分を捨て、最初からやり直します。やり直しは1回です。

証明できなければ、`ok: false`・`error: "scan_incomplete"` で、読めた範囲を `result` に入れて返します。
`observation.problem` に理由が入ります。

| `problem` | 意味 |
|---|---|
| `end_not_confirmed` | 末尾を確認できなかった。一覧は途中まで |
| `bank_moved_externally` | 走査中にLogicがバンクを動かし、番号を確定できなかった |

`bank_home_failed` と `scan_incomplete` のとき、`state` の `selected_track` は `null` で、
「選択なし」を意味しません。完全な走査で選択が見つからないときだけ、`null` が「選択なし」です。

読み取りには時間がかかります。末尾の確認で、反応がないことを0.8秒ずつ待つためです。
実測では、`track list` が約4秒、`track get` は1〜4秒です（Logic 12.3.1）。

## 5. 書き込みの「既にその状態」

送信を省ける書き込みは、**Logicが報告した状態**が要求と同じときだけ省きます。

- `transport play` / `stop`：再生と録音のLEDを、どちらもこの接続で受信するまで待ちます（最大1秒）。
  受信できなければ `readback_unavailable` で、何も送りません。停止を余計に送ると、位置が先頭に戻るためです。
- `track mute n off` など：LEDが未報告なら省略せず、押下後のLCD表示（`Muted` / `--`）で確認します。

## 6. 確認済みの範囲と限界

- 検証した環境は Logic 12.3.1（6682）・macOS 27.0・MCU経路です。
- 完全性の証明は「Channel RightとBank Rightの両方が0.8秒反応しない」という観測にもとづきます。
  Logicが負荷で0.8秒を超えて遅れる場合は、誤って末尾と判断する余地が残ります。
- 色の更新が移動ごとに1回であることは、実機の記録（EXP-MCU-020）にもとづく前提です。
  満たされない場合は、安全側に倒れて `scan_incomplete` になります。
- 名前の同一性（同名・並べ替え・削除）は、この契約の対象外です。[計画書のPLAN-08](../Research/plans/agent-ready-roadmap.md)で扱います。

根拠：[EXP-MCU-020](../Research/experiments/EXP-MCU-020-banking.md)・[EXP-MCU-021](../Research/experiments/EXP-MCU-021-last-strip-db-text.md)。
失敗の再現は、実Logicの挙動を写した模擬サーフェスのテスト（`Tests/LogicCoreTests/MCUObservationTests.swift`）で行います。
