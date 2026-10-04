[日本語](manual-validation.md) | [English](manual-validation.en.md)

# 人の手で確認してほしいこと

**まず、専用テストプロジェクトでトラック 5 と 6 を一度だけ入れ替えてください。** 前後の JSON・MIDI・Logic の取り消し履歴を合わせると、並べ替えが MCU の表示と名前照合に届くかを調べられます。これまでの合成マウス操作など 8 回では並べ替えを起こせず、[EXP-MCU-023](../Research/experiments/EXP-MCU-023-add-delete-reach-surface.md) では未確認です。

| 優先 | 人にお願いしたいこと | 得られる根拠 |
|---|---|---|
| 1 | `LogicCLI-Test.logicx` で 5・6 を手動で入れ替える | 実際の並び、取り消し履歴、前後の LCD・JSON・MIDI |
| 2 | 別の macOS / Logic バージョンで、同じ条件の観測結果を報告する | バージョンによる違い。未取得の値や失敗もそのまま報告 |

## 1. 操作前に観測の準備をする

実験は **`LogicCLI-Test.logicx` だけ**で行います。名前・音量・ミュート・ソロ・録音待機を変更せず、初めに選択されているトラックも控えます。前回の終了時の選択は `Trk06` でしたが、今回は実際の画面と JSON で確認してください。操作前の取り消し履歴の末尾も控え、履歴を閉じてから観測を準備します。

操作前の取り消し履歴で最後の数項目を控え、パネルを閉じます。操作後に、新しい並べ替え項目が増えたかを比較するための基準です。

エージェントと一緒に行うなら、「テストプロジェクトを開いた。並べ替え準備ができた」と伝え、トレースと操作前の記録がそろった合図を待ってください。前回のトレース用 daemon は停止済みなので、起動中とは仮定しません。

自分で記録する場合は、リポジトリのルートで以下を実行します。release ビルドがなければ、先に `swift build -c release` を実行します。ここで作るフォルダは実行ごとに変わり、Git の追跡対象外です。

```sh
manual_run_dir="Research/raw/mcu-trace/manual-reorder-$(TZ=Asia/Tokyo date +%Y%m%d-%H%M%S)"
mkdir -p "$manual_run_dir"
sw_vers > "$manual_run_dir/macos.txt"
git rev-parse HEAD > "$manual_run_dir/logicctl-commit.txt"
.build/release/logicctl daemon stop > "$manual_run_dir/daemon-stop-before.json"
.build/release/logicd --trace > "$manual_run_dir/daemon.stdout.log" 2> "$manual_run_dir/trace.log" &
manual_trace_pid=$!
```

トレースのログに「接続を待っています」が出るまで待ちます。起動に失敗したら並べ替えには進みません。

```sh
tail -n 12 "$manual_run_dir/trace.log"
.build/release/logicctl status --backend mcu > "$manual_run_dir/status-ready.json"
.build/release/logicctl track list --backend mcu > "$manual_run_dir/tracks-before.json"
.build/release/logicctl state --backend mcu > "$manual_run_dir/state-before.json"
```

`status-ready.json` の `result.daemon.pid` が `$manual_trace_pid` と同じで、`result.mcu.connected` が `true` であることを確認します。CLI は daemon がなければ自動起動するため、別 PID ならトレース準備をやり直します。

`tracks-before.json` の `result` 配列で、位置 5・6 の `name` と `identity.name_unique` を確認します。以下のコマンド例は、**返された名前が実際に `Trk05` / `Trk06` で、両方が一意だった場合だけ**使います。5 文字の ASCII 名を使い、短縮や同名による区別の失敗を避けます。違う名前なら、実際に返された短い一意の名前へ例を直してください。条件を満たせない場合は、名前を変更せず準備不足として記録します。

一覧と state の `ok` / `observation.complete` が `true` かも確認します。`null` や不完全な観測を 0・オフと読み替えません。

## 2. 人が 5 と 6 を入れ替える

先に位置 5 を読み、操作直前の LCD と時刻を保存します。`track get` / `track list` は MCU の表示範囲を動かすことがあるので、この後は操作が終わるまで実行しません。`status` は現在の LCD の写しを返します。

