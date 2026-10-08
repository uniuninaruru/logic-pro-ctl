[日本語](onboarding-rdco-001.md) | [English](onboarding-rdco-001.en.md)

# To RDCO: how this project works, and what we have learned so far

Addressed to RDCO (ChatGPT via Remote Desktop Commander). Written by Claude (owner of Logic GUI work and live experiments). Date: 2026-10-08. Logic is 12.4 (build 6707).
**The goal is a general programmable interface to Logic Pro** (CLI, MCP and later an SDK sharing one core). Reliable readback matters more than the number of features.

## 1. Roles and manners

| Participant | Main role |
|---|---|
| Codex | Static analysis, Swift product code (`logicctl`, `logicd`, MCP), curating and publishing documents, `cs_assignments.py` |
| Claude | Logic GUI operation and live experiments, experiment records (`Research/experiments/EXP-*`) |
| RDCO | Independent checks, investigation and review on demand (scope agreed on the board) |

**From 2026-10-08 Codex is the overall leader** (the user's instruction). Codex decides task assignment, priorities and ownership conflicts; Claude and RDCO follow Codex's instructions on the board. The user's direct instructions always come first. Read Codex's earlier welcome too (board message `CDEX118`).

- The board is `chatgpt-claude.md` (not in Git). `python3 Tools/research-scripts/board_new.py --reader rdco` prints only unread text (the name is ASCII letters, digits, `-` and `_`). **It cuts at 1,000 characters, so repeat while it says "more unread". Read the full text from the file; never settle for headings or the first lines.** Read before every operation (missing a "stop" or "I take the slot" notice makes experiments overlap and the data invalid; this really happened).
- Declare owned files and resources (Logic's screen, MIDI, Ghidra, builds) on the board first. Silence is not permission.
- Messages are short English plus IDs. Explanations to the user are in Japanese.
- Git: `git fetch` first. Commit only your own files with explicit paths (no `git add -A`, `git commit -a`, `stash`, `reset` or force push). Do not edit other people's files. `Research/raw/` is outside Git. Never commit raw logs, device names, user names, paths, UUIDs or locale; tables list counts only.

## 2. Rules (the core of AGENTS.md)

- Operate only on the dedicated test project `LogicCLI-Test.logicx`, and only while the window title shows "LogicCLI-Test". Do not switch, close or save songs.
- Never start playback or do anything that makes sound (the user is sometimes in class).
- No Logic binary changes, SIP, code signing or `sudo` without explaining and getting approval. **Never write directly to the settings file `com.apple.logic.pro.cs`** (Apple also says settings are changed inside Logic).
- Persistent setting changes (for example Pickup mode) only with the user's direct approval, and restore them.
- Product code (`Sources/`) must not depend on `Research/` or `Tools/`. The CLI prints JSON to stdout and diagnostics to stderr. Every write is read back; if it cannot be, report `verified: false`.
- Change one condition per experiment. Keep observations (with evidence files) apart from hypotheses (with confidence).
- **Read Apple's official guide before any GUI or feature operation** (`support.apple.com/ja-jp/guide/logicpro/...`; the guide stops at 12.3, so confirm 12.4 behavior on the real app and note which is which). The English and Japanese pages can disagree (example: the received value of a message without `Lo7` is 0 in the Japanese page and 1 in the English one).

## 3. Keep three states apart (most important)

"MIDI was sent", "Logic has the assignment" and "the value actually changed" are different facts. Results should carry a verification state per stage.
- **Never auto-retry toggle-type commands.** The Loop Browser opens or closes for every non-zero CC; a retry can undo the state.
- Write `verified: false` for anything that cannot be read back.

## 4. What we know (links to the records)

- Over the MCU (Mackie Control) path we can read and write the track list, volume, pan, mute, solo, selection, record arm and transport. See `logicctl`, `logicd` and `docs/`.
- Generic MIDI assignments:
  - [EXP-CA-001](../experiments/EXP-CA-001-generic-cc-fixed-message.en.md): a row learned from a single value is a "fixed message"; each identical message adds 1 to the current value ("Rotate" mode).
  - [EXP-CA-002](../experiments/EXP-CA-002-variable-cc-and-pickup.en.md) and [EXP-CA-003](../experiments/EXP-CA-003-value-mode-pickup-ab.en.md): **sending several different values while learning gives an `Lo7` row.** We moved pan, volume and Channel EQ's Master Gain this way. Rows follow the "selected track". With Pickup mode on, right after the target changes the controller is ignored until it equals or crosses the target's current value.
  - Feedback (Logic sending MIDI back) was not confirmed on a generic input port (one format, one trial).
- Key commands: [EXP-KC-001](../experiments/EXP-KC-001-key-command-inventory.en.md) (the 12.4 list: 27 groups, 2,176 commands), [EXP-KC-002](../experiments/EXP-KC-002-midi-to-key-command-loop-browser.en.md) (a MIDI CC registered on a key command runs it).
- The settings file: [EXP-CS-001](../experiments/EXP-CS-001-prefs-file-live-diff.en.md) (rewritten without quitting Logic; one assignment is one `RDAF` record; **check a copy's validity with the header length field**).
- Note entry (step input, speed): [EXP-MIDI-032](../experiments/EXP-MIDI-032-controller-note-input.en.md) and [EXP-MIDI-033](../experiments/EXP-MIDI-033-step-region-edit.en.md) (Codex).
- Review of the external reference `koltyj/logic-pro-mcp`: [logic-pro-mcp-reference-001](logic-pro-mcp-reference-001.en.md).

## 5. GUI mistakes we made (so they are not repeated)

- Clicks and typed text were sent while the frontmost app was not Logic, and went to another app (ChatGPT). **Check the frontmost app before acting** (`lsappinfo info -only name "$(lsappinfo front)"`). Start a full-screen batch in a call separate from the first look at the screen.
- Typing in the background lands somewhere else (a list). When windows overlap, a coordinate click hits the window on top. **Press buttons by element index** (`AXPress`).
- On 12.4, ⌘K opens Musical Typing (letter keys can play notes). Open windows from the menu.
- Pressing "Register message" with a row selected creates a **new row**; it does not re-register the selected one.
- Opening the Loop Browser hides the Library panel and it does not come back.
- Learning from one value gives a fixed message. Send several values 0.4 s apart.

## 6. Tools

- `python3 Tools/research-scripts/board_new.py --reader rdco`: unread board text.
- `.build/out/Products/Debug/logicctl`: the CLI (`logicctl --help`). `logicd` starts automatically when needed. The build directory is shared, so announce use on the board first.
- `Tools/research-scripts/mcu-probe.swift` (a virtual MIDI port; `MIDI_PORT=name` changes the name), `mcu_trace.py`, `midi-note-probe.swift`, `cs_assignments.py` (Codex, read-only), `logic-plugin-inspect.swift` (Codex, screen reading only).
- Ghidra is shared; go through the lock `Tools/ghidra/with-project-lock.py`.

## 7. What we would like from RDCO (first candidates; agree on the board first)

1. **A read-only cross-check:** compare Apple's guide (Japanese, English, 12.3) with the statements in `EXP-CA-*`, `EXP-KC-*` and `EXP-CS-001`, and report mismatches or under-supported claims as a file (create a new file under `Research/notes/`; do not edit existing ones).
2. **A readback survey** (observation only): can the value shown in a plug-in window be read through the screen's accessibility API? Agree on the split with Codex's `logic-plugin-inspect.swift` on the board first.
3. **Python tidiness:** list what GitHub's Pylint reports on `Tools/research-scripts/*.py` (fix things only after agreeing with the owner).

Write questions on the board. Claude and Codex answer at their normal checks.
