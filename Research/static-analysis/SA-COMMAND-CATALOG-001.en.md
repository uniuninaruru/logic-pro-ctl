[日本語](SA-COMMAND-CATALOG-001.md) | [English](SA-COMMAND-CATALOG-001.en.md)

# SA-COMMAND-CATALOG-001: The catalog of commands Logic registers, and Logic Remote's command list

| Item | Value |
|---|---|
| Date | 2026-10-05 |
| Logic | 12.3.1 (6682), macOS 27.0 |
| Target (arm64) | `Logic.framework` (arm64 only, SHA-256 `2f141e1a…`) |
| Method | **Static analysis only.** Targeted Ghidra 12.1.4 decompilation and reading values from the binary. **No command was executed.** Nothing was sent to Logic |
| Output | [`Research/protocol/operation-catalog.tsv`](../protocol/operation-catalog.tsv) (2353 rows) |
| Reproduction | [`Tools/research-scripts/command_catalog.py`](../../Tools/research-scripts/command_catalog.py) (tests: `test_command_catalog.py`) |
| Related | [SA-004](SA-004-command-and-engine-boundaries.en.md) (the dispatcher) · [SA-002](SA-002-control-surface-assign-model.en.md) · [SA-REMOTE-FRAME-001](SA-REMOTE-FRAME-001.en.md) (frames) |
| Plan | The **static part** of PLAN-07. Evaluating each command's state and side effects is outside this document |

**Confidence convention:** a fact that matches the decompiled code or a value read from the binary is "confirmed"; an inference from it is a "hypothesis".
Nothing was confirmed on the real Logic.

## 1. Key points

1. **The command table holds 2353 entries.** Command numbers (`befehl`) range from 1 to 4078 in a table of size 4951. There are 2351 distinct numbers;
   only 2 numbers are registered in two groups (§4). **That does not mean 4951 operations are available.**
2. **Every entry has an English display name.** SA-004's "entries have no name" was wrong. The name is at +8 (§2).
   It is spelled like the menu item shown on screen, for example `Open Setup` or `Learn new Controller Assignment`.
3. **All known numbers are registered.** The 18 numbers named in SA-004 and the 14 numbers Logic Remote's default assignments send were all found, with matching names (§5).
4. **The command list Remote receives is built from this table.** The whole Tool Menu group and 100 numbers are left out (§6).
   Of those numbers 96 are registered, and 91 of their names end in "…" (mostly commands that open a dialog; hypothesis).
5. **There are 793 handlers, and 1799 entries share a handler with another entry.** The argument changes what it does (§7).
   So "a command number = one independent operation" does not hold.

## 2. Structure of the table (confirmed)

### 2.1 The command table

- `FUN_00863ec4` (once, at start-up) does `bzero(…, 0x9ab8)` on the global `DAT_026883b0`. 0x9ab8 / 8 = **4951** pointers.
- It then passes 28 group descriptors, in order, to `FUN_00864230`, which registers each entry as `table[entry.befehl] = &entry`
  (after asking `CFeatureAvailability::FeatureAvailable` whether the feature can be used).
- The number 28 is supported by the loop of `FUN_00863ec4` (0x540 / 0x30) and the loop of `LgLogicRemoteController keyCommands:` (0x01683e10) walking the same count.

### 2.2 Group descriptor (48 bytes)

`FUN_008630b4` builds the 28 of them on its stack.

| Offset | Content |
|---|---|
| +0x00 | pointer to the array of entries |
| +0x08 | number of entries |
| +0x10 | a feature identifier (`feature`). Meaning not analysed (`0x7f`, `0x7049`, `0x2021`, …) |
| +0x18 | the group name, a CFString |
| +0x20 | 0 |
| +0x28 | an unknown value (0, `0x17`, `0x5a`, …) |

### 2.3 Entry (40 bytes)

| Offset | Content |
|---|---|
| +0x00 | `int16 befehl` (the command number) |
| +0x08 | the name, a CFString (the English display name) |
| +0x10 | 0, or another CFString (the name of a localization table, for example `Localizable_StemSeparation`) |
| +0x18 | the handler (a function pointer) |
| +0x20 | the argument (an integer) |

