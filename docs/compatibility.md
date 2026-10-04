# 対応する環境と、公開してよい範囲

[日本語](compatibility.md) | [English](compatibility.en.md)

[仕様に戻る](specification.md) · [読み取りの契約](observation-contract.md) · [実行の契約](execution-contract.md) · [対象の契約](target-contract.md) · [README](../README.md)

`logicctl` が**実際に確かめた環境**はどこまでか、どの操作をどこまで確かめたか、公開してよいと言える条件は何か、をまとめます。
機械可読の一覧は [`Research/protocol/support-matrix.tsv`](../Research/protocol/support-matrix.tsv) です。

## 1. 要点

- 確かめた環境は **Logic 12.3.1（6682）・macOS 27.0・arm64** の 1 つだけです。これ以外は「動かない」のではなく、**検証していない**扱いです。
- `logicctl status` の `result.compatibility` が、今の組み合わせを検証済みかを答えます。**分からないときは `null`** で、`false` でも `true` でもありません。
- 検証していない環境でも、コマンドは止めません。**結果を検証済みのものとして扱わない**ための表示です。書き込みは、これまでどおり読み戻しで確認します。
- 実機で確かめた操作と、静的解析だけの領域は、はっきり分けます（§4）。静的解析だけの領域を「対応済み」とは書きません。

## 2. 検証済みの環境

| 項目 | 値 |
|---|---|
| Logic | 12.3.1（ビルド 6682） |
| macOS | 27.0（26A5416b） |
| CPU | arm64 |
| 実機の試験に使うプロジェクト | `LogicCLI-Test.logicx` だけ（制作用のプロジェクトでは行わない） |

## 3. `status` の `compatibility`

```json
"compatibility": {
  "verified_profiles": [{"logic_version": "12.3.1", "logic_build": "6682", "macos": "27.0"}],
  "host_macos": "27.0",
  "logic_build_verified": true,
  "macos_verified": true,
  "profile_verified": true,
  "note": "検証済みの組み合わせです。"
}
```

| フィールド | 意味 |
|---|---|
| `verified_profiles` | 検証済みの組み合わせの一覧 |
| `host_macos` | この Mac の macOS（メジャー.マイナー） |
| `logic_build_verified` | Logic の版とビルドが、一覧のどれかと一致するか。**Logic が動いていない、または版を読めないときは `null`** |
| `macos_verified` | macOS（メジャー.マイナー。パッチの版は無視）が一覧にあるか |
| `profile_verified` | **Logic と macOS の組が**一覧にあるか。片方だけ一致しても `false`。`null` は判断できない |

- 版が違っても、ビルド番号が同じだけでは検証済みになりません（版とビルドの**両方**が一致したときだけ）。
- `profile_verified` が `true` でないときは、`note` を読んで結果を参考値として扱ってください。

## 4. 領域ごとの対応状況

状態の語彙：

| 状態 | 意味 |
|---|---|
| `live` | 実機（専用プロジェクト）で確かめ、試験もある |
| `tested` | 試験（単体・統合。偽の相手を使う）で確かめた。実機では確かめていない |
| `static` | 静的解析だけ。実機の通信・動作は確かめていない |
| `unconfirmed` | 試したが成立しなかった、または未確認 |
| `not_started` | 未着手（承認待ちを含む） |
| `other` | 別の担当の資料に従う |

現在の件数（[support-matrix.tsv](../Research/protocol/support-matrix.tsv) の行）：`live` 16、`tested` 3、`static` 4、`unconfirmed` 2、`not_started` 2、`other` 1（計 28 行）。

**MCU 経路のコマンド 11 個**（`status`、`state`、`transport play`、`transport stop`、`track list`、`track get`、`track select`、`track mute`、`track solo`、`track volume`、`track pan`）は、
すべて実機で確かめています（[EXP-CLI-001](../Research/experiments/EXP-CLI-001-v0.1-dod-transcript.txt)）。
**Logic Remote の領域は、すべて静的解析だけ**です。新しい接続は、ユーザーの承認が出るまで行いません。

この件数は「確かめた行 / この表の行」です。Logic 全体のうち何割を理解したか、という数ではありません。

## 5. 副作用（読み取りを含む）

「読む」ことは、画面や surface に影響しないことを意味しません。

