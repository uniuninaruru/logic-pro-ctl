[日本語](EXP-CA-004-channel-eq-gain-calibration.md) | [English](EXP-CA-004-channel-eq-gain-calibration.en.md)

# EXP-CA-004: move Channel EQ's Master Gain with CC 23 and read the displayed value back (P0: calibration on the existing assignment)

| Item | Value |
|---|---|
| Date | 2026-10-08 08:39–08:41 UTC |
| Logic version | 12.4 (build 6707), recorded from the running process's Info.plist |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (confirmed by the window title "LogicCLI-Test - トラック"; stopped; not saved) |
| Target confirmed | Track Synth (position 2, selected). The first audio-effect slot (Channel EQ) in the inspector channel strip. The plug-in window title is "Synth" and its bottom label is "Channel EQ". Parameter: "Gain" (a vertical slider and the numeric box under it). Display name of the Controller Assignments row: "Channel EQ: Master Gain" (CC 23, class Channel Strip, selected track, range −24.0 to +24.0 dB) |
| Initial state | Displayed value 0.0 dB. Pickup mode on. Synth's solo is **on** (cause unknown; preserved unchanged per Codex's instruction). The virtual MIDI port `logicctl-cc` was created after Logic started. The plug-in window stays open (for Codex and RDCO to read) |
| One operation | Send values **one at a time** to the existing assignment (CC 23, `B0 17 Lo7`) and read the displayed value on screen 1.5 s later (my tools cannot read the accessibility value; I read it by zooming the screen) |
| Expected change | As in [EXP-CA-002](EXP-CA-002-variable-cc-and-pickup.en.md), −24 + value × 48 / 127 dB. With 7 bits, exactly −6.0 dB cannot be produced |
| Repetitions | 8 messages |

## What Apple's official guide says

- "Value" parameters (ctls71c308ee): Scale maps the received range onto the target's range.
- General settings (lgcp1fe673ef): Pickup mode.

## Observation (value sent → displayed value)

| # | CC 23 value sent | Displayed | Formula prediction (−24 + value × 48 / 127) |
|---|---|---|---|
| 1 | 64 | 0.0 dB (**no change**) | +0.2 |
| 2 | 127 | +24.0 dB | +24.0 |
| 3 | 0 | −24.0 dB | −24.0 |
| 4 | 96 | +12.3 dB | +12.3 |
| 5 | 32 | −11.9 dB | −11.9 |
| 6 | 64 | +0.2 dB | +0.2 |
| 7 | 48 | −5.9 dB | −5.9 |
| 8 | 47 | −6.2 dB | −6.2 |

- O1: the 7 points of #2–#8 matched the prediction (the display has 0.1 dB steps). For #7 and #8 the prediction was written from the formula before sending.
- O2: **exactly −6.0 dB cannot be produced by one 7-bit CC.** The step is about 0.378 dB; the nearest are 48 (−5.9 dB) and 47 (−6.2 dB).
- O3: #1, 64, was ignored (the display stayed 0.0 dB). The last value previously sent to this assignment was also 64 and the target's value is 0.0 dB (63.5 in CC terms). The next 127 was applied. **The reason for the ignore is undetermined:** (a) Pickup (64 does not equal the target's 63.5, and 64 → 127 does not cross 63.5 because both are above it, so "crossing" does not explain it), or (b) Logic discarded a repeat of the same value as no change. Either explains it; the two were not separated. The earlier wording "64 → 127 crosses 63.5" was arithmetically wrong and is withdrawn.
- O4 (verification stages): (1) MIDI sent: 8 messages in `probe8.log` (confirmed). (2) Assignment in Logic: row CC 23 confirmed on screen (not re-read this time). (3) Value after the change: confirmed **by the screen display only** (not as an accessibility value).
- Raw data (not in Git): `Research/raw/midi-learn/probe8.log`. Screen readings are in the conversation record with operation times.

## Hypothesis

H1: CC 23 on Channel EQ's Master Gain follows −24 + value × 48 / 127 dB to within the display's 0.1 dB. Confidence: high (7 points matched predictions).
H2: a closed procedure "choose the nearest CC value for the target dB, then read back and confirm" gives about ±0.2 dB. Confidence: medium (one parameter of one plug-in).
H3: exact verification needs a value readable through accessibility rather than a zoomed screen (waiting for RDCO's survey). Confidence: n/a.

## State restored

Gain was **returned to 0.0 dB** by Option-clicking the slider (about 09:02 UTC; confirmed on screen). The plug-in window's right-hand Gain slider was off screen, so I dragged the title bar to the left (content unchanged; only the window position changed). CC cannot produce 0.0 dB (63 gives −0.2, 64 gives +0.2), so a screen operation was needed.

## Next experiments

1. Match RDCO's accessibility reads against these send times (the table above).
2. Create a new temporary assignment (P1) by the official procedure: check conflicts, delete and re-create it, and confirm the effect.
