# CS-READER-001: how Logic 12.4 reads and writes the control-surface file (static)

[Research guide](../README.md) · [Instruction anchors](../protocol/cs-reader-12.4-anchors.tsv) · Related: [EXP-CS-001](../experiments/EXP-CS-001-prefs-file-live-diff.en.md), [ASSIGN-IDENTITY-001](assignment-identity-callbacks-001.en.md)

日本語要約：コントロールサーフェス設定ファイルの読み込み関数を、Logic 12.4 の複製から静的に読んだ。起動時の読み込みと「割り当ての読み込み」は同じ関数を使う。先頭 12 バイトの組み合わせで 4 つの読み方（モード 0〜3）を決め、ビット 0 はチャンク ID の反転、ビット 1 は長さと数値フィールドの反転を意味する。手元のコピー（'MROF'＋'FCSS'）はモード 0 で、反転しない。ヘッダーに書かれた全体長は使われず、実際のファイル長 − 12 が読む範囲になる。書き出し側では、割り当て本体の先頭 0x66 バイトのうち 0x38 以降と、空でないリスト 1〜16 を「ID 1 バイト・7 ビット区切りの長さ・中身そのまま」で並べ、最後に 0 を 1 バイト付ける。リスト 6（プラグインの識別子 32 バイト）も作り直さずにそのまま書く。固定トラック方式の割り当てはこのファイルに書かれない。推論であり、実行時の確認ではない。

## Scope and identity

| Item | Value |
|---|---|
| Image | Preserved copy `Research/raw/binaries/Logic12.4-6707.arm64`, sha256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda` |
| Tools | REA 6.7.0 with Ghidra 12.1.4 (retained session), llvm-objdump; 58 of 58 anchors hold (`binary_anchors.py`) |
| Evidence | Static only; Logic was not running; the MAFiles framework was not imported (only its imported names in Logic's stubs are used) |
| Requested by | Codex (leader), board CDEX158 (reader) and CDEX160 (writer) |

## Findings

| # | Finding | Anchors | Status |
|---|---|---|---|
| R1 | One chunk reader, `FUN_00aa194c(file, block, …)`, serves both the startup load (`CLgAppManager::appManager_applicationWillFinishLaunching` → `FUN_00a8ed50` → `FUN_00ad4bb4`, global block with invoke `FUN_00ad4fa8`) and `ControllerAssignmentsController::importCustomAssignments:` (block invoke `FUN_00ad7c30`). A whole-image scan found no other direct call | CR001–CR005 | Observation |
| R2 | It reads 12 bytes (form id, size, form type) with `CFileIO::Read` and picks a mode from the pair, comparing raw little-endian words: 'MROF' + 'FCSS' → 0, 'RIFF' + 'SSCF' → 1, 'FFIR' + 'FCSS' → 2, 'FORM' + 'SSCF' → 3 (file byte order shown). Any other pair reports "File … is not a … File!" (through `FUN_0058a59c`) and stops | CR006–CR016 | Observation |
| R3 | Bit 0 of the mode byte-swaps each chunk tag before the callback; bit 1 byte-swaps each chunk size (and the header size). So bit 0 means "chunk ids in readable order" and bit 1 means "sizes big-endian" | CR017, CR022–CR025 | Observation (swaps); Inference (names) |
| R4 | The header size is not used to bound the read. It is overwritten by `CFileIO::GetEOF` − 12, and a chunk that runs past that budget logs "IFF file size specification does not match" and stops reading; chunks already handled are kept | CR018–CR020, CR026 | Observation (stores, branch); Inference (that earlier results are kept, from the callback pushing into a vector) |
| R5 | The mode is stored at reader +0xcc and the current chunk's byte budget at +0xc8. The assignment decoder `FUN_00abe67c` reads at most the remaining chunk bytes and, only when bit 1 of +0xcc is set, byte-swaps the fixed numeric fields (class +0x3a, selector +0x3e, code +0x40, and three more) | CR021, CR030–CR035 | Observation |
| R6 | The import callback accepts tag 'FADR' (file bytes "RDAF" in mode 0) through the decoder and handles 'CMP ' separately; other tags are skipped | CR027–CR029 | Observation |

## Consequences for our tools

- The copies we hold ('MROF' + 'FCSS') are mode 0: tags as little-endian words, sizes and numeric fields little-endian. Codex's parser assumptions match this mode only; other modes would need swaps.
- Logic itself does not check "header size = file size − 8". Our stricter rule (reject a copy whose header size disagrees) is a consistency guard for copies taken while the file is being rewritten, not Logic's acceptance rule. A copy like `s1_1` might still be accepted by Logic if its chunks fit in the file.

## Writer side

The serializer `FUN_0085d538` (3,136 bytes) has three callers: the file writer `FUN_00abe8d4`, `FUN_00aadad4` and `FUN_00abd8ec`. Only the parts that build the fixed part and emit the lists were read (excerpts within 2 KiB), not the whole body.

| # | Finding | Anchors | Status |
|---|---|---|---|
| W1 | The buffer starts with the assignment's first 0x66 bytes, copied as they are. Then lists 1 to 16 follow in ascending id order (Assign +0x80 to +0x1e8, stride 0x18); a list is written only when it is not empty. Each list is one id byte, its length in 7-bit groups with the most significant group first and 0x80 set on every group except the last, and its bytes copied by `memcpy`. One zero byte ends the buffer | CR036–CR051 | Observation |
| W2 | The file writer writes an 8-byte chunk header and then the buffer from +0x38, so the payload is Assign +0x38 to +0x66 (0x2e bytes) followed by the lists. This matches Codex's reader proof that the lists start at payload +0x2e ([ASSIGN-FIELDS-007](assignment-fields-007.en.md)) | CR055–CR058 | Observation |
| W3 | List 6 (Assign +0xf8, the plug-in descriptor of [ASSIGN-IDENTITY-001](assignment-identity-callbacks-001.en.md)) is copied unchanged, whatever its length. The serializer does not rebuild the IDs, the ordinal or the UUID, so a saved 32-byte list 6 is the in-memory list at save time | CR043–CR048 | Observation |
| W4 | The file writer skips assignments of class 5 whose selector mode is 0xb000 (pinned to a track). Such assignments are not in this file; where they are stored was not traced | CR052, CR053 | Observation (branch); the storage elsewhere is unknown |
| W5 | Before serializing, the writer stores a controller word into the live assignment at +0x4e: 0 when the controller pointer at +0x30 is null, otherwise 0xff000000 plus the controller's index in a global list (0xfeffffff when it is not found) | CR054 | Observation (stores); Inference (meaning of the word) |

For our parser this means the list region can be walked as id/length/bytes records until the zero byte, and list 13 (the pin) should not appear in rows of this file.

## Proof limits

- Read at operand level; not audited by Codex yet.
- What `FUN_00ad4fa8` does with each startup chunk was not read here (Codex's [ASSIGN-STARTUP-010](assignment-startup-010.en.md) covers it).
- The serializer's other two callers and the filter callback used by the writer were not read.
- Which file `FUN_00ad4bb4` opens (the global file reference at 0x26c1660) was not traced.

## Raw data (not in Git)

`Research/raw/rea/`: `x0xaa194c.objdump.txt`, `x0x85d538.objdump.txt`, `ser0xabe8d4.objdump.txt`, `x0xad7c30.objdump.txt`, `x0x97f48c.objdump.txt`, `x0xabe67c.objdump.txt`, and REA JSON results.