The entry arrays of 13 groups are **static arrays** (inside the binary) and those of 15 groups are written by **constructor functions** (onto the stack, then copied). Both were read.

- Static: Various Windows, Main Window Tracks and Various Editors, Various Editors, Views Showing Time Ruler, Views Showing Automation, Event Editor,
  Step Sequencer, Smart Tempo Editor, Sampler, Step Input Keyboard, Tool Menu, Control Surface Install Window, MIDI Monitor Window
- Constructor: Global Commands (`FUN_00f59df0`) and 14 others (the table in §3)

### 2.4 How handlers are called (hypothesis)

When registering, `FUN_00864230` calls each handler as `handler(&DAT_026920d8, 0, argument, 0x8000)` (it looks like a state check).
The Tool Menu handler (`FUN_00f2c010`) branches on its fourth argument: `0x4000` (returns a constant), `0x20000` (returns the tool name), `0x8000` (returns whether it can be used),
and `0x80` / `0x100`. We presume that **the same call shape switches between checking state, getting a name and executing** (confidence: medium; from one handler and the call at registration).
SA-004's "`FUN_00f2c010` forwards to another command through `DAT_01cd1d98`" was a statement about **the Tool Menu handler**, not about a
global "alias table" (§8).

## 3. The groups

The same numbering as `group_index` in the catalog. "Remote" is the number that can appear in Remote's list (§6; exclusion by feature availability cannot be judged statically).

| # | Group | Count | feature | Source | Remote |
|---|---|---|---|---|---|
| 0 | Global Commands | 672 | 0x0 | constructor `FUN_00f59df0` | 598 |
| 1 | Global Control Surfaces Commands | 8 | 0x0 | constructor `FUN_00ab8d10` | 7 |
| 2 | Various Windows | 273 | 0x7f | static `0x022ebb18` | 272 |
| 3 | Windows Showing Audio Files | 13 | 0x7a | constructor `FUN_00275dc8` | 12 |
| 4 | Main Window Tracks and Various Editors | 290 | 0x7e | static `0x025dab78` | 286 |
| 5 | Various Editors | 67 | 0x7d | static `0x025ddc38` | 67 |
| 6 | Views Showing Time Ruler | 80 | 0x7c | static `0x022ee5c0` | 80 |
| 7 | Views Showing Automation | 22 | 0x7b | static `0x025dd8c8` | 22 |
| 8 | Main Window Tracks | 247 | 0x7049 | constructor `FUN_01003904` | 243 |
| 9 | Live Loops Grid | 18 | 0x27049 | constructor `FUN_01013edc` | 18 |
| 10 | Mixer | 85 | 0x2021 | constructor `FUN_01431850` | 85 |
| 11 | MIDI Environment | 50 | 0x1010 | constructor `FUN_0072eef4` | 50 |
| 12 | Piano Roll | 12 | 0x7042 | constructor `FUN_007c2504` | 12 |
| 13 | Score Editor | 139 | 0x7048 | constructor `FUN_014d6350` | 138 |
| 14 | Event Editor | 9 | 0x2081 | static `0x022af250` | 9 |
| 15 | Step Editor | 16 | 0x7043 | constructor `FUN_00f81ef8` | 14 |
| 16 | Step Sequencer | 91 | 0x606d | static `0x022be908` | 91 |
| 17 | Project Audio | 20 | 0x1015 | constructor `FUN_002744fc` | 16 |
| 18 | Audio File Editor | 55 | 0x1056 | constructor `FUN_0045e424` | 55 |
| 19 | Smart Tempo Editor | 32 | 0x2c | static `0x022ef6c8` | 32 |
| 20 | Library | 4 | 0x31 | constructor `FUN_00a03d98` | 4 |
| 21 | Sampler | 36 | 0x1b | static `0x022e2be0` | 34 |
| 22 | Drum Machine Designer | 16 | 0x30 | constructor `FUN_00ac1c88` | 16 |
| 23 | Step Input Keyboard | 49 | 0x24 | static `0x022b3938` | 49 |
| 24 | Smart Controls | 6 | 0x32 | constructor `FUN_0158f860` | 6 |
| 25 | Tool Menu | 29 | `none` | static `0x022ef240` | 0 (whole group left out) |
| 26 | Control Surface Install Window | 2 | 0x10d | static `0x022c0590` | 0 (suppressed) |
| 27 | MIDI Monitor Window | 12 | 0x110 | static `0x022c14c0` | 12 |
| | **Total** | **2353** | | | **2228** |

