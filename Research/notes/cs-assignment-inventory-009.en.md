# CS-INVENTORY-009: bounded copied-assignment fingerprints

[Research guide](../README.md) · [Validation JSON](cs-assignment-inventory-009.json) · [Parser](../../Tools/research-scripts/cs_assignments.py) · Static basis: [ASSIGN-FIELDS-007](assignment-fields-007.en.md), [ASSIGN-IDENTITY-008](assignment-identity-audit-008.en.md)

日本語要約：保存コピーの読み取り専用ツールに解析結果を反映した。可変長フィールドを長さ・重複・終端まで検査し、EQ型の対象候補について「プラグイン種類のハッシュ・同じ種類の中での順番・インスタンス識別データのハッシュ」を比較できる。実際に選択される対象や値の検証とは分離し、未確認フラグを維持する。設定への書き込み・復元処理は追加していない。

## Behavior

`cs_assignments.py list COPIED_FILE` still requires an explicit copied MROF/FCSS snapshot, rejects the live preferences file and aliases, and checks declared file length by default. Names, raw identifiers and payload contents remain omitted. No product backend, MIDI behavior, `verified` capability or CI configuration changed.

The narrowly recognized CC candidate shapes retain their fixed-prefix conditions and tag sequence **1, 3, optionally 6, 16**. The old one-byte optional-field skip is replaced by a bounded MSB-first base-128 parser. Each length must fit the remaining payload and a five-group/32-bit limit. Duplicate tags, redundant leading zero groups, unterminated lengths, missing terminators and trailing bytes reject the candidate. These rules deliberately accept less than Logic's inspected malformed-input scan; they are evidence-integrity checks, not a compatibility specification for arbitrary settings.

Every recognized candidate now includes `variable_field_lengths`. A `stored_plugin_target_candidate` is added only for the already recognized class-5 shape, parameter family `(code & 0xffffc000) == 0x4000`, and an **exactly 32-byte tag 6**. It contains:

| Field | Meaning within the static 12.4/6707 mapping |
|---|---|
| `descriptor_sha256` | Hash of the first 12 bytes; compare stored plug-in descriptor data without exposing its words |
| `ordinal_raw` | Raw unsigned word at +0xc; an ordinal candidate, not an absolute GUI slot |
| `instance_token_sha256` | Hash of the last 16 bytes; useful to distinguish stored instances, but the selected-track route need not use this token |
| `selector_raw`, `parameter_code_raw` | Existing copied-prefix probes associated with this candidate |
| `static_version_scope` | Explicitly limits the interpretation to the audited Logic 12.4 / 6707 mapping |
| `status`, `active_target_confirmed`, `value_verified` | `hypothesis`, `false`, `false` |

A new instance with the same descriptor can produce the same descriptor hash and ordinal but a different instance-token hash. None of these comparisons establish the current document, selected track, plug-in instance, assignment activity or requested parameter value. `semantics_confirmed` remains false.

## Validation

The affected suite passes **26 tests**. Five added cases cover redaction and false verification flags, same descriptor with a changed instance/ordinal, rejection of wrong class/family/identity length, multibyte length boundaries (127/128/255/16384), and ambiguous/truncated/overflowing variable tails. Existing live-path/alias rejection, flat chunk boundaries, file-length guards, multiplicity-aware diffs and CLI checks still pass.

The actual CLI was also run on historical `s0b.bin` (SHA-256 `d80b27bb49b6c65e7841a36a5e6ee95dafdb61e7ab110605a75e20600de331f4`). Comparing with its prior saved CLI output preserves **all 2992 raw RDAF records**, the **4 recognized CC rows**, and all earlier candidate fields. Exactly **one** row now has a stored plug-in target candidate: raw code `0x4020`, ordinal 0. Its active-target and value-verification flags are false.

```sh
python3 -m unittest discover -s Tests/research -p test_cs_assignments.py
python3 Tools/research-scripts/cs_assignments.py list /absolute/path/to/copied-snapshot.bin
```

The validation JSON records tool/test/reproducer hashes and redacted counts. Complete CLI outputs stay in ignored `Research/raw/rea/codex-assignment-inventory-009/`. This is a research inventory improvement; write/restore automation and same-target live readback remain separate work.
