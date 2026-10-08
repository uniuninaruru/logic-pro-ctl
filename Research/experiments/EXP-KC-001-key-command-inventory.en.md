[日本語](EXP-KC-001-key-command-inventory.md) | [English](EXP-KC-001-key-command-inventory.en.md)

# EXP-KC-001: take Logic 12.4's key command list with the official "Copy Key Commands to Clipboard"

| Item | Value |
|---|---|
| Date | 2026-10-08 02:03–02:10 UTC |
| Logic version | 12.4 (build 6707), recorded from the running process's Info.plist |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (unchanged) |
| Initial state | Stopped. Synth selected. The clipboard held a short string, which was read and saved first and written back afterwards as plain text (rich-text formats were not restored) |
| One operation | In the Key Commands window (⌥K), choose "Copy Key Commands to Clipboard" once from the Action pop-up |
| Expected change | Per Apple's guide, a text list of every key command lands on the clipboard |
| Repetitions | 1 |

## What Apple's official guide says (ja-jp; the guide's version selector stops at 12.3)

- "Copy and print key commands" (lgcpeabb4c40): choosing "Copy Key Commands to Clipboard" from the Action pop-up of the Key Commands window copies the list of all key commands.
- "Assign key commands" (lgcp41ff6979) also describes registering MIDI assignments. Not read this time (next experiment).

## Observation

- O1: the Action menu has 14 items (Presets, Import, Import to selection, Merge, Save, Save as, Save customized as, Copy to Clipboard, Show all / Hide all, Jump to selection, Reset all / selected / unused).
- O2: the copied text is not UTF-8 but Japanese Shift_JIS-family bytes (80,541 bytes, 2,231 lines). Read as CP932, the command-name column has 0 garbled characters.
- O3: format: a header row (Command, Key, Touch Bar), then "- group name" rows and tab-separated rows of 4 fields (empty, command name, key, Touch Bar).
- O4: 27 groups, **2,176** commands. 811 have key text and 50 have a Touch Bar entry. 6 names occur twice. Counts per group: Global 671, Main-window tracks and editors 290, Main-window tracks 247, Score editor 139, Various windows 110, Step Sequencer 91, Mixer 85, Views with a time ruler 80, Various editors 67, Audio File editor 55, MIDI Environment 50, Step Input Keyboard 49, Sampler 36, Smart Tempo editor 32, Tools menu 29, Views with automation 22, Project Audio 20, Live Loops grid 18, Drum Machine Designer 16, Step Editor 16, Windows showing audio files 13, Piano Roll 12, Event editor 9, Global control surface commands 7, Smart Control 6, Library 4, Control Surface install window 2.
- O5 (key column): ⌘ appears as `86 D1` 230 times. Arrows decode correctly in CP932. ⌥, ⌃ and ⇧ were already replaced by `?` when pasted and are **not recoverable**, so the key column is inexact for modifiers.
- O6 (not in the copy): the window's table has a "Control Surface" column (for example "Play or Stop" shows "Note 26 (+1)", and Play and Stop show Mackie assignments); the copy has no such column.
- O7 (command names for the priority features, as shown by Apple's UI): "Create Pattern Region/Cell", "Create Session Player Region/Cell", "New Session Player Software Instrument Track…", "Create Track from Session Player Region", "Replace with Session Player Region/Cell", "Convert to Pattern Region/Cell", "Separate Pattern Region/Cell by Kit Piece" (all in "Main window tracks and editors"), "Show/Hide Loop Browser" and "Show/Hide Step Input Keyboard" (Global), "Add Region/Cell to Loop Library…" and "Convert Loops to Regions" (Main-window tracks). (Names translated here from the Japanese labels; the Japanese strings are the observation.)
- Raw data (not in Git): `Research/raw/keycommands/current-12.4-copy.txt` (original bytes), `current-12.4-copy.utf8.txt` (converted with CP932).

## Hypothesis

H1: this list is a primary source for the **names and groups** of current 12.4 key commands. It carries no command-ID mapping. Confidence: high (names, counts).
H2: context-menu labels (such as "Create Pattern Region") most likely correspond to key command names ("Create Pattern Region/Cell") differing only in wording or "/Cell". Confidence: medium (string closeness only; not run).
H3: key commands can be targets of MIDI assignments (the Controller Assignments class "Key Command"); the existing row "Note 26 → Play or Stop" is an example. Confidence: medium (Apple's text and an existing row; a new assignment has not been executed).

## Next experiments

1. Read Apple's "Assign key commands" (lgcp41ff6979), then register one harmless key command (for example "Show/Hide Loop Browser") with a MIDI assignment, send it, and confirm on screen. Delete the row afterwards.
2. Find a route that captures modifiers exactly (a `.logikcs` saved through "Save as", or the in-app presets).
3. Check the context-menu-to-key-command correspondence one item at a time.
