[日本語](EXP-CA-002-variable-cc-and-pickup.md) | [English](EXP-CA-002-variable-cc-and-pickup.en.md)

# EXP-CA-002: variable-value generic CC (pan, volume, plug-in) and how Pickup mode acts

| Item | Value |
|---|---|
| Date | 2026-10-08 01:50–02:02 UTC |
| Logic version | 12.4 (build 6707), recorded from the running process's Info.plist |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (stopped, not saved) |
| Initial state | Synth selected. Pan 0, volume 0 dB. Pickup mode on. Virtual MIDI port `logicctl-cc` (created after Logic started). Previous record: [EXP-CA-001](EXP-CA-001-generic-cc-fixed-message.en.md) |
| One operation | Nudge the target parameter with the real mouse so it becomes the "last touched parameter", start Learn with ⌘L, and send **four different values** (64, 70, 76, 82) 0.4 s apart. Then send single values and read each back |
| Expected change | Several values yield an `Lo7` row that follows the received value continuously. With Pickup on, right after the target changes, values are ignored until they reach the current value (Apple's guide) |
| Repetitions | 3 learned targets (pan CC 21, volume CC 22, Channel EQ Master Gain CC 23). 5–10 readbacks per target |

## What Apple's official guide says (ja-jp; the guide's version selector stops at 12.3)

- Easy-view registration (ctls71c31855): choose a parameter, learn with the registration command under "Logic Pro > Control Surfaces", and move the controller.
- "MIDI input" parameters (ctls71c30fbf): a message with `Lo7` is a 7-bit value. For a message without it, the received value is 0 in the Japanese page and 1 in the English page (**they disagree**; checked by Codex; see [EXP-CA-003](EXP-CA-003-value-mode-pickup-ab.en.md)).
- "Value" parameters (ctls71c308ee): the default mode for faders and knobs is Scale (the received range is scaled to the target's range).
- General settings (lgcp1fe673ef): in Pickup mode the value does not change until the controller reaches the current value. The guide uses control surfaces as its example.

## Observation

- O1 (learning): for all three targets, sending four different values produced a "value change" of `B0 15 Lo7`, `B0 16 Lo7` and `B0 17 Lo7`, Lo7 range 0–127, format unsigned, class Channel Strip (selected track). The row learned from a single value (EXP-CA-001) was a fixed message. The values sent during learning already moved the target.
- O2 (pan, CC 21): values 0, 127, 64, 90, 100 read back over MCU as −64, +63, 0, +26, +36. That is "received value − 64".
- O3 (volume, CC 22): values 127, 0, 64, 100, 32, 90 gave +6.0, −∞, −6.0, +1.8, −18.0, 0.0 dB. The curve is the fader's own taper, not linear.
- O4 (plug-in, CC 23): Channel EQ Master Gain (range −24…+24 dB) went to +24.0, −24.0, +0.2 dB for values 127, 0, 64 (linear). Confirmed on screen (MCU cannot read it).
- O5 (follows the selected track): on three tracks (Piano, Ballad, Synth), only the selected track's pan moved.
- O6 (Pickup on): right after switching the target, values that did not reach its current value were ignored: 4 times (80 on Ballad, 80 on Synth twice, 100 on Ballad). On Synth (current value equivalent to 100) the order was 80 → ignored, 100 (equal to the current value) → no change, 80 → applied (+16). On Piano, where the controller's last value (64) equalled the target's value (64), the first 100 applied immediately.
- O7 (comparison with Pickup off): on Ballad (current value 64) with the controller's last value at 80, sending 100 was ignored (on). After turning Pickup off in Settings, the same situation with 110 applied +46 (the values were 100 and 110, so this is not the same stimulus; the same-stimulus comparison is O3 of [EXP-CA-003](EXP-CA-003-value-mode-pickup-ab.en.md)). Pickup was turned back on afterwards.
- O8 (feedback): while pan, volume and the plug-in parameter changed, Logic sent 0 MIDI messages back to `logicctl-cc` (only device-query sysex arrived). 58 messages were sent.
- Raw data (not in Git): `Research/raw/midi-learn/probe6.log`. Screen checks are in the conversation record with operation times.

## Hypothesis

H1: a "selected track" assignment becomes unsynchronized when its target changes and ignores the controller until the controller's value equals the target's current value (Pickup). After that, any jump is applied.
Confidence: high (O6 and O7: the predicted order held, and the on/off A/B comparison agrees).
Counterexample: none. Whether merely crossing the current value (without equalling it) synchronizes is untested.
H2: the value mapping is linear for pan, the fader taper for volume, and linear over the parameter's range for the plug-in (Scale mode). Confidence: medium-high (3–10 points each).
H3: a generic assignment has no output, so there is no feedback. Confidence: medium (0 messages on 3 targets).
H4: the MCU LCD "Pan" / "-" display from the earlier record did not reproduce this time (0 occurrences through learning and readbacks). Confidence: low.

## Cleanup and next experiments

- State restored: Synth selected, pan and volume 0, Channel EQ Master Gain 0.0 dB, Pickup on. The test rows (CC 20–23) are still in Logic (for Codex's static analysis; to be deleted when it is done).
- Next: (1) whether crossing the current value alone synchronizes (e.g. target at 64, send 100 then 30); (2) Pickup when the track's volume or pan has automation; (3) behaviour when one CC is assigned to several targets; (4) the key-command inventory (Apple's "Copy Key Commands to Clipboard").
