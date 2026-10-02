# 対象の契約 — トラック番号が指すもの

[日本語](target-contract.md) | [English](target-contract.en.md)

[仕様に戻る](specification.md) · [読み取りの契約](observation-contract.md) · [実行の契約](execution-contract.md) · [README](../README.md)

`track mute 3 on` の **3 は ID ではなく、ミキサー上の位置**です。
トラックの追加・削除・並べ替えがあると、同じ番号が別のトラックを指します。
このページは、書き込みが**読んだトラックとは別のトラックに届く**ことを防ぐための決まりをまとめます。

## 1. 要点

- トラック番号（`id`）は、ミキサーの並び順の位置です。読み取りのあとで並びが変わると、番号は別のトラックを指します。
- **`--expect-name <名前>`** を付けると、番号が指す位置に表示中の名前が一致するときだけ実行します。一致しなければ `target_mismatch` で、**何も送信しません**。
- 名前は、必ず `track list` / `track get` が返した `name` をそのまま渡します。
- 同じ名前が複数ある場合は、名前では区別できません。`track list` の `identity.name_unique` が教えます。
- 照合できるのは、**Logic がコントロールサーフェスへ表示を送ったとき**です。名前の変更は実機で確認しました。並べ替え・追加・削除は**未確認**です（§6）。

## 2. 使い方

```sh
logicctl track list                                   # name と identity を控える
logicctl track mute 3 on --expect-name Bass --idempotency-key mute-bass-on-001
```

`--expect-name` は `track get|select|mute|solo|volume|pan` で使えます（`track list`・`transport` では使えません）。
`--idempotency-key`（[実行の契約](execution-contract.md)）と組み合わせられます。

### 一致しなかったとき

```json
{"ok": false, "verified": false, "error": "target_mismatch",
 "requested": {"track": 3, "expect_name": "Piano"},
 "observed": {"track": 3, "name": "Bass", "identity_scope": "mixer_position"},
 "message": "トラック 3 の表示名は「Bass」で、期待した「Piano」と違います。…何も送信していません。",
 "execution": {"state": "not_applied"}}
```

- Logic の状態は変わりません。ただし、位置を合わせるために、MCU の表示範囲（バンク）は動くことがあります。
- 次にすること：`track list` で読み直し、狙うトラックを選び直します。
- 同じ冪等キーのまま名前だけ直すと、内容が違うため `idempotency_key_conflict` になります。**新しいキー**を使ってください。
  （照合を変えない再送は、`not_applied` なので同じキーで再実行できます。）

### 一致したとき

書き込みの `result` に、何を確認したかが入ります。

```json
"result": {"target": {"track": 3, "name": "Bass", "matched_expected_name": true, "identity_scope": "mixer_position"}}
```

## 3. 読み取りの `identity`

`track list` / `track get` の各トラックに付きます。

| フィールド | 意味 |
|---|---|
| `identity.scope` | `"mixer_position"`：`id` はミキサー上の位置 |
| `identity.stable_across_reorder` | `false`：並べ替え・追加・削除で変わる |
| `identity.name_unique` | `true`：完全な走査で、同じ表示名が他に無い／`false`：同じ表示名が複数ある／`null`：分からない |

`name_unique` が `null` になるのは、次のときです。

- `track get`（1 本だけ読むので、他のトラックを知らない）
- 走査が `complete: false` のとき（見ていないトラックが同じ名前かもしれない）

表示名は MCU の 7 文字のセルに収まる短い名前です（`name_may_be_truncated` も参照）。
7 文字を超える名前は切り詰められます。たとえば `Guitar L` と `Guitar R` がどちらも `Guitar` と表示されると、`name_unique: false` になり、`--expect-name` では区別できません（Logic が実際にどう短縮するかは名前によります。表示された `name` を見てください）。

## 4. 参照の寿命

| 参照 | 何を指すか | 有効な範囲 | 検出手段 | 根拠 |
|---|---|---|---|---|
| トラック番号 / `id`（MCU） | ミキサー上の位置 | 追加・削除・並べ替えまで | `--expect-name`（Logic が表示を更新するとき） | 名前変更：EXP-MCU-022。ほかは未確認 |
| 表示名（MCU） | 7 文字に収まる短い名前 | 名前変更まで。重複しうる | 比較のみ | 単体試験、実機 |
| `observation.session.handshake_generation` | Logic との接続 | Logic の再接続・再起動まで | `--expect-session` | [実行の契約](execution-contract.md) |
| Logic Remote の `trackID`・`gindex`・UUID | （Remote が使う識別子） | **寿命は未確認** | 使っていない | 静的解析のみ：[SA-REMOTE-STATE-001](../Research/static-analysis/SA-REMOTE-STATE-001.md) |

寿命が確認できていない参照を、確認済みのように扱いません。`logicctl` は、確認できた範囲（**接続中の位置と表示名**）だけを契約にしています。

## 5. 守れること・守れないこと

守れること：

- `--expect-name` が一致しないとき、**何も送信しません**（`target_mismatch`。単体試験、実機）。
- 書き込みが成功したとき、`result.target` に**確認した名前**が入ります。
- `logicctl` 経由では、古い `logicd` が `--expect-name` を黙って無視することはありません。`logicctl` は先に `status` で対応を確認し、
  対応していなければ `daemon_upgrade_required` で**何も送りません**（`--idempotency-key`・`--expect-session`・`--deadline-ms` も同じです）。

守れないこと（限界）：

- **同じ表示名のトラック同士の入れ替え**は検出できません。
- Logic が表示を更新しない変更は検出できません。この確認は、サーフェスに出ている表示と比べるだけです。
- 曲（プロジェクト）の名前は MCU から読めません。別の曲に切り替わっても、トラック名が同じなら一致します。
  接続が変わる切り替えは `--expect-session` で検出できます。
- フォルダー・スタックなど階層、インストゥルメント、インサート、プラグインの対象指定は、この契約の範囲外です（MCU は公開しません）。
- 読み取りと書き込みの**間**に人が操作することは防げません。照合は、書き込みの直前に位置を合わせたあとで行います。

## 6. 確認状況

| 変更 | 実機での確認 | 単体試験 |
|---|---|---|
| トラック名の変更（表示中のストリップ） | **確認済み**：EXP-MCU-022（`Zed5`、旧名は `target_mismatch`） | 〇 |
| トラックの並べ替え | **未確認** | 〇（Logic が表示を更新する、という仮定） |
| トラックの追加 | **未確認** | 〇（同上） |
| トラックの削除 | **未確認** | 〇（同上） |
| 表示外のストリップの名前変更 | 未確認（バンクを動かすと表示が書き直されるはず） | — |

未確認の項目は、実機で確かめるまで「検出できる」と書きません。単体試験は、**Logic が表示を更新するなら**
この照合が検出する、ことを示すだけです。

## 7. 根拠

- `Tests/LogicCoreTests/TargetIdentityTests.swift`（名前変更・入れ替え・削除・追加、全コマンドで未送信、重複名、切り詰め、引数の検証、冪等キーとの関係）
- `Tests/integration/test_cli_safety_gate.py`（古い daemon に安全装置つきの要求を送らない）
- [EXP-MCU-022](../Research/experiments/EXP-MCU-022-rename-reaches-surface.md)（実機：名前変更はサーフェスに届く）
