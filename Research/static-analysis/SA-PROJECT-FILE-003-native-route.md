# SA-PROJECT-FILE-003: native入力の判定と曲パスの選択

[English / 詳細](SA-PROJECT-FILE-003-native-route.en.md) · [13事実・命令anchor・限界](../protocol/logicx-native-route-boundaries.tsv) · [証拠manifest](project-native-route-manifest.json)

**3本文・4388bytes・1097命令ワードを照合しました。** 曲ファイル先頭の比較と、自動保存データを選ぶ静的経路を確認しました。完全なファイル形式・実dispatch・読込成功は未確認です。

2つの読込実装は出力pointerの扱いが異なります。8bytesの本文は1を返すだけですが、CLgDocManagerは非nilの`usedAutoSave`とerrorを初期化します。実際にどちらが呼ばれるかは未確定です。（N01）

native readerは先頭LE32の4値を比較し、専用曲の`23 47 c0 ab`も一致します。legacy converterが返す値により元データ・変換後データ・失敗へ分岐します。bytes+6の64bit値やbytes+22のhelperも見えましたが、fieldの意味とschemaは未確定です。`getBytes:range:`の引数はlocation=22/length=0で、22bytesのcopyとは呼べません。（N02〜05）

resolverは`logicx/band/grid`とvariantに応じて`ProjectData`を選び、別候補`documentData_lowmem`が存在するとモーダルを呼ぶ経路があります。数値1001→nil、1002→通常、他→低メモリ候補です。flag=1は選択候補nilのみで、初期directory不正・最終file不在・最終directoryはnil/flag=0です。（PATH01〜08）

resolverのflagとreaderの`usedAutoSave`は別です。内部状態・モーダルを扱うため、純粋な読取りとして使えるとは確認していません。実機ではこれらを呼んでおらず、全事実は`runtime_verified=false`、`product_capability=false`です。
