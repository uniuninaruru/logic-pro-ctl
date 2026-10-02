[日本語](EXP-MCU-022-rename-reaches-surface.md) | [English](EXP-MCU-022-rename-reaches-surface.en.md)

# EXP-MCU-022: Does a track rename reach the MCU display?

| Item | Value |
|---|---|
| Date | 2026-10-02 13:05–13:15 JST |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (10 tracks + St Out + Master = 12 strips) |
| Initial state | `logicd` restarted and connected to the MCU (generation 4). The display shows the first bank (tracks 1–8). Track 5 is named `Trk05` |
| One operation | In Logic's track header, rename track 5 from `Trk05` to `Zed5` and commit. Nothing else changes |
| Expected change | If the hypothesis holds, the track 5 cell of the MCU upper LCD row becomes `Zed5`, and the check `--expect-name Trk05` gives `target_mismatch` |
| Repetitions | 1 (change → check → restore) |

## Purpose

A check such as `track mute 5 on --expect-name Trk05` assumes that "Logic sends a name change to the surface"
([docs/target-contract.en.md](../../docs/target-contract.en.md)). This experiment tests that assumption.
If it were not sent, a check that reads the visible cell without moving the bank would keep seeing the old name and pass after the change.

## Procedure and observations

| Step | Action | Observation |
|---|---|---|
| 0 | `logicctl track get 5 --expect-name Trk05` | Succeeds. `observation.session.bank_offset` is 0 |
| 1 | In the GUI, overwrite the name field with `Zed5` (typing only) | The name field stays in edit mode. The LCD at this moment was not checked |
| 2 | Click empty space to commit | — |
| 3 | `logicctl status` (raw copy of the LCD) | `Piano  Audio  Bass   Synth  Zed5   Trk06  Trk07  Trk08  ` — **the 5th cell is `Zed5`** |
| 4 | `track get 5 --expect-name Trk05` | `target_mismatch`, `observed.name` is `Zed5`. No data returned |
| 5 | `track get 5 --expect-name Zed5` | Succeeds |
| 6 | Restore the name to `Trk05` and commit | All names in `track list` (complete) are as before |

- After step 1 a Return was sent, but the name field stayed in edit mode and did not commit (the input tool reported that it "set the selected text to a newline"). The commit was done by clicking empty space.
  So **whether the LCD updates while typing or on commit is not distinguished**.
- The LCD copy in step 3 was read without moving the bank. So the rename **reached the visible cell without any bank movement on the surface**.

## Hypothesis

Hypothesis: when the name of a strip on the display changes, Logic updates that strip's LCD cell.
Confidence: medium to high (one run; before and after copies compared).
Evidence: the LCD copy of step 3; the check results of steps 4 and 5.
Counterexamples: none.
Not yet verified (does not raise the confidence):
- Whether **reordering, adding or deleting** tracks also makes Logic update the surface. The unit-test simulation assumes it does.
- A rename of a strip that is not on the display should show up the next time that bank is displayed (moving the bank rewrites the LCD). Not tried in this experiment.
- The behaviour of the LCD while a name is being typed.
Next validation experiment: reordering (dragging a track header), adding a track and deleting a track, each as a separate experiment,
checking whether the name from `track get` changes without moving the bank (revert with Undo; do not save).

## Consequence for logicctl

- For a rename, `--expect-name` detected the change with a read that does not move the bank.
- Detection for reorder, add and delete is **not confirmed**. Until it is, [the target contract](../../docs/target-contract.en.md) does not say
  "detects reordering and so on"; it says "detects it when Logic updates the surface".
