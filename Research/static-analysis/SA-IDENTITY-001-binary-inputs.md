# SA-IDENTITY-001: バイナリ入力の同一性 — 元ファイル、arm64 slice、Ghidra import

[日本語](SA-IDENTITY-001-binary-inputs.md) · [English](SA-IDENTITY-001-binary-inputs.en.md) · [identity manifest](binary-identity-12.3.1-6682.json) · [開発計画](../plans/agent-ready-roadmap.md)

**MACoreの元Universalファイル全体と、Ghidraへimportしたthin arm64イメージのSHA-256は異なります。** 2026-10-02の再確認では、元ファイルのarm64 slice、解析copy、Ghidraの保存済みExecutable SHA-256は一致しました。Logicの元ファイルは既にthin arm64なので、元ファイル全体も同じhashです。

この記録はPLAN-01の**バイナリ識別部分だけ**です。全体の根拠index、protocol解析、peer接続、実機gate、製品実装の完了を意味しません。PLAN-01全体を完了にはしません。

## 対象と証拠

| 項目 | 確認した値 |
|---|---|
| 再確認日 | 2026-10-02、Asia/Tokyo |
| manifest記録時刻 | `2026-10-02T00:09:36.849240+00:00` |
| アプリ | Logic Pro Creator Studio 12.3.1 / build 6682、`com.apple.mobilelogic` |
| 環境 | macOS 27.0 / build 26A5416b、arm64 |
| インストール済み元ファイル | `/Applications/Logic Pro Creator Studio.app/Contents/Frameworks/{Logic,MACore}.framework/Versions/A/{Logic,MACore}` |
| 解析copy | `/Users/nagataharuto/GhidraProjects/logicctl/bin/{Logic,MACore}.arm64` |
| Ghidra project | directory `/Users/nagataharuto/GhidraProjects/logicctl`、project名 `logicctl` |
| Ghidra metadata | version `12.1.4`、language `AARCH64:LE:64:AppleSilicon`、compiler spec `swift`、image base `00000000` |
| 読み取りreport | [ProgramIdentityReport.java](../../Tools/ghidra/ProgramIdentityReport.java) |
| version付き記録 | [binary-identity-12.3.1-6682.json](binary-identity-12.3.1-6682.json) |

パス・アプリ名・環境は今回の観測値です。別環境の固定値や、対応buildの一般的な保証として使いません。

## 何と何を照合するか

1. インストール済み**元ファイル全体**のhashで、出典となるthin/universalファイルを識別する。
2. 元ファイル内の**選択したarchitectureのslice**を識別し、そのbytes、offset、長さ、UUID、hashを記録する。
3. そのsliceと**解析copy**のbytes、architecture、UUID、hashを照合する。
4. 対応するGhidra programから**保存済みExecutable SHA-256**を直接取得し、slice/copyのhashと照合する。program名・languageも記録する。

今回の必要な一致は `selected_slice.sha256 == analysis_copy.sha256 == ghidra_program.imported_executable_sha256` です。元Universalファイル全体のhashを、この式へ入れません。

| 対象 | 元ファイル全体のSHA-256 | arm64 sliceのSHA-256 | 解析copyのSHA-256 | Ghidraの保存済みExecutable SHA-256 |
|---|---|---|---|---|
| Logic | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| MACore | `76ab2a5f50b3ef120786369b5bf8b53dfc87a3b4107438e0894ab5f9b8095c52` | `99a4a9adbf79c92046682eb821d8ef35145f4915a29b88839c4f026ae63cd076` | `99a4a9adbf79c92046682eb821d8ef35145f4915a29b88839c4f026ae63cd076` | `99a4a9adbf79c92046682eb821d8ef35145f4915a29b88839c4f026ae63cd076` |

元ファイル内のslice位置とUUIDも、manifestで別々に記録しています。

| 元ファイル | architecture | slice offset（byte、元ファイル先頭基準） | slice長（byte） | Mach-O UUID |
|---|---|---:|---:|---|
| Logic：thin | arm64 | 0 | 40710736 | `641ea797-e5a3-3ff1-8188-b36067cf8361` |
| MACore：universal | x86_64 | 16384 | 2346464 | `0d8a684c-1991-3699-8602-70e453626582` |
| MACore：universal | arm64 | 2375680 | 2248544 | `c225c0d6-7d88-3bcc-a570-ebae658e1a6a` |

