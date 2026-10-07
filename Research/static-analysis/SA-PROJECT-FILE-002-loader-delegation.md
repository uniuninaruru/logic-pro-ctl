# SA-PROJECT-FILE-002: 版番号の比較と読込の委譲

[日本語](SA-PROJECT-FILE-002-loader-delegation.md) · [English / 詳細](SA-PROJECT-FILE-002-loader-delegation.en.md) · [6件の事実・根拠・限界](../protocol/logicx-loader-delegation-boundaries.tsv) · [証拠manifest](project-loader-delegation-manifest.json)

**023は3本文・364bytes・91命令ワードを照合しました。** signed32の版番号比較、読込先receiver、URL作成へ渡すpathを確認した静的結果です。

比較はdocument<10000なら10000倍の低32bitを使います。normalized>currentのとき、current+5000以上で1、次にcurrent+1000以上で2、それ以外は0です。current=55000では55001〜55999も0になります。0/1/2の意味・版番号encodingは未確定で、演算は32bit wrapです。（P023-01〜02）

116bytesの読込wrapperは、`unilibDocManager`の**実返receiver**へ元URLと出力pointerを渡し、実返値をそのまま返します。同名selectorをself再帰と読むことはできません。wrapperに`usedAutoSave` byteの初期化・内容書込みはありません。（P023-03〜04）

172bytesのURL helperは、深いresolver `015e9a6c`の**実返path**を`NSURL.fileURLWithPath:`へ渡します。nil入力・nil resolver返値はnil経路ですが、元URLのpath getterがnilでもresolverは呼びます。resolver本文・path選択・flag契約は023では未読です。（P023-05〜06）

native parser、実dispatch・URL、出力pointer契約、保存・再読込・Undoは未確認です。019 checkerを再実行せず、023用のoffline検査だけを行いました。全事実は`runtime_verified=false`、`product_capability=false`です。
