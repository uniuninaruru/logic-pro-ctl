# SA-GUI-CREATE-002: observed creation labels to current callback records

Logic **12.4 / 6707, arm64** statically binds the exact `Create Pattern Region`
and `Create Session Player Region` titles to callback `0x00690ad4`, with stored
selectors **3 and 2**. This replaces the historical address for this build;
the preserved 12.3.1 analysis remains separate.

日本語: 空のレーンで観測された作成項目と同じ英語キーから、現行版の
タイトル・処理関数・引数の組を確認した。Pattern は3、Session Player は2。
実機での作成結果と、右クリックからこの初期化処理へ入る経路は未検証。

## Build and observation boundary

The [current identity](binary-identity-12.4-6707.json) records the installed
app/framework metadata, UUID and thin-image SHA-256
`48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda`.
An identical separate copy is preserved locally. No current Ghidra import or
shared-project job was used. Historical addresses belong to
[12.3.1 / 6682](binary-identity-12.3.1-6682.json).

Claude's CLDE077 saved four dismissed context menus from `LogicCLI-Test`:
empty lane, track header, MIDI region body and region edge. The files contain
12/24/22/22 rows; body/edge item dictionaries agree within those samples.
The two empty-lane creation items were enabled and were not invoked. The
capture's inherited `12.3.1 (6682)` label was not independently checked;
installed-file metadata does not identify the image used for that observation.
The English/Japanese experiment templates now require a measured running version.

## Current static route

| Exact title key / observed Japanese label | Catalog name | ID | Current static record | Stored argument |
|---|---|---:|---|---:|
| `Create Pattern Region` / パターンリージョンを作成 | `Create Pattern Region/Cell` | 151 | `0x025e7140` | 3 |
| `Create Session Player Region` / Session Playerリージョンを作成 | `Create Session Player Region/Cell` | 150 | `0x025e7168` | 2 |

Both 40-byte registration records rebase their callback slots to
`0x00690ad4`. `dyld_info -fixups` independently confirms the name/callback
targets. Their enclosing command group was not re-established.

The exact non-`/Cell` title objects also occur outside the handler, in the
current function-start interval `0x0101ef34..0x01021a8c`. Only a **328-byte
window** was inspected. At `0x01020c7c` and `0x01020c9c`, it passes each title
pair, callback `0x00690ad4`, and selector3/2 to `0x0026c624`.

That **96-byte initializer** stores a 16-bit tag10 at record+8, callback at
`+0x10`, retained title-pair fields at `+0x18/+0x20`, and selector at `+0x28`.
Its retain calls are linked to the current `_objc_retain` import. Thus title,
callback and stored argument have a direct static binding; Japanese-value
equality alone is no longer the sole link. The Pattern undo key sharing the
same Japanese value does not establish which GUI path executed.

The handler's current function-start interval is **1368 bytes**, ending at
`0x0069102c`. Its input-x2 branches distinguish2/3 and reference the same exact
title objects. Another path selects `w21=0x10,w22=0` for2 and
`w21=0x20,w22=1` for3, then forwards x2 to helper `0x00675134`.
These are register constants, not proved region-type enum values. Passing a
record's stored selector into handler x2 still requires current dispatch-ABI proof.

## Checks and next trace

The [machine-readable evidence](gui-region-creation-12.4.json) retains source
hashes, records, title references, fixup targets and limits. **47/47**
[anchors](../protocol/gui-create-12.4-anchors.tsv) pass byte and required-tool
checks. All **342+82+24 instruction words** in the three bounded listings also
match the preserved current image. No full CI run is needed for these notes.

Next, establish the tag10 callback invocation and the GUI gesture entering this
initialization path, then observe one creation and Undo in the test project.
Creation effects, feature applicability, cursor position, selection semantics,
MIDI-trigger equivalence and remote invocation remain unverified.