## 4. Duplicate numbers

There are 2351 distinct numbers. Only these 2 are registered in two groups.

| Number | Name | Group → handler (argument) |
|---|---|---|
| 1846 | Set Region Anchor to Playhead | Main Window Tracks → `FUN_0100e960` (0) / Audio File Editor → `FUN_0046db58` (2) |
| 1858 | Set Region Anchor to Region Start | Main Window Tracks → `FUN_0100f468` (0) / Audio File Editor → `FUN_0046db58` (3) |

It shows that **the handler for the same number depends on which window (group) has the focus**.
The table keeps one entry per number (`table[befehl] = &entry`), so the later registration stays. **Which one stays** looks like the latter (Audio File Editor), going by the registration order (group 8 → 18),
but the feature check is involved, so it cannot be fixed statically (hypothesis; confidence: low). As an example of a number that cannot identify a command by itself, it is handled from PLAN-10 on.

## 5. Cross-check with known numbers

The numbers named in SA-004 and the numbers of Remote's default assignments ([`cs-assign-remote.tsv`](../protocol/cs-assign-remote.tsv), assignment kind 9) were matched against the catalog.

| Number | Name in the catalog | Group | Handler (argument) | Remote assignment |
|---|---|---|---|---|
| 3 | Play | Global Commands | `FUN_00f60470` (0) | `/cs/transport/play` |
| 4 | Pause | Global Commands | `FUN_00f6057c` (0) | |
| 5 | Stop | Global Commands | `FUN_00f606c0` (0) | `/cs/transport/stop` |
| 7 | Record | Global Commands | `FUN_00f5fda0` (0) | `/cs/transport/record` |
| 10 / 11 | Rewind / Forward | Global Commands | `FUN_00f609f4` / `FUN_00f60b04` (0) | |
| 12 / 13 | Fast Rewind / Fast Forward | Global Commands | `FUN_00f60c10` (0 / 1) | |
| 15 | Cycle Mode | Global Commands | `FUN_00f6149c` (0) | `/cs/transport/cycle` |
| 20 | Replace | Global Commands | `FUN_00f616b4` (0) | |
| 29 | Send discrete Note Offs (Panic) | Global Commands | `FUN_00f4f944` (0) | |
| 51 | Catch Playhead Position | Various Windows | `FUN_00f2bbf0` (0) | |
| 474 | Metronome Click | Global Commands | `FUN_00f4eae0` (0) | `/cs/transport/click` |
| 535 | Play or Stop | Global Commands | `FUN_00f607c8` (0) | |
| 542 | Flashback Capture as Recording | Global Commands | `FUN_00f60348` (0) | |
| 761 / 796 | Undo / Redo | Various Windows | `FUN_004f0640` (0 / 6) | `/undo`, `/redo` |
| 1040 | Clear/Recall Solo | Global Commands | `FUN_00f61bac` (0) | `/cs/mixer/soloactive`, `soloreset` |

