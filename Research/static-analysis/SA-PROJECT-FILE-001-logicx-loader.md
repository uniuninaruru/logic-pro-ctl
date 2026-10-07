# SA-PROJECT-FILE-001: LogicXのバージョン分類と読込wrapper

[日本語](SA-PROJECT-FILE-001-logicx-loader.md) · [English / 詳細](SA-PROJECT-FILE-001-logicx-loader.en.md) · [12件の事実・根拠・限界](../protocol/logicx-loader-boundaries.tsv) · [証拠manifest](project-loader-manifest.json)

**確認したのは、バージョンを分類するclass methodと、読込処理を委譲するinstance wrapperの2本文です。** `Alternatives` directoryの存在で返す4は分類の枝で、native `ProjectData`をparseした結果ではありません。3/4の意味と比較calleeは未読です。（P019-01〜04）

`Alternatives` directoryがない経路では、lowercase `projectData`をNSKeyedUnarchiverで読み、`Version`を55000との比較calleeへ渡します。`DfDocumentSystem`はNSStringとしてdecodeしますが内容比較に使わず、`CbVersion`の返値も保存しません。native uppercase `ProjectData`のmagic/header/schemaは未確定です。

読込wrapperにはmetadata設定、ARA migration、variant変更、条件付きbackup moveがあります。未読helperの**実返URL**をnative data loaderへ渡し、その成功後にsongのbitを更新し、条件に応じてdisplayを読みます。`usedAutoSave` byteはcallerで事前初期化されません。（P019-05〜11）

成功末尾には`tmp`削除と条件付きmetadata書込みがあり、loadの無副作用は保証できません。native parser、実URL・動的dispatch、失敗・例外・完全なrollback、保存・再読込・Undoの往復は未確認です。（P019-12）

根拠はLogic12.3.1/build6682の**2定義・2276bytes・569命令ワード**です。version本文780bytesは非連続で、span808bytes・gap28bytesです。021の旧prefix hashはfull-body証明ではなく、019の明示range unionが優先されます。取得済み証拠を再利用し、凍結checkerは再実行していません。全事実は`runtime_verified=false`、`product_capability=false`です。

保存済み専用テストpackageの別観察022では、`Alternatives`が存在しlowercase `projectData`はなく、native `ProjectData`とbackup2件を確認しています。これは保存ファイルの観察であり、parserの受理・実URL・未保存live状態の証明ではありません。詳細とprovenanceはEN本文・manifestにあります。
