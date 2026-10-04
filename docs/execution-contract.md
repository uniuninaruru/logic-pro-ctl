# 書き込みの実行契約 — 再送・時間切れ・競合・停止

[日本語](execution-contract.md) | [English](execution-contract.en.md)

[仕様に戻る](specification.md) · [読み取りの契約](observation-contract.md) · [README](../README.md)

`logicd` は、すべてのコマンドを1つの**実行器**に通します。
目的は一つです。**結果が分からない操作を成功にせず、同じ操作を2回実行しないこと**です。
エージェントは、応答が消えた・時間切れになった・再送した場面でも、何が起きたかを判断できます。

## 1. 三つの安全装置（すべて任意）

| オプション | 守ること |
|---|---|
| `--idempotency-key <キー>` | 同じ操作の再送を1回の実行にまとめる。状態を変更するコマンドだけ |
| `--expect-session <世代>` | 読み取った時点の接続のままのときだけ実行する |
| `--deadline-ms <ミリ秒>` | 待ち時間と実行の上限。省略時は30秒 |

キーは英数字と `. _ : -` の1〜128文字です。読み取りコマンドには付けられません（`usage`）。

起動中の `logicd` が古く、これらのオプションに対応していないと、指定した安全装置なしで書き込みが実行されてしまいます。
`logicctl` は、安全装置を指定された要求の前に `status` で対応を確認し、対応していなければ **何も送らずに** `daemon_upgrade_required` を返します。
`logicctl daemon stop` のあとに再実行すると、新しい `logicd` が起動します（`--expect-name` も同じです。[対象の契約](target-contract.md)）。

## 2. 応答の `execution`

すべての応答に、実行の扱いを示す `execution` が付きます。

```json
{"ok": true, "verified": true,
 "execution": {"state": "replayed", "idempotency_key": "mute-1-on",
               "queue_wait_ms": 0, "replayed_from": "2026-10-02T00:20:05Z"}}
```

| `state` | 意味 | 次にすること |
|---|---|---|
| `completed` | 実行し、状態を確認できた | なし |
| `replayed` | 同じキーの記録済みの結果を返した。Logicには何も送っていない | なし |
| `read` | 読み取りを実行した | なし |
| `not_applied` | Logicに届く前に失敗した。キーはそのまま再利用できる | 原因を直して再実行 |
| `rejected` | 実行を始めなかった（理由は `error`） | 理由に従う |
| `unknown` | **実行された可能性がある**。結果を確認できていない | 状態を読み直す。必要なら**別のキー**で実行 |

## 3. 重複（冪等キー）

実行の前後で、キーごとに記録（ジャーナル）を残します。内容は、コマンド・引数・経路から作る指紋です。

| 状況 | 結果 |
|---|---|
| 新しいキー | 実行して記録 |
| 同じキー・同じ内容で、前回が確認済み | **再実行せず**、前回の結果を `replayed` で返す |
| 同じキー・**違う内容**（引数や経路が違う） | `idempotency_key_conflict`。実行しない |
| 同じキーの操作が実行中 | `request_in_flight`。待たずに返す |
| 同じキー・前回の結果が不明 | `outcome_unknown`。**自動では再実行しない** |
| 同じキー・前回がLogicに届く前に失敗（`not_applied`） | 再実行する |

「結果が不明」になるのは、確認済みでも、届かなかったと分かる失敗でもないときです。
たとえば `verification_failed`（送ったが状態が違う）や時間切れです。
届かなかったと分かる失敗は、`logic_not_running`・`surface_not_connected`・`invalid_argument`・`usage`・`unknown_command`・
`no_such_track`・`bank_unknown`・`bank_home_failed`・`precondition_failed`・`target_mismatch`・`unsupported_*`・`daemon_upgrade_required` です。
それ以外の失敗は、安全側に倒して不明として扱います。例：`readback_unavailable` は、
操作の前後どちらで起きたかを区別できない経路があるため、不明に含めます。

ジャーナルは `~/Library/Application Support/logicctl/journal.jsonl`（環境変数 `LOGICCTL_JOURNAL`）に追記され、
`logicd` を再起動しても残ります。新しい500件ほどを保持します。

**キーなしの再送は、重複を防げません。** 応答が消える可能性がある操作には、キーを付けてください。

## 4. 時間切れと応答の消失

実行には締め切りがあります。締め切りを過ぎると、`logicd` は `timeout`（`execution.state: "unknown"`）を返します。

- Logicへの操作そのものは**止められません**。裏で終わるまで続きます。
- その間、次のコマンドは**重なって実行されません**（実行枠は1つ。終わるまで次は待つ）。
  例外は `status` だけです。`status` は daemon がすでに持っている情報を返すだけで、表面を動かさず、書き込みもしないため、実行枠を待たずに答えます
  （`logicctl` が安全装置つきの要求の前に送る確認が、長い書き込みの終了を待たないようにするため）。
- 裏で操作が**確認済みで終わる**と、記録が `completed` に更新され、同じキーの再送は `replayed` で結果を返します。
  確認済みで終わらなければ、`unknown` のままです。
- 待ち時間の上限を過ぎたときは、`deadline_exceeded` で**実行を始めません**（`rejected`）。
- 待機が多すぎるときは `queue_full`（上限8）。

## 5. 古い読み取りに基づく書き込み（`--expect-session`）

読み取りの `observation.session.handshake_generation` は、Logicとの接続の世代です。
書き込みに `--expect-session <世代>` を付けると、**接続の世代が違うときは送信せず**に
`precondition_failed`（`rejected`）を返します。Logicが再接続・再起動した場合や、未接続の場合です。

```sh
logicctl track list                     # observation.session.handshake_generation を控える（例: 4）
logicctl track mute 3 on --expect-session 4 --idempotency-key mute-3-on-001
```

この前提が保証するのは**接続の同一性**までです。接続の中でほかの人が値を変えたかどうか（リビジョン）は検出できません。
曲の切り替えは、Logicが接続をやり直すときに限って検出されます。

## 6. 停止と再起動

- `daemon stop` や終了シグナルのとき、実行中の書き込みは `unknown`（`daemon_stopped`）として記録されます。
  以降のリクエストは `shutting_down` で拒否されます。
- `logicd` が異常終了して、実行中の記録が残った場合は、次の起動時に `unknown`（`daemon_restarted`）にします。

## 7. 限界

- 実行を途中で取り消せません。時間切れは「待つのをやめた」ことを表します。
- 「届かなかった」の判定は、エラーコードの一覧にもとづきます。新しいエラーコードは不明側に倒れます。
- `exactly-once` は約束しません。約束するのは、**同じキーで確認済みの操作を2回実行しない**ことと、
  **不明な実行を成功にしない**ことです。
- ジャーナルはこのMacのこのユーザーのものです。複数のMacやユーザーでは共有されません。
- Logicを人が操作して状態が変わる場合は、前提の `--expect-session` では検出できません。

根拠となるテスト：`Tests/LogicCoreTests/WriteExecutorTests.swift`（重複・競合・時間切れ・再起動・停止・前提）。