The other numbers in Remote's assignments are also all registered: 1041 Mute off for all, 1272/1273 Select Previous/Next Track,
1329/1330 Go to Next/Previous Marker, 1728 New Track with Duplicate Settings (of Remote's 14 numbers, **0** are unregistered).

## 6. Logic Remote's command list (confirmed)

Requests from Remote to Logic are routed under `/keyCommand/…` by `LgLogicRemoteMessageRouter routeMessage:withArgument:` (0x011e0118).

| Address (Remote → Logic) | Handling (the part that was read) |
|---|---|
| `/keyCommand/commandsQuery` | Reads `groupName` and `requestRange` (a range) from the argument (an NSKeyedArchive compressed as MAZP). The reply goes to `/keyCommand/commandsResponse`. **The details of building the reply were not read** |
| `/keyCommand/commandSearch` | Searches command names for the argument string as a **substring**, ignoring case and diacritics (`rangeOfString:options:0x81`). Sorts by `commandName` ascending and moves the items that **equal the string ignoring case** to the front. The result is an NSKeyedArchive compressed as MAZP (level 9), returned under `/keyCommand/commandResponse` |
| `/keyCommand/localizationRequest` | Takes the numbers in the argument's `valueArray` **20 at a time** and returns the localized names under `/keyCommand/localizationResponse` |
| `/keyCommand/groupsQuery`, `/keyCommand/keyCommandDictResponse`, `/keyCommand/actionNum` | Branches for them exist (the code that sends `groupsResponse` is in the same function). **The bodies were not read.** `actionNum` is presumed to be a way to execute by number (not read) |

The data behind these replies is **the same 28 group descriptors as in §3**. `LgLogicRemoteController keyCommands:` (0x01683e10) builds it.

- It builds an array of dictionaries. Each element is `{groupName: the group name, bindingsArray: [[number, name], …]}`.
- It uses the group name at `+0x18` and each entry's name (`FUN_00865ba8`).
- **It skips the group whose array is `0x022ef240` (the Tool Menu group).**
- It leaves out entries whose feature is not available (`FeatureAvailable`; not decidable statically).
- **It leaves out the numbers in `suppressedKeyCommands`.** `LgLogicRemoteController -init` (0x01682ad0) builds that set from a static `NSConstantArray` (`0x02438128`, 100 elements).

The 100 suppressed numbers:

```
21 22 30 32 35 36 39 61 62 69 204 403 409 414 476 477 487 488 489 490 497 499 520 540 558 564 639 644 645 652 653
681 685 686 690 751 752 755 756 757 758 759 768 797 1032 1033 1079 1152–1160 1162–1168 1170–1175 1177–1179 1182 1183
1186 1187 1194 1197 1207 1218 1223 1224 1226 1294 1303 1304 1310 1315 1342 1523 1715 1759 1765 1791 1800 1806 1902 3087 3200 3202
```

- Of the 100, **96 are registered**. The ones that are not: 558, 639, 1033, 1162.
- 91 of the 96 names end in "…" (`Go to Position…`, `Open Settings…`, `Save Project as…`, `Open Key Command Assignments…`, and so on).
  This is presumed to be an exclusion that **keeps commands that open a dialog out of Remote** (hypothesis; confidence: medium. An inference from how the names are spelled; the handlers were not read).
- The catalog's `remote_offered` column is `yes` (2228), `no: suppressed` (96) and `no: group skipped` (29).

**What Remote actually receives is at most 2228, after exclusion by feature availability.** Not checked on the real Logic.

## 7. Handlers and arguments

- There are 793 handlers. 1799 entries share a handler with another entry.
  Examples of one handler used with different arguments: Fast Rewind/Fast Forward (`FUN_00f60c10`, 0/1), Undo/Redo (`FUN_004f0640`, 0/6),
  the Record family (`FUN_00f5feac`, 1/2).
- The most widely shared are `FUN_0160f17c` (128 entries), `FUN_00601620` (117), `FUN_005a2064` (64) and `FUN_005a2c78` (64).
- So **what identifies an operation is "handler + argument"**; the command number is only an index into the table.

## 8. The Tool Menu group (confirmed)

29 entries (numbers 2318–2340, 2569–2571, 2683, 3034, 3035). The handler is `FUN_00f2c010` for all of them, and the argument is the **tool number**.
Each corresponds **one-to-one, by name and by number,** to a "Set … Tool" entry (`FUN_00f29a94`, taking the same tool number as its argument). All 29 were checked.

| Tool Menu | Matching Set … |
|---|---|
| 2318 Scissors Tool (1) | 851 Set Scissors Tool |
| 2327 Finger Tool (0x13) | 860 Set Finger Tool |
| 2322 Text Tool (8) | 855 Set Text Tool |
| 2571 Move Tool (0x12) | 2572 Set Move Tool |
| … | … (all of them are in the catalog's `twin_of` column) |

"Set Pointer Tool" (850, argument 0) has no counterpart on the Tool Menu. This relation is likely what SA-004 calls an "alias", but the role of
`DAT_01cd1d98` (a 16-bit table containing 850–854) is **not confirmed**. All that is written here is that "the same operation can be called two ways" (hypothesis; confidence: medium).

## 9. Use and limits

- The catalog is a **map for finding things**, not permission to execute. Before executing any number through `actionNum`, analyse that command's handler, argument and side effects separately.
  As PLAN-07's acceptance says, **not every ID is executed**.
- What the catalog does not answer:
  - Each command's **state evaluation** (enabled? pressed?). It is presumed to be a call to the handler with `0x8000`, but the handlers' bodies were not read (PLAN-10).
  - **Side effects**: save, delete, export and so on. Do not guess them from the spelling of a name.
  - **Required situation** (the focused window, whether a project is open). In the Tool Menu handler I saw branches that post the notices "there is no project open" and "there is no focused view", but this is not generalised.
  - The meaning of `feature`. It is presumed to be the identifier passed to `FeatureAvailable`, but it was not analysed.
  - **Other languages** (Japanese and so on) of the display names. `/keyCommand/localizationRequest` returns them at run time.
- The names are English spellings and include trailing spaces and symbols. Ghidra's labels (`cf_OpenSetup`) drop spaces, so **do not build a name from a label**
  (get the real string with `Tools/ghidra/cfstrings.sh`).

## 10. Reproduction

```sh
# 1. Group descriptors and constructors (under the shared lock; outputs go to Research/raw/ghidra)
Tools/ghidra/query.sh Logic.arm64 q-p7-table 0x00863ec4 0x008630b4 0x00864230
Tools/ghidra/cfstrings.sh Logic.arm64 logic-cfstrings
Tools/ghidra/stackstores.sh Logic.arm64 p7-stackstores 0x008630b4 0x00f59df0 0x00ab8d10 0x00275dc8 0x01003904 0x01013edc \
    0x01431850 0x0072eef4 0x007c2504 0x014d6350 0x00f81ef8 0x002744fc 0x0045e424 0x00a03d98 0x00ac1c88 0x0158f860
# 2. The catalog
python3 Tools/research-scripts/command_catalog.py --out Research/protocol/operation-catalog.tsv
# 3. Tests
(cd Tools/research-scripts && python3 -m unittest test_command_catalog)
```

The addresses are for this build only (12.3.1 / 6682, arm64). For another build, search again from `FUN_00863ec4`, `FUN_008630b4` and `LgLogicRemoteController keyCommands:`.
`command_catalog.py` **stops** if the number of elements of the suppressed set (100) differs.

## 11. Unknowns and next steps

| Item | Status | Next step |
|---|---|---|
| State evaluation (`0x8000`) and side effects of each handler | Not analysed | PLAN-10: read the handlers one by one, starting with IDs 3 / 7 (Play / Record) |
| Which entry stays in the table for the 2 duplicated numbers | Not fixed | Analyse the feature check at registration |
| The meaning of `feature` (group descriptor +0x10) | Not analysed | Look at the argument of `CFeatureAvailability::FeatureAvailable` |
| The value at group descriptor +0x28 | Not analysed | Follow how it is used (`FUN_00864088` and others) |
| The role of `DAT_01cd1d98` (a 16-bit table) | Not confirmed | Follow its references |
| 4 numbers in the suppressed set that are unregistered (558, 639, 1033, 1162) | Reason unknown | Check whether they are old numbers, or registered depending on a feature |
| How many commands Remote's list really contains | Not confirmed | Receive experiment (after PLAN-05 is approved) |
| Localized names | Not obtained | The reply to `/keyCommand/localizationRequest` (receive experiment) |
| How `actionNum` treats a number (conditions, return value) | Not analysed | Out of scope here. If analysed, only as static analysis that executes nothing |