| コマンド | Logic の状態 | MCU の表面への影響 |
|---|---|---|
| `status` | 変えない | なし |
| `track list`、`state` | 変えない | **表示範囲（バンク）を先頭へ戻し、末尾まで進める** |
| `track get` | 変えない | 位置合わせでバンクを動かす。**dB を読むためフェーダーのタッチを送る**（値は動かさない） |
| `track select` | **選択を変える。自動録音待機が有効だと、録音待機も動く** | 位置合わせでバンクを動かす |
| `track mute`、`solo`、`volume`、`pan` | 要求した値を変える | 位置合わせでバンクを動かす |
| `transport play`、`stop` | 再生状態を変える | なし |
| `--expect-name` つき | 一致しなければ何も送らない | 位置合わせのためにバンクは動くことがある |

バンクの移動は、Logic の画面の表示（ミキサーの見え方）にも影響することがあります（Logic が追従して表示範囲を動かす例を、EXP-MCU-023 で確認）。

## 6. 古い daemon・古い CLI

- `logicd` を古いまま動かしていると、新しいオプション（`--idempotency-key`、`--expect-session`、`--deadline-ms`、`--expect-name`、`--backend appleevent`）を
  黙って無視して、安全装置なしで実行してしまいます。`logicctl` は、これらを指定された要求の前に `status` で対応を確認し、
  対応していなければ **何も送らずに** `daemon_upgrade_required` を返します（[実行の契約](execution-contract.md)、試験：`test_cli_safety_gate.py`）。
- 古い `logicctl` から新しい `logicd` へは、追加のフィールドを持たない従来の要求がそのまま通ります（互換）。
- 通信の**版番号**は、まだありません。機能の有無は `status` の `capabilities` で判断します。
  版番号の導入は、将来の互換性の約束が必要になったときの課題です。

## 7. 公開の段階と、現在の判定材料

公開の段階（[計画](../Research/plans/agent-ready-roadmap.md) §10）ごとの条件と、現在の状況です。**公開してよいかの判断は、ここでは行いません**。判断のための事実を並べるだけです。

| 段階 | 公開できる内容 | 条件 | 現在 |
|---|---|---|---|
| A：基本操作 | 既存の transport／mixer の CLI | unknown、鮮度、一覧の失敗、対象参照、副作用、互換性を検証 | unknown・一覧の失敗・鮮度：`live`。対象参照：名前変更・追加・削除は `live`、**並べ替えは未確認**、同名は区別できない。副作用：§5 に記載。互換性：§3。実行契約：`live`／`tested` |
| B：広い読み取り | 完全な名前、領域別の state、Remote の snapshot・watch | 初回・差分・0/false・再接続・曲の切替の検証 | **満たしていない**（Remote は静的解析だけ。受信実験が未着手） |
| C：制作操作 | 検証済みの send／plugin／automation／region の操作単位 | 共通の実行 gate、複数値・複数対象、誤対象の防止、保存・再読込、Undo の限界 | **満たしていない**（この対応表に載せていない） |
| D：agent 運用 | MCP、batch、長時間 job、許可範囲内の自律操作 | schema の発見、競合・timeout・重複・部分失敗、成果物の確認 | **満たしていない**（MCP adapter は未実装） |

### 公開前の共通の確認（毎回）

- `swift test`、`python3 Tests/integration/*.py`、`Tools/research-scripts` の試験がすべて通る。
- 公開する操作ごとに、対象の環境・入力・単位・事前条件・読み戻し・副作用・失敗時の挙動・根拠（実験記録または試験）が文書にある。
- 文書は日本語と英語がそろい、リンクが有効である。
- `verified: true` は、読み戻した状態が要求と一致したときだけ。未取得・古い・部分的な値を、0・false・成功に読み替えていない。
- 静的解析だけの内容を「対応済み」と書いていない。未確認のものは未確認と書いている。
- 検証していない環境と古い daemon を、検証済み・別経路の成功として扱っていない。

## 8. 限界

- 検証済みの環境が 1 つだけです。別の macOS・別の Logic の版・別の CPU では、結果が違う可能性があります。
- 「一度確かめた」ことは、「いつでも再現する」ことではありません。多くの実機の確認は 1〜数回の実行です（各実験記録の「再現回数」を参照）。
- `tested`（偽の相手による試験）は、実機の挙動を保証しません。偽の相手は、確かめた実機の挙動を写したものです。