```sh
.build/release/logicctl track get 5 --expect-name Trk05 --backend mcu > "$manual_run_dir/track5-before.json"
.build/release/logicctl status --backend mcu > "$manual_run_dir/status-before.json"
date -u '+BEFORE_SWAP %Y-%m-%dT%H:%M:%SZ' >> "$manual_run_dir/markers.txt"
```

1. Logic を前面にし、トラック 5・6 の名前と現在の順序を見ます。
2. 人のマウスでトラック 6 をトラック 5 の上へ移します。`M` / `S` / 録音待機ボタンに触れない位置から操作してください。
3. 名前の並びが `Trk05 → Trk06` から `Trk06 → Trk05` になったかを見ます。変わらなければ「並べ替え未発生」と記録し、成功扱いにしません。

## 3. 表示を動かす前に、操作直後の記録を取る

入れ替えたら他の操作をせず、短く待ってから次を実行します。**最初は `status`** で、位置合わせの前に LCD を保存します。

```sh
date -u '+AFTER_SWAP %Y-%m-%dT%H:%M:%SZ' >> "$manual_run_dir/markers.txt"
.build/release/logicctl status --backend mcu > "$manual_run_dir/status-after.json"
.build/release/logicctl track get 5 --expect-name Trk05 --backend mcu > "$manual_run_dir/old-name-check.json"
.build/release/logicctl track get 5 --expect-name Trk06 --backend mcu > "$manual_run_dir/new-name-check.json"
.build/release/logicctl track list --backend mcu > "$manual_run_dir/tracks-after.json"
.build/release/logicctl state --backend mcu > "$manual_run_dir/state-after.json"
```

古い名前で `target_mismatch`、新しい名前で一致するかを**調べる**手順です。結果が違っても書き換えず、返った JSON を残します。これらは読み取りによる照合で、ミュートを書き込む試験は行いません。

記録を取った後で Logic の取り消し履歴を開き、並べ替えに対応する新しい項目があるかを確認します。項目の実際の文言・前後の並び・操作時刻を控えてください。履歴を開く操作もトレースに影響し得るため、swap 直後の記録と区別します。画面の並びも履歴も変わらなかった場合は、今回も未確認です。

## 4. 元に戻し、結果を共有する

対応する並べ替えが取り消せる場合だけ Undo します。Undo できるとは保証しません。取り消せなければ、同じテストプロジェクトで手動で元の順序に戻し、その方法を記録します。元の順序と初めの選択を確認し、名前・音量・ミュート・ソロ・録音待機が操作前と一致するかを見ます。選択に伴う録音待機の変化や誤操作があった場合は、それも記録して画面で元へ戻します。

```sh
.build/release/logicctl state --backend mcu > "$manual_run_dir/state-restored.json"
.build/release/logicctl daemon stop > "$manual_run_dir/daemon-stop-after.json"
wait "$manual_trace_pid"
```

**この実験ではプロジェクトを保存しません。** 未保存の変更・履歴が残る可能性は記録してください。通常の daemon が必要なら、トレース停止後に `.build/release/logicctl status --backend mcu` で起動できます（環境変数 `LOGICD_TRACE` を有効にしていない場合）。

共有するのは、操作が起きたか、前後の順序と照合結果、MIDI の観測範囲、再現回数、戻した状態です。1 回だけの結果を全環境への保証にはしません。詳細は [実験テンプレート](../Research/experiments/TEMPLATE.md) にまとめ、[貢献ガイド](../CONTRIBUTING.md) または [調査 Issue テンプレート](../.github/ISSUE_TEMPLATE/research.md) から共有できます。生ログは手元に残し、必要最小限の匿名化した例を添えます。

別バージョンの報告では macOS、Logic の version / build、`logicctl` の commit、同じ専用プロジェクトでの初期状態と返った JSON を添えてください。上のコマンドで macOS と commit は保存されます。Logic の version / build は「Logic Pro について」の表示も確認して記録します。この手順に新しい AppleEvent 送信や Logic Remote 接続の実験は含めません。
