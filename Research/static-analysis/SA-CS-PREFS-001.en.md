# SA-CS-PREFS-001: bounded, read-only controller-assignment snapshots

日本語概要: コントローラー設定のコピーを読み、レコード単位の差分を取得するツールを追加した。追加後のコピーには長さの不整合があり、通常の読み取りでは拒否する。バイト列の候補、GUIで確認した割り当て、実際の値の変化を別々の証拠として扱う。設定ファイルへの直接書き込みや復元は行わない。

Machine-readable evidence: [SA-CS-PREFS-001.json](SA-CS-PREFS-001.json).
Baseline live experiment: [EXP-CS-001](../experiments/EXP-CS-001-prefs-file-live-diff.en.md).
These independently checked byte facts qualify that experiment's initial layout interpretation; they do not establish a persistence API.

## Official behavior and scope

Apple documents selecting a plug-in or mixer parameter, choosing **Learn Assignment**, sending controller input, then ending Learn mode. Expert View exposes additional assignment fields. [Easy View, guide 12.3](https://support.apple.com/guide/logicpro/assign-and-delete-controllers-in-easy-view-ctls71c31855/12.3/mac/15.6), [Expert View, guide 12.3](https://support.apple.com/guide/logicpro/controller-assignments-expert-view-ctls71c3162b/12.3/mac/15.6).

The [control-surface setup guide](https://support.apple.com/ja-jp/guide/logicpro/ctls718ddead/mac) identifies `com.apple.logic.pro.cs` as the control-surface settings file. The [general settings guide](https://support.apple.com/ja-jp/guide/logicpro/lgcp53689108/mac) says application settings are saved on quit and settings should be changed inside Logic. This does not establish that the CS file is written **only** on quit. EXP-CS-001 observed changes while Logic 12.4 (6707) kept running. The guide version and installed version differ.

This work reads the four existing experiment copies. It neither quits Logic nor edits live preferences. Names, opaque identifiers and complete payloads remain in ignored local evidence. Restoration means re-creating and validating an assignment through Logic's GUI in a future experiment, never overwriting this file.

## Independently checked framing

All offsets are zero-based; spans end exclusive. `MROF` is at 0, a little-endian unsigned 32-bit declared body length at 4, and `FCSS` at 8. Flat records begin at 12: four raw type bytes, a little-endian 32-bit payload length, then that many payload bytes. The copies walk to EOF without padding or nested-record interpretation. This is an observed layout, not a complete format specification.

| Copy | Size | Declared body length | Actual size minus 8 | Flat records / RDAF | Strict structure |
|---|---:|---:|---:|---:|---|
| s0 | 316620 | 316612 | 316612 | 3036 / 2992 | Valid |
| s0b | 316820 | 316812 | 316812 | 3036 / 2992 | Valid |
| s1_1 | 316941 | **4** | **316933** | 3037 / 2993, forensic | **Rejected** |
| s2 | 316820 | 316812 | 316812 | 3036 / 2992 | Valid |

The cause of the `s1_1` mismatch is unknown. A concurrent write is a possible explanation, not an observation. Explicit forensic reading uses actual EOF and retains `snapshot_valid: false`; it never repairs the copy or confirms an assignment from it. Even a structurally valid copy does not prove that its opaque records are active assignments or identify the current target.

## Record multiset differences

The comparison uses raw type, payload length and SHA-256, retaining duplicate counts. Offsets are evidence locations, not persistent IDs. A changed payload is represented as one removal plus one addition.

| Before → after | Added / removed RDAF payloads | Unchanged | Meaning established |
|---|---:|---:|---|
| s0 → s0b | 5 / 5 | 2987 | Raw change around observed port appearance; not five new assignments |
| s0b → s1_1 | 2 / 1 | 2991 | Forensic-only registration-associated delta |
| s1_1 → s2 | 1 / 2 | 2991 | Forensic-only reverse delta |
| s0b → s2 | 0 / 0 | 2992 | All RDAF payloads restored as a multiset; whole files differ |

The registration-associated delta contains a new 113-byte RDAF payload at record offset **14714**, SHA-256 `41f74ee59e166992b3eb404856354554019d14022ec206ceece1810c6fdce51f`. Its raw little-endian word at payload **+6** is **748** and bytes at **+48** are `B0 19 F5`. GUI evidence identifies the learned CC25 operation as Loop Browser; 748 matches the historical **12.3.1** command catalog. Current 12.4 command dispatch, numeric class interpretation and serialization-to-memory conversion remain unproved.

A separate existing 119-byte payload changes **exactly one byte**, payload **+1: 0x99 → 0x19**, while moving from record offset 14714 to 14835. This explains the second added hash and removed hash. The flag's meaning is unknown. It is inaccurate to describe the raw difference as exclusively one added record with every existing assignment record unchanged.

## Observed parameter-row candidates

The narrow parser recognizes four mode-2 shape candidates in `s0b`. They are near 14.7–15.1 KB, not the file tail. CC labels below come from corresponding GUI observations; message bytes alone cannot establish the assignment, input port or target. An independent broad fixed-offset message comparison finds 157 matches across the same copy, including other shapes.

| GUI-associated CC | Record offset | Payload bytes | Raw u32 LE +2 | Raw u32 LE +6 | Bytes +48..50 | Bytes +42..45 |
|---|---:|---:|---:|---|---|---|
| 23, EQ Master Gain | 14714 | 119 | 5 | `0x40201000` | `B0 17 F5` | `F2 00 00 00` |
| 22, Volume | 14841 | 88 | 5 | `0x00071000` | `B0 16 F5` | `2A 00 00 5A` |
| 21, Pan | 14937 | 76 | 5 | `0x000a1000` | `B0 15 F5` | `64 00 00 00` |
| 20, fixed Pan | 15021 | 76 | 5 | `0x000a1000` | `B0 14 40` | `01 00 00 00` |

The parser emits these as **hypotheses**, with `semantics_confirmed: false`. It does not turn family 5 into a current-version class enum or decode +6 as a universal parameter ID. Its candidate counts are s0/s0b/s1_1/s2 = 0/4/5/4; zero means no match to this narrow shape, not no assignments.

## Connection to existing reverse engineering

[SA-MIDI-ROUTE-001](SA-MIDI-ROUTE-001.en.md) independently binds current `WrappedAssign` getters to machine instructions. In-memory offsets `assignmentClass +0x3a`, `befehl +0x3e` (signed 16-bit), `valueMode +0x4b & 7`, and `multiply +0x4c` (signed 16-bit × 0.01) belong to an **in-memory structure**. The serialized u32 at payload +6 has a different location and width. No decoder/deserializer connecting these fields has been traced here.

Current `valueChangeHasLo7` / `valueChangeHasHi7` scan stored spans for internal `F5` / `F4`. The copied `F5` bytes and GUI Lo7 display are consistent with those getters. These markers are internal pattern bytes, **not** MIDI bytes to send on the wire. Matching, target resolution, replacement behavior and value readback still need independent proof.

## Reproducer and checks

Use explicit **copied** snapshots:

```sh
python3 Tools/research-scripts/cs_assignments.py list COPIED.bin
python3 Tools/research-scripts/cs_assignments.py diff BEFORE.bin AFTER.bin
# Forensic inspection only; keeps an invalid snapshot warning:
python3 Tools/research-scripts/cs_assignments.py diff BEFORE.bin AFTER.bin --allow-length-mismatch
python3 -m unittest discover -s Tests/research -p test_cs_assignments.py
```

JSON stdout, diagnostics stderr; no write/restore API. Live preferences and aliases to them are rejected. File / payload / record limits are 16 MiB / 1 MiB / 10000. The candidate decoder validates its observed prefix, bounded UTF-8/NUL field and full suffix; it does not scan nested byte substrings.

**21 synthetic tests pass**, including malformed lengths, truncation, limits, duplicate multiplicities, reordering, bounded candidates, invalid strings, live-file aliases and nonblocking FIFO rejection. Real strict s0b reading succeeds; strict s1_1 exits 2 with empty stdout; explicit forensic comparison retains the invalid warning. A second independent framing/diff walk imports no parser code. Snapshot and tool hashes are in the companion JSON.

Next acceptance criteria: [MIDI assignment and Channel EQ milestone](../plans/midi-assignment-automation-001.en.md). This reader provides a bounded inventory/diff foundation; GUI restoration and an automated verified EQ operation are **pending**.
