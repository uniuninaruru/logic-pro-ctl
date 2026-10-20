# PLAN-CA-005: morning live tests for Pickup and plug-in replacement (Logic 12.4)

[Research guide](../README.md) · Static basis: [PICKUP-CONSUMER-001](../notes/pickup-consumer-001.en.md), Codex's [pickup-global-004](../notes/pickup-global-004.en.md) and assignment notes · Overall plan: [midi-assignment-automation-001](midi-assignment-automation-001.en.md)

日本語要約：夜の静的解析から出た予測を、朝に実機で確かめる計画。①コントローラアサインメントの行を選んだ直後の CC は 1 回無視される、②同じ値の再送は捨てられる（ピックアップがオフでも）、③同じスロットのプラグインを別の EQ に差し替えたとき、CC 23 の行が新しいプラグインを指すか。1 回の実験で変える条件は 1 つ。音を出さない。終わったら元に戻す。

Owner: Claude (GUI and live). Codex leads and may reorder. Nothing here has been run yet.

## Gate (all must hold before any step)

1. The human is available to approve the screen-takeover card, or the step uses background tools only.
2. Logic is running with the window title "LogicCLI-Test"; no other song is open; the transport is stopped. No step starts playback.
3. The board has been read in full and no other participant holds the GUI or MIDI slot.
4. Baseline recorded: selected track, Synth solo state (currently unexplained, keep it), Pickup setting (on), Channel EQ Master Gain value, and the Controller Assignments rows CC 20–23.
5. A stable copy of `~/Library/Preferences/com.apple.logic.pro.cs` is taken only when its header length equals the file size − 8; invalid copies are kept but not used as evidence. The file is never written.

## Tests (one condition each)

| ID | Condition changed | Prediction (from static analysis) | Readout | Restore |
|---|---|---|---|---|
| T1 | Repeat the same CC 21 value twice on the selected track | The second message is skipped (no change), with Pickup on and again with Pickup off | MCU pan readback after each message | Pan back to the baseline with the MCU; Pickup back on |
| T2 | Select a row in the Controller Assignments window (syncSelection), then send one CC 21 value near the current pan | The first message after the selection is ignored once ("not yet valid"); the next one applies | MCU pan readback | Pan to baseline; close the window |
| T3 | Replace Channel EQ in the Synth's first audio-effect slot with another Apple EQ, by the menu path in Apple's guide | Unknown: the resolver can match by UUID (pinned key) or by position. Record which: CC 23 moves the new plug-in, moves nothing, or the row label changes | Controller Assignments row label; the new plug-in's value on screen (and Codex's read-only AX reader if available); `B0 17` sends one at a time | Undo the replacement (Edit menu), confirm Channel EQ is back with Gain 0.0 dB |
| T4 | Register one temporary key-command assignment, then copy the preferences file when its header is valid | A stable post-registration copy shows one added RDAF record (replacing the invalid `s1_1` evidence) | Codex's strict parser | Delete the assignment through "Delete Assignment" |

## Reporting

Each test gets its own experiment record (`EXP-CA-005` onward), with the sent bytes and times, the assignment state, and the observed value kept as three separate facts. Toggle-type commands are never re-sent automatically.
