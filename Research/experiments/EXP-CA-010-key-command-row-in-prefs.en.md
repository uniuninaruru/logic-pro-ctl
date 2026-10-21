[日本語](EXP-CA-010-key-command-row-in-prefs.md) | [English](EXP-CA-010-key-command-row-in-prefs.en.md)

# EXP-CA-010: one key-command registration adds exactly one record to the preferences file, and deleting it removes it (PLAN-CA-005 T4)

| Item | Value |
|---|---|
| Date | 2026-10-21 00:29–00:31 UTC |
| Logic version | 12.4 (build 6707), pid 7274 |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | New untitled project "名称未設定 6" (not saved) |
| Initial state | Command "ループブラウザを表示/非表示" (Show/Hide Loop Browser): key O, no control-surface assignment. Valid copy `s6.bin` (7,985 RDAF records). Port `logicctl-gen` |
| One operation | Register CC 24 on the command in the Key Commands window, copy the file; then delete the assignment and copy again |
| Expected change | +1 record, then back (written before, `Research/raw/ca010/prediction-T4.txt`) |
| Repetitions | 1 |

## What Apple's official guide says

- Assign key commands (lgcp41ff6979, as in [EXP-KC-002](EXP-KC-002-midi-to-key-command-loop-browser.en.md)): select the command, press "Register New Assignment", send the controller's message; delete with "Delete Assignment".

## Observation

- O1: the window was opened with Logic Pro > キーコマンド > 割り当てを編集…; it is not reported as a regular window to the background tools. The search field was focused (cursor checked) before typing.
- O2: after pressing 新規割り当てを登録 and sending `B0 18 7F` / `B0 18 00` (00:30:04.530 / 05.038Z), the Control Surface column showed **CC 24** and the button turned off. The Loop Browser did not open. Nothing was sent after registration.
- O3: valid copies (header length = file size − 8): s6 7,985 RDAF → s7 **7,986** → after "割り当てを削除" s8 **7,985**. The set of list-16 tokens of s8 equals that of s6.
- O4: the added record: class (payload 2–5) **9**, payload 6–7 = **0x02ec (748)**, message list 1 = `B0 18 F5` (CC 24 Lo7), lists 1, 3, 16. It was the only record whose list-16 token was new.
- O5: a hash comparison of whole payloads marked about 7,500 records as changed between s6 and s7 although only one was added, so payload hashes are not a usable identity across rewrites; the list-16 token was.
- Raw data (not in Git): `Research/raw/cs-diff/s6.bin`, `s7.bin`, `s8.bin`, `Research/raw/ca010/`.

## Hypothesis

H1: one registration writes one RDAF record (class 9, command id at payload 6) and deletion removes it. Confidence: high for this command.
H2: list 16 is a per-assignment token that stays the same when the file is rewritten (supports Codex's ASSIGN-STARTUP-010 inference). Confidence: medium (one add/delete cycle).
Next: compare tokens across a Logic restart.
