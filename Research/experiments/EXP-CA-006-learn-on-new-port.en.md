[日本語](EXP-CA-006-learn-on-new-port.md) | [English](EXP-CA-006-learn-on-new-port.en.md)

# EXP-CA-006: learn CC 23 → Channel EQ Master Gain on a new port with the GUI, then verify three values

| Item | Value |
|---|---|
| Date | 2026-10-21 00:01–00:09 UTC (09:01–09:09 JST) |
| Logic version | 12.4 (build 6707), pid 7274 |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | New untitled project "名称未設定 6" (user approved; not saved) |
| Initial state | As EXP-CA-005: Ballad selected, Channel EQ in slot 1, Master Gain 240 / "0.0 dB", Pickup on. New virtual port `logicctl-gen` (no assignment used it before) |
| One operation | Learn CC 23 for Master Gain with Apple's Easy-view procedure, then send single values on `logicctl-gen` |
| Expected change | Values follow −24 + v·48/127 dB (EXP-CA-004), predictions written before sending (`Research/raw/ca006/prediction.txt`) |
| Repetitions | Learn twice (run 1 failed, see O2); 3 single values in run 2 |

## What Apple's official guide says

- Assign controllers in Easy view (ctls71c31855, guide 12.3, checked 2026-10-21): select the parameter in a plug-in window, choose Logic Pro > Control Surfaces > Learn Assignment for "[parameter]", move the controller, then click Learn Message (or press Command-L) to finish.
- Expert view (ctls71c3162b): "No zone" assignments are always active; selecting a mode activates it.

## Procedure that worked (run 2)

1. In the Controller Assignments window, show zone **"(No zone)"** (it was shown after deleting the run-1 row).
2. With the real mouse, drag the Master Gain knob a few pixels so the value changes (a press without movement, or background drags, did not register: the Learn menu item stayed "no parameter").
3. Press Command-L. A new row labelled "Master Gain" appears and Learn Message is on (AX value 1).
4. Send `B0 17 40`, `46`, `4C`, `52` 0.4 s apart on `logicctl-gen` (00:07:59.335–00:08:00.564Z).
5. Press Command-L again; Learn Message reads 0.

The new row (read through Accessibility): label "Master  Gain", class Channel Strip, channel strip "selected track", input `logicctl-gen`, message `B0 17 Lo7`, Lo7 0–127, format unsigned, value range −24.0 to +24.0 dB, multiply 1.00, mode Scale.

## Observation

| # | Time sent (UTC) | CC 23 value | Prediction | AX value / display |
|---|---|---|---|---|
| 1 | 00:08:19.128 | 96 | +12.3 dB | 363 / +12.3 dB |
| 2 | 00:08:20.751 | 32 | −11.9 dB | 121 / −11.9 dB |
| 3 | 00:08:22.356 | 64 | +0.2 dB | 242 / +0.2 dB |

- O1: in run 2 all three values matched the prediction.
- O2: run 1 (Learn at 00:04:49Z) put the new row into zone **VPots**, mode **Surround Position**, because the Controller Assignments window had last shown that mode (it had followed the VPot 8 message in EXP-CA-005). That mode is not the active one (Pan/Surround is bold), and the row did not react to 96, 32 and 64 (Master Gain stayed +7.0 dB). The row was deleted with Edit > Delete after selecting it (input `logicctl-gen` checked first).
- O3: during Learn the parameter followed the messages: after the burst Master Gain was 310 / +7.0 dB (= value 82).
- O4: copied preferences after run 2 (`s5.bin`, 7,985 records, one more than before): the new row has Assign +0x56 = 0xffff (as the "no zone" note-26 rows) and list 6 = IDs 0x454d4147, 0, 0xec with ordinal 0, the same descriptor as the old row ([ASSIGN-IDENTITY-001](../notes/assignment-identity-callbacks-001.en.md) I11, I15). The run-1 row had +0x56 = 0. The VPots active mode stayed Pan/Surround.
- O5: restore: Option-click on the Master Gain knob set it to 240 / 0.0 dB (00:08:42Z). The learned row on `logicctl-gen` is kept for later tests. The probe was stopped.
- Raw data (not in Git): `Research/raw/ca006/` (AX reads by `Tools/research-scripts/ax-value-read.swift`; `probe.log`, `prediction.txt`, `run2-read-*.json`, `restore.json`), `Research/raw/cs-diff/s4.bin`, `s5.bin`.

## Verification stages

1. MIDI sent: TX lines with times in `probe.log`.
2. Assignment in Logic: the row's fields read through Accessibility, and the saved row in the copied preferences.
3. Value: AX value of the Master Gain slider after each send (not only the screen).

## Hypothesis

Hypothesis H1: an Easy-view Learn puts the new assignment in the zone and mode currently shown in the Expert view lists, so the Learn procedure must show "(No zone)" first. Confidence: medium (two runs, one per zone).
Hypothesis H2: Assign +0x56 is the zone reference and 0xffff means "no zone". Confidence: medium-low (note-26 rows, the run-1 and run-2 rows).
Hypothesis H3: the last-touched-parameter record needs a real value change by the user (matches `extParValueChangedByUser` in ASSIGN-IDENTITY-001 I9). Confidence: medium.
Next experiment: PLAN-CA-005 T1–T3 on `logicctl-gen`; a third Learn with a different mode shown, to test H1.
