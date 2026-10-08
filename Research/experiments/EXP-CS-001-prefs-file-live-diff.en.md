[日本語](EXP-CS-001-prefs-file-live-diff.md) | [English](EXP-CS-001-prefs-file-live-diff.en.md)

# EXP-CS-001: the control surface preferences file is rewritten while Logic runs (adding and deleting one assignment)

| Item | Value |
|---|---|
| Date | 2026-10-08 02:55–08:05 UTC (the operations were 03:00–03:02 UTC; interrupted in between) |
| Logic version | 12.4 (build 6707), recorded from the running process's Info.plist |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (stopped, not saved) |
| Initial state | Logic kept running. The parameter assignments (CC 20–23) are present. The file was only read, never written |
| One operation | Copy the preferences file `~/Library/Preferences/com.apple.logic.pro.cs` at three points and compare: (1) before and after a virtual MIDI port appeared, (2) right after registering one MIDI assignment on a key command, (3) after deleting that assignment |
| Expected change | Apple says settings are saved when Logic quits, so nothing should change while it runs |
| Repetitions | 1 |

## What Apple's official guide says

- Around "set up control surfaces" (ctls718ddead): assignments and settings are stored in `com.apple.logic.pro.cs`, saved when Logic quits. Changes are made inside Logic; no method of editing the file directly is given.
- This experiment **wrote nothing**.

## Observation

- O1 (format): not a plist but a custom binary. The first 4 bytes are `MROF`, the next 4 are the file length (−8), then a `FCSS  SG` header. There are many `RDAF` tags (2,992). The size is 316,620 bytes. A copy from the day before (before the second MCU unit was removed) was 560,836 bytes with 5,486 `RDAF` tags.
- O2 (rewritten while running): without quitting Logic, the file's modification time and size changed.
  - Right after creating a virtual MIDI port: +200 bytes (316,620 → 316,820).
  - About 1 s after registering one MIDI assignment on a key command: +121 bytes (→ 316,941).
  - After deleting that assignment: back to 316,820 bytes.
- O3 (what registration added): at about 14.7 KB from the start, one `RDAF` record (113-byte payload) appeared. It holds a command number (a 4-byte integer, value **748**: Loop Browser, the same number Codex saw in the 12.3.1 catalog), the message `B0 19 F5` (`F5` is the `Lo7` marker, matching the internal marker Codex found by static analysis), a length-prefixed UTF-8 display name (with NUL), and a 16-byte identifier (not recorded here).
- O4 (restoration after deletion): after deletion the file is the same size as before registration and **differs in 78 bytes** (around 13,122–13,200, the same place that changed when the port appeared; they look like time or counter fields). The record added by the registration is gone.
- O5: the records of the parameter assignments (rows CC 20–23) are in the later part of the file and did not change in this experiment.
- Raw data (not in Git; contains device names): `Research/raw/cs-diff/` (`s0.bin` before the port, `s0b.bin` after, `s1_1.bin` after registering, `s2.bin` after deleting).
- Operating note: during the session a mistaken click and text input went to another app (text was left in ChatGPT's input box). It did not affect this experiment's results.

## Hypothesis

H1: assignment information can be obtained by reading this file while Logic is running (reflected about 1 s after registering). Confidence: medium-high (one add and delete; not done for a parameter row).
H2: because deleting returns the file to its original size, the result of adding or deleting through the GUI is restored in a fixed form. Confidence: medium (the 78-byte difference looks like time or counter fields, not confirmed).
H3: the stored command number (748) directly links the on-screen name (key command) to the internal number. On 12.4 it equals the 12.3.1 catalog (one example, one command). Confidence: medium.
H4: writing the file directly is outside Apple's procedure and was not verified. Confidence: n/a (not done).

## Next experiments

1. Compare the later part of the file for adding and deleting a parameter assignment (for example CC 21) by the same method.
2. Replace the Channel EQ slot with another EQ and check what the CC 23 row resolves to, on screen and in the stored record (target identification).
3. Build a read-only listing tool in `Tools/` (class, message, display name and number per record) and test it on synthetic data.
