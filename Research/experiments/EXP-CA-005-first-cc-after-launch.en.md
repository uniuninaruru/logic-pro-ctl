[日本語](EXP-CA-005-first-cc-after-launch.md) | [English](EXP-CA-005-first-cc-after-launch.en.md)

# EXP-CA-005: is the first CC 23 after Logic starts ignored? (inconclusive: the port is shadowed by a Mackie Control surface)

| Item | Value |
|---|---|
| Date | 2026-10-20 23:53–23:58 UTC (2026-10-21 08:53–08:58 JST) |
| Logic version | 12.4 (build 6707), from the running app's Info.plist; app name "Logic Pro Creator Studio", pid 7274 |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | A new untitled project "名称未設定 6", used with the user's approval (the file `LogicCLI-Test.logicx` no longer exists in the home folder). Not saved |
| Initial state | One track, Ballad (selected), audio-effect slot 1 = Channel EQ. Master Gain AX value 240 of 0–480, "0.0 dB". Pickup mode on (Settings > Control Surfaces > General, checked). Transport stopped |
| One operation | Send CC 23 (`B0 17 vv`) one value at a time on the virtual port `logicctl-cc`, the input of the existing CC 23 → Channel EQ Master Gain row, and read Master Gain through Accessibility about 1.5 s later |
| Expected change | From PICKUP-CONSUMER-001 F4–F6 (written before sending, `Research/raw/ca005/prediction.txt`): #1 = 60 ignored (first message after the startup reset), #2 = 66 applied (+0.9 dB) |
| Repetitions | 3 sends (60, 66, 64), plus one send of 64 with the Controller Assignments window open |

## What Apple's official guide says

- Controller Assignments Expert view (ctls71c3162b, guide 12.3, checked 2026-10-21): assignments in "No zone" are always active; selecting a mode in the list makes that mode active in the selected zone.
- General control-surface settings (lgcp1fe673ef): Pickup mode.

## Observation

| # | Time (UTC) | Sent | Master Gain after 1.5 s |
|---|---|---|---|
| — | 23:53:40 | marker only; the `B0` line was lost (FIFO reopen race in the probe; no TX logged) | 240, 0.0 dB |
| 1 | 23:54:20.042 | `B0 17 3C` (60) | 240, 0.0 dB |
| 2 | 23:54:29.461 | `B0 17 42` (66) | 240, 0.0 dB (**prediction failed**) |
| 3 | 23:54:53.989 | `B0 17 40` (64) | 240, 0.0 dB |
| 4 | 23:58:16.238 | `B0 17 40` (64), Controller Assignments window open | 240, 0.0 dB |

- O1: none of the sends changed Master Gain. Ballad's volume stayed +0.0 dB (AX 173 of 0–233).
- O2: with the Controller Assignments window open, send #4 made the window show the matching assignment: zone **VPots**, row **VPot 8** (label `@tp`, class Channel Strip, channel strip "Fader bank 8", parameter Fader, input `logicctl-cc`, message `B0 17 Lo7`, format signed magnitude). The learned CC 23 → Master Gain row was not shown.
- O3: 17 ms after send #4 Logic sent a Mackie Control LCD update (`F0 00 00 66 14 12 31 …`) to `logicctl-cc`. Logic also sent Mackie device queries to the port when it appeared.
- O4: the zone list now contains "Control Surface: Mackie Control", "Control Surface: Mackie Control #2" and "Control Surface: logicctl-research-peer". The preferences file grew from 316,820 bytes / 2,992 RDAF records (2026-10-08 copy) to 790,042 bytes / 7,984 records.
- O5: in the copied preferences, the old CC 23 → Master Gain row (input `logicctl-cc`) changed since 2026-10-08 at payload offsets 1, 15, 30–31 and 42; offsets 30–31 (Assign +0x56) went from 0xffff to 0x0012 on all four CC 20–23 rows.
- Raw data (not in Git): `Research/raw/ca005/` (`probe.log`, `prediction.txt`, `read1..3.json`), `Research/raw/cs-diff/s3.bin`.

## Verification stages

1. MIDI sent: confirmed (TX lines in `probe.log`, except the lost first attempt).
2. Assignment in Logic: the message was matched to the Mackie Control VPot 8 row, not to the learned Master Gain row (O2).
3. Value: unchanged (AX). The prediction about the startup reset is **not tested**.

## Hypothesis

Hypothesis: a Mackie Control surface was installed on the port name `logicctl-cc` between 2026-10-08 and now, and its VPot 8 assignment (CC 23) takes the message before the generic row. With one track, "Fader bank 8" has no target, so nothing changes.
Confidence: high for "the message goes to VPot 8" (O2, O3); low for when and how the surface was installed.
Counterexample to look for: a send that changes Master Gain on `logicctl-cc` while the Mackie surface stays installed.
Next experiment: EXP-CA-006 (learn the same parameter on a new port name).
