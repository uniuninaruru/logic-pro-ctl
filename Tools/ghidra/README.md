[日本語](README.md) | [English](README.en.md)

# Ghidra の調査を順番に実行する

同じ Ghidra プロジェクトを使う headless 解析は、**1 件ずつ**実行します。読み取り専用の `-readOnly` でも同じルールです。
`with-project-lock.py` は、参加するコマンドが共有のロックを取ってから実行し、終了まで保持するためのラッパーです。

```text
エージェント A ── 同じロックを取得 ── 解析 ── 終了・解放
エージェント B ── 同じロックを待つ ────────── 取得 ── 解析
```

## 同じプロジェクトには同じ絶対パス

`analyze.sh`・`appleevents.sh`・`query.sh`・`cfstrings.sh`・`stackstores.sh` は、このラッパーを使います。既定のロックは、そのチェックアウトの `Research/raw/ghidra/logicctl-project.lock` です。
**別の worktree / チェックアウトから同じ Ghidra プロジェクトを使う場合は、`GHIDRA_LOCK` を同じ絶対パスにそろえてください。** 既定値のままでは、チェックアウトごとに別のロックになります。

例として、共通の場所にロックを置きます。すべての参加者が同じ値を使います。

```sh
export GHIDRA_LOCK="$HOME/GhidraProjects/logicctl/headless-coordination.lock"
Tools/ghidra/query.sh Logic.arm64 query-example 0x001a1dcc
```

別のスクリプトや直接の `analyzeHeadless` 呼び出しも、同じラッパーを通します。

```sh
python3 Tools/ghidra/with-project-lock.py --lock "$GHIDRA_LOCK" -- \
  /path/to/analyzeHeadless /path/to/projects logicctl \
  -process Logic.arm64 -noanalysis -readOnly \
  -scriptPath "$PWD/Tools/ghidra" \
  -postScript XrefDecompile.java "$PWD/Research/raw/ghidra/query-example.c" 0x001a1dcc
```

パスとプログラム名は手元の環境に合わせてください。ロックは全参加者が通したコマンドにだけ作用します。Ghidra の UI やラッパーを通さないコマンドまで制御するものではありません。

## Ghidra 自身のロックも尊重する

このロックは、Ghidra 自身のプロジェクトロックに追加する調整です。**Ghidra のロックを削除・無視・迂回しないでください。** 解析が待っているときは、先行ジョブのログと実行状態を確認します。動作中に共有ロックファイルを消すと、別のロックとして扱われて同時実行になるため、このファイルも削除しません。

ラッパーの「取得」表示は、コマンドを実行する順番が来たことを示します。解析が成功したかは、最新の Ghidra ログと出力を確認してください。調査の生出力は Git の追跡対象外の `Research/raw/` に置きます。

## ラッパーだけを確認する

```sh
python3 Tools/ghidra/test_project_lock.py
```

このテストは合成した子コマンドを使い、同時実行の防止・終了コード・標準出力・コマンド未指定を確認します。子プロセス群への終了シグナルの伝達と、ラッパーが強制終了しても子が保持するロックも検証します。Ghidra や Logic Pro を起動しません。

ロックの継承は、子や後続プロセスが継承したファイル記述子を保持する場合に有効です。独自のランチャーでその記述子を閉じる場合は、同じ保証にはなりません。
