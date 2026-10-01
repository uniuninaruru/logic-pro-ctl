# SA-003: Logic.framework first pass — Assign fields, command entry points, URL handling

[日本語](SA-003-logic-framework-first-pass.md) | [English](SA-003-logic-framework-first-pass.en.md)

| Field | Value |
|---|---|
| Date | 2026-10-01 |
| Logic | 12.3.1 (6682) |
| Binaries (arm64) | `Frameworks/Logic.framework/Versions/A/Logic` (40.7 MB, 3 exported symbols; ObjC metadata recovered by Ghidra), main executable stub, `LogicAppFramework` |
| Tool | Ghidra 12.1.4 headless, ~20 min analysis, 10 GB heap. `Tools/ghidra/analyze.sh` with a name filter; targeted follow-ups with `Tools/ghidra/query.sh` + `XrefDecompile.java` |
| Output (local only) | `Research/raw/ghidra/Logic.arm64.{functions.tsv,decompiled.c}`, `q-*.c` |

## 0. Where the code is
- Main executable `Logic Pro Creator Studio`: 29 functions — `NSApplicationMain` + app-factory setup. No logic.
- `LogicAppFramework`: 80 functions — Swift `AppFactory` document lifecycle only.
- → The application lives in `Logic.framework` and the `MA*.framework`s.

Classes in the filtered decompile (method counts): `LgLogicRemoteController` 275,
`WrappedAssign` 124, `ControllerAssignmentsController` 100, `LgTronMessageRouter` 51,
`CSLearnRecentAssignmentsImpl` 42, `LiveLoopsControlSurfaceManager` 21,
`CSControlSurfaceControllerImpl` 20, `KeyCommandsController` 11, `RemoteCommandSupport` 10.

## 1. Assign field map — confirmed from WrappedAssign getters
`WrappedAssign` (ObjC wrapper of the C++ Assign used by Controller Assignments)
reads these offsets of the serialized Assign (`pvVar1 = [self assign]`):

| Getter | Offset / type |
|---|---|
| `assignmentClass` | +0x3a u32 |
| `trackNo` | +0x3e u16 & 0xfff |
| `befehl` (German "command") | +0x3e s16 |
| `key`, `mode` | +0x3e (s8 / s16) |
| `trackParam`, `audioTrackParam`, `groupParam` | +0x40 s32 |
| `bankType` | +0x40 u8 |
| `valueMode` | +0x4b & 7 |
| `feedbackType` | +0x46 & 0x7f |

→ Upgrades SA-002: "kind" = **assignmentClass**; "sub" = **trackNo** (class 5) or
**befehl** (class 9, command); "param" = **trackParam**. Confidence: high (getter code).
Other WrappedAssign properties name the remaining semantics: `globalObj`,
`clockPart`, `markerIndex`, `alertButton`, `trackObj`, `viewFilter`, `groupObj`,
`csGroupObj`, `valueFormat`, `multiply`, `min/maxMIDIValue`, `resolution`,
`MIDIInput`/`MIDIOutput`, `isPinnedToTrack`, `paramMin/Max`.

## 2. Command execution by number ("befehl")
- `RemoteCommandSupport -doLogicAction:(short)` → `FUN_008663d4(befehl, currentSong, 0, 2, 0)`.
- `-parseCommandQuery:` splits a query string and handles components
  `befehlid=<n>` (→ doLogicAction), `remoteid=<n>` (n in 1…14 → small table
  `DAT_01cbeb70` → doLogicAction), `openhelpvieweranchor=<a>`.
- Only caller: `CLgNotesFocusView -textView:clickedOnLink:atIndex:` — a click on a
  `file://…/logic?<query>` link inside Logic's Notes. Not reachable from outside
  without a GUI click.

Hypothesis: `FUN_008663d4` is the key-command dispatcher shared by key commands,
Notes links and Assign class 9 (Logic Remote `/cs/transport/play` = befehl 3).
Confidence: medium. Next: decompile `FUN_008663d4`; capture `/keyCommand/*`.

## 3. URL schemes (Info.plist + `CLgAppManager -handleGetURLEvent:withReplyEvent:`)
- `applelogicpro://<path>?alternativeIndex=<n>&selectBackup=<bool>` → opens the
  project at `<path>` (must exist) via `openDocumentAtURL:withAlternativeIndex:`.
- `logicpro:` → handed to another class (`FUN_01b3f480(0x25bc080, url)`, not yet read).
- No URL path to commands or mixer control found.

## 4. Key-command name table (unresolved)
`__DATA_CONST` 0x23a8018…0x23abfd8: 511 entries × 32 bytes
(`{name ptr (chained fixup), length, 0x8020000000001ce6, 0x7c8}`), e.g.
"Cycle Mode" [132], "Clear/Recall Solo" [139], "Mute off for all" [140].
Logic Remote uses befehl 1040/1041 for solo/mute reset → index + 901 for this
block, but "Cycle Mode" + 901 ≠ 15 (Remote's cycle). No code references found
(address computed at runtime). ID ↔ name mapping: **unknown**.
Next: get it dynamically from `/keyCommand/commandsQuery` → `commandsResponse`.
