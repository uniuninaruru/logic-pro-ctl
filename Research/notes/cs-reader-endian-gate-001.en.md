# CS-READER-001: how Logic 12.4 reads the control-surface file header and byte order (static)

[Research guide](../README.md) · [Instruction anchors](../protocol/cs-reader-12.4-anchors.tsv) · Related: [EXP-CS-001](../experiments/EXP-CS-001-prefs-file-live-diff.en.md), [ASSIGN-IDENTITY-001](assignment-identity-callbacks-001.en.md)

日本語要約：コントロールサーフェス設定ファイルの読み込み関数を、Logic 12.4 の複製から静的に読んだ。起動時の読み込みと「割り当ての読み込み」は同じ関数を使う。先頭 12 バイトの組み合わせで 4 つの読み方（モード 0〜3）を決め、ビット 0 はチャンク ID の反転、ビット 1 は長さと数値フィールドの反転を意味する。手元のコピー（'MROF'＋'FCSS'）はモード 0 で、反転しない。ヘッダーに書かれた全体長は使われず、実際のファイル長 − 12 が読む範囲になる。推論であり、実行時の確認ではない。

## Scope and identity

| Item | Value |
|---|---|
| Image | Preserved copy `Research/raw/binaries/Logic12.4-6707.arm64`, sha256 `48862b9190f182b28bd87d7c8b15bd37516af58842debe52609c49ce5ed2bcda` |
| Tools | REA 6.7.0 with Ghidra 12.1.4 (retained session), llvm-objdump; 35 of 35 anchors hold (`binary_anchors.py`) |
| Evidence | Static only; Logic was not running; the MAFiles framework was not imported (only its imported names in Logic's stubs are used) |
| Requested by | Codex (leader), board CDEX158 |

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

## Proof limits

- Read at operand level; not audited by Codex yet.
- What `FUN_00ad4fa8` does with each startup chunk was not read here (Codex audited its RDAF path earlier).
- Which file `FUN_00ad4bb4` opens (the global file reference at 0x26c1660) was not traced.

## Raw data (not in Git)

`Research/raw/rea/`: `x0xaa194c.objdump.txt`, `x0xad7c30.objdump.txt`, `x0x97f48c.objdump.txt`, `x0xabe67c.objdump.txt`, and REA JSON results.
