[日本語](EXP-CS-002-tokens-across-restart.md) | [English](EXP-CS-002-tokens-across-restart.en.md)

# EXP-CS-002: the list-16 token of every assignment survives a Logic restart (copied preferences, read-only)

| Item | Value |
|---|---|
| Date | 2026-10-24 13:00 UTC (copy); compared with the copy of 2026-10-21 00:31 UTC |
| Logic version | 12.4 (build 6707); the running process changed from pid 7274 to pid 1628 between the copies (Logic was restarted by the user) |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | none used (no GUI or MIDI; only the preferences file was copied) |
| Initial state | `s8.bin` (2026-10-21, after [EXP-CA-010](EXP-CA-010-key-command-row-in-prefs.en.md)), 7,985 RDAF records |
| One operation | Copy `~/Library/Preferences/com.apple.logic.pro.cs` once, keeping it only when the header length equals the file size − 8 (`s9.bin`, file modified 2026-10-24 12:37 UTC) |
| Expected change | Hypothesis H2 of EXP-CA-010: list 16 is a stable per-assignment token |
| Repetitions | 1 |

## Observation

- O1: both copies have 7,985 RDAF records; every record has a list-16 token, tokens are unique, and the multiset of tokens is identical.
- O2: matching records by token, 490 payloads are byte-identical. In the others the differences are only at fixed-part offsets 15 (Assign +0x47, 7,495 records) and 38 (Assign +0x5e, 7,490 records), plus one record at offsets 1 and 42.
- O3: that one record is the CC 23 → Master Gain row on `logicctl-gen` ([EXP-CA-006](EXP-CA-006-learn-on-new-port.en.md)): flags byte (Assign +0x39) 0x81, stored value (+0x62) 0, i.e. bits 3–4 and the stored value cleared, as the loader reset predicts (Codex, PICKUP-CONSUMER-001 F6).
- Raw data (not in Git): `Research/raw/cs-diff/s8.bin`, `s9.bin`.

## Hypothesis

H1: list 16 identifies an assignment across file rewrites and Logic restarts. Confidence: medium-high (two rewrites, one restart, all 7,985 records).
H2: Assign +0x47 and +0x5e are volatile (rewritten on save for almost every row) and must not be used for identity. Confidence: medium.
Next: tools that read or restore assignments should key on list 16; test whether a copy/paste of an assignment gets a new token.
