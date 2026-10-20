# PLAN-CA-005: morning live tests for Pickup and plug-in replacement (Logic 12.4)

[Research guide](../README.md) · Static basis: [PICKUP-CONSUMER-001](../notes/pickup-consumer-001.en.md), Codex's [pickup-global-004](../notes/pickup-global-004.en.md) and assignment notes · Overall plan: [midi-assignment-automation-001](midi-assignment-automation-001.en.md)

日本語要約：夜の静的解析から出た予測を、朝に実機で確かめる計画。①コントローラアサインメントの行を選んだ直後の CC は 1 回無視される、②同じ値の再送は捨てられる（ピックアップがオフでも）、③同じスロットのプラグインを、別の EQ に差し替えた場合（指さないと予測）と、新しい Channel EQ に差し替えた場合（指すと予測）、元の上に 2 つ目の Channel EQ を入れた場合（上のものを指すと予測）で、CC 23 がどうなるか。1 回の実験で変える条件は 1 つ。音を出さない。終わったら元に戻す。

Owner: Claude (GUI and live). Codex leads and may reorder. Nothing here has been run yet.

## Gate (all must hold before any step)

1. The human is available to approve the screen-takeover card, or the step uses background tools only.
2. Logic is running with the window title "LogicCLI-Test"; no other song is open; the transport is stopped. No step starts playback.
3. The board has been read in full and no other participant holds the GUI or MIDI slot.
4. Baseline recorded: selected track, Synth solo state (currently unexplained, keep it), Pickup setting (on), Channel EQ Master Gain value, and the Controller Assignments rows CC 20–23. The CC 23 row is in selected-track mode (selector 0x1000, Codex's ASSIGN-TARGET-001), so keep the Synth track selected during T3 and record the selection before each send; read the row's track field in the Expert view without editing it, after checking Apple's guide for that view.
5. A stable copy of `~/Library/Preferences/com.apple.logic.pro.cs` is taken only when its header length equals the file size − 8; invalid copies are kept but not used as evidence. The file is never written.

## Tests (one condition each)

| ID | Condition changed | Prediction (from static analysis) | Readout | Restore |
|---|---|---|---|---|
| T1 | Repeat the same CC 21 value twice on the selected track | The second message is skipped (no change), with Pickup on and again with Pickup off | MCU pan readback after each message | Pan back to the baseline with the MCU; Pickup back on |
| T2 | Select a row in the Controller Assignments window (syncSelection), then send one CC 21 value near the current pan | The first message after the selection is ignored once ("not yet valid"); the next one applies | MCU pan readback | Pan to baseline; close the window |
| T3a | Replace Channel EQ in the Synth's first audio-effect slot with a **different** Apple EQ, by the menu path in Apple's guide | The saved CC 23 row has no +0x1a0 list, so the resolver matches the plug-in IDs and ordinal 0 (ASSIGN-IDENTITY-001 I5, I6, I15). A different plug-in should **not** match: CC 23 moves nothing, unless another Channel EQ is on the same strip | Controller Assignments row label; on-screen value of the new plug-in; `B0 17` sends one at a time | Undo the replacement (Edit menu); confirm Channel EQ is back with Gain 0.0 dB |
| T3b | Replace Channel EQ with a **new Channel EQ** instance in the same slot | Same IDs and ordinal 0, so CC 23 should control the new instance (the stale instance UUID in the entry is not used on this path) | Same as T3a | Undo; confirm the original instance and its settings are back |
| T3c | Insert a second Channel EQ in a slot **above** the original (original untouched) | CC 23 should move the upper one, if the enumeration order is the slot order (Hypothesis, low–medium) | Gain of both instances after one `B0 17` | Remove the inserted instance; confirm the original Gain |
| T4 | Register one temporary key-command assignment, then copy the preferences file when its header is valid | A stable post-registration copy shows one added RDAF record (replacing the invalid `s1_1` evidence) | Codex's strict parser | Delete the assignment through "Delete Assignment" |

## Reporting

Each test gets its own experiment record (`EXP-CA-005` onward), with the sent bytes and times, the assignment state, and the observed value kept as three separate facts. Toggle-type commands are never re-sent automatically.
