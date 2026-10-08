[日本語](EXP-KC-002-midi-to-key-command-loop-browser.md) | [English](EXP-KC-002-midi-to-key-command-loop-browser.en.md)

# EXP-KC-002: assign a generic MIDI CC to the key command "Show/Hide Loop Browser" and run it

| Item | Value |
|---|---|
| Date | 2026-10-08 02:10–02:13 UTC |
| Logic version | 12.4 (build 6707), recorded from the running process's Info.plist |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (stopped, not saved) |
| Initial state | Synth selected. Library shown, Loop Browser hidden. Virtual MIDI port `logicctl-cc` (created after Logic started). Earlier records: [EXP-KC-001](EXP-KC-001-key-command-inventory.en.md), [EXP-CA-003](EXP-CA-003-value-mode-pickup-ab.en.md) |
| One operation | Following Apple's steps: in the Key Commands window select the command, press "Register New Assignment", and send CC 24 `B0 18 7F` and `B0 18 00` (0.5 s apart) once. Then send single values and check the screen |
| Expected change | After registering, sending CC 24 opens and closes the Loop Browser |
| Repetitions | 1 registration. The execution check was 2 pairs and 5 single messages (see Observation) |

## What Apple's official guide says

- "Assign key commands" (lgcp41ff6979, ja-jp): press "Register New Assignment", select the command in the Command column, and send a MIDI message from the controller. The registered assignment appears in the Control Surface field; once the whole message is received the button is disabled. To delete, select the command, select the assignment, and press "Delete Assignment".
- The guide's version selector stops at 12.3. This was confirmed on 12.4.

## Observation

- O1 (registration): after selecting the command "Show/Hide Loop Browser" (default key O), pressing "Register New Assignment" and sending `B0 18 7F` and `B0 18 00`, the table's Control Surface column showed **`CC 24`** and the button turned itself off. The key O stayed.
- O2 (execution): after registering, one pair of `7F` and `00` **opened** the Loop Browser at the right of the main window, and one more pair **closed** it (checked on screen).
- O3 (by value): `00` alone changed nothing. `7F` alone opened it, `7F` again closed it, `01` opened it, `40` closed it. **Any non-zero value toggled each time; 0 did nothing** (5 messages).
- O4 (deletion): selecting the command, selecting `CC 24` in the Control Surface list and pressing "Delete Assignment" emptied the column, and a later `7F` did nothing. The key O stayed.
- O5 (side effect): opening the Loop Browser hid the Library panel on the left, and closing the browser did not bring it back. I restored it with the leftmost toolbar button (this state must be restored before later checks).
- O6 (safety): on 12.4, ⌘K opens Musical Typing ([EXP-CA-003](EXP-CA-003-value-mode-pickup-ab.en.md) O7). Letter keys could play notes, so I drove the windows with the menu and buttons. Playback was never started.
- Raw data (not in Git): `Research/raw/midi-learn/probe6.log`. Screen checks are in the conversation record with operation times.

## Hypothesis

H1: registering a generic MIDI CC on a key command (the Controller Assignments class "Key Command") runs the command once for every non-zero value received. Confidence: high (1 registration; 6 toggles and 1 non-response to 0, all consistent).
H2: by the same procedure, the key commands Apple's screen shows ([EXP-KC-001](EXP-KC-001-key-command-inventory.en.md): 2,176) can be called from MIDI. Confidence: medium (confirmed for one command only; commands that depend on the selection or a region, or that open a dialog, are untested).
H3: the stored message form (`B0 18 Lo7` or a fixed pair) can be read in the Controller Assignments Expert view. Confidence: medium (not read this time).

## Next experiments

1. Read this row (class Key Command) in Expert view: message, mode and multiply (does a registration add a row, and does deleting remove it?).
2. Whether "Create Session Player Region/Cell" and "Create Pattern Region/Cell" can be called from MIDI with an empty lane selected (one at a time, reversible).
3. Include the Library-hiding side effect of the Loop Browser in the procedure.