MACoreの元ファイル全体は4624224 bytesです。x86_64 sliceのSHA-256は `ed6674bc1e19bc64b53a23bd8a53d097248e3664db16b184342f3897f10edb05`。これは別architectureの識別値であり、今回の `MACore.arm64` importとの照合値ではありません。解析copyのUUIDは、選択した各arm64 sliceのUUIDと一致しました。

## Ghidra metadataの直接確認と限界

今回のreportは既存の `Logic.arm64`、次に `MACore.arm64` を、**1 processずつ** `-noanalysis -readOnly` で開きました。`ProgramIdentityReport.java` は `currentProgram.getExecutableSHA256()` を読み、指定したprogram名と期待する**slice hash**が一致しなければreportを書きません。元ファイル/copyの照合と、このGhidra metadataの読み取りは別々の証拠です。

ローカルの直接取得結果とheadless logは次の通りです。各ファイルのSHA-256はversion付きmanifestに記録しています。

- [Logic identity JSON](../raw/20261002T000630Z-binary-profile/Logic.arm64.identity.json) · [Logic headless log](../raw/20261002T000630Z-binary-profile/Logic.arm64.headless.log)
- [MACore identity JSON](../raw/20261002T000630Z-binary-profile/MACore.arm64.identity.json) · [MACore headless log](../raw/20261002T000630Z-binary-profile/MACore.arm64.headless.log)

保存済みExecutable SHA-256は**元のimport入力のmetadata**です。Ghidra databaseファイル自体のchecksumではなく、その後の型・ラベル・解析注釈が変更されていないことを保証しません。今回の一致はimport入力の同一性を裏付けますが、解析結果全体の完全性や意味の正しさを保証しません。

## 再確認の例

既存Ghidra projectを使う例です。リポジトリrootで、`GHIDRA_HEADLESS` は既存 `analyzeHeadless` の絶対パス、`JAVA_HOME` は利用するJava環境へ設定済みとします。以下の例はMACoreの**arm64 slice hash**を期待値に使います。Universal全体の `76ab2a5f…` は渡しません。

```sh
mkdir -p "$PWD/Research/raw"
identity_run=$(mktemp -d "$PWD/Research/raw/identity-recheck.XXXXXX")
"$GHIDRA_HEADLESS" "$HOME/GhidraProjects/logicctl" logicctl \
  -process MACore.arm64 -noanalysis -readOnly \
  -scriptPath "$PWD/Tools/ghidra" \
  -postScript ProgramIdentityReport.java \
  "$identity_run/MACore.arm64.identity.json" \
  MACore.arm64 \
  99a4a9adbf79c92046682eb821d8ef35145f4915a29b88839c4f026ae63cd076 \
  > "$identity_run/MACore.arm64.headless.log" 2>&1
```

programが見つからない、名前/hashが違う、reportが出ない場合は未確認として扱います。reportの成功だけで現在の元ファイル/copyも一致したことにはせず、別途照合します。汎用 `query.sh` にはhash guardがないため、固定addressのquery前にもこの確認が必要です。

同じGhidra projectでquery/report/import/更新を同時実行しません。read-onlyも1本ずつ順番に行います。別buildでは元ファイルとsliceのprofileを取り直します。生binary、decompile、Ghidra database、raw logはローカルに保持し、Gitへ追加するのは整理済み記録・manifest・report sourceです。

## この確認の範囲

今回の確認では、インストール済みbinaryの変更、Ghidra databaseへの変更保存、対象processへのattach、peer接続、AppleEvent/MIDI等のアプリ操作は行っていません。既存のAE/MCU経路に関する全体計画を変更する記録ではありません。

PLAN-05の新規peer接続は、2026-10-02のユーザー指定に従い、接続先と送受信範囲を示して明示承認を得た後に行います。静的解析とオフライン準備は先行できます。今回のidentity確認は、その接続の承認や成功を示すものではありません。
