# SA-004: Logic's command boundary (befehl dispatcher) and the sequencer message queue

[日本語](SA-004-command-and-engine-boundaries.md) | [English](SA-004-command-and-engine-boundaries.en.md)

| Field | Value |
|---|---|
| Date | 2026-10-01 |
| Logic | 12.3.1 (6682), `Logic.framework` arm64 |
| Tool | `Tools/ghidra/query.sh Logic.arm64 …` (outputs `Research/raw/ghidra/q-cmd.c`, `q-cmdtable.c`, `q-menu.c`, `q-fader.c`) |

## 1. One command dispatcher for every UI path: `FUN_008663d4(befehl, song, flag, source, x)`
Callers (68) include menus (`CLgAppManager -globalMenuItemCall:`, `CLgView
-localMenuItemCall:`), toolbar (`CLgDocManager -doBefehlForToolbarItem:…`),
transport views and `DfDocument` play/stop/record/undo, Accessibility actions
(`CLgViewAccessibility* -accessibilityPerformAction:`), Logic Remote
(`LgLogicRemoteMessageRouter -routeMessage:withArgument:`) and Notes links
(`RemoteCommandSupport`).

Literal command numbers passed by callers (code-derived meaning):

| befehl | Caller(s) | Logic Remote table (SA-002) |
|---|---|---|
| 3 | `DfDocument -_playCallbackWithWillFreeze:`, Remote router | `/cs/transport/play` 3 ✓ |
| 4 | `DfDocument -pause`, virtual count-in play/record | — |
| 5 | `DfDocument -stop` | `/cs/transport/stop` 5 ✓ |
| 7 | `DfDocument -recordCallback` | `/cs/transport/record` 7 ✓ |
| 10 / 11 | `DfDocument -rewind` / `-forward` | — |
| 12 / 13 | `-fastRewind` / `-fastForward`, transport buttons | — |
| 15 | `DfDocument -enableCycle:`, toolbar, AX | `/cs/transport/cycle` 15 ✓ |
| 20 | `-setRecordingReplaceModeEnabled:` | — |
| 29 | `DfDocument -sendPanic` | — |
| 51 | `CLgView -toggleCatchPlayhead` | — |
| 474 | `-setMetronomEnabled:` | `/cs/transport/click` 474 ✓ |
| 535 | `ChordPopoverActionsDelegate -triggerPlayStop` | — |
| 542 | `DfDocument -captureLastRecording` | — |
| 761 / 796 | `DfDocument -undo:` | `/undo` 761, `/redo` 796 ✓ |
| 1040 | `-toggleKillRecallSoloAll` | `/cs/mixer/soloreset` 1040 ✓ |

→ **H2 confirmed**: Assign class 9 `befehl` values are Logic's command IDs, the
same IDs used by menus, toolbar, transport and Accessibility.

Dispatcher internals:
- `befehl < 0x1357` indexes a command table `DAT_026883b0[befehl]` (pointer to a
  40-byte entry; `+0x18` handler, `+0x20` argument; one handler `FUN_00f2c010`
  redirects to an alias via `DAT_01cd1d98`).
- `source` (4th arg): 2 = Notes link, and also Logic Remote's `/keyCommand/actionNum` ([SA-REMOTE-KEYCOMMAND-001](SA-REMOTE-KEYCOMMAND-001.en.md)); 6/7 = menu/key paths that read modifier
  keys; 1 skips that block.
- Same command twice within 500 ms is flagged (`DAT_02701c54`).
- Executes via `FUN_00865cec`; on failure `NSBeep` + notification
  "Command not available because …".

Command table construction (`FUN_00863ec4` → `FUN_008630b4` → `FUN_00864230`):
groups of 40-byte entries `{int16 befehl @0, handler @0x18, arg @0x20}` are
registered as `table[entry.befehl] = &entry` when the feature is available.
Groups match the Key Commands window categories, e.g. `GlobalCommands` (672),
`MainWindowTracksandVariousEditors` (290), `MainWindowTracks` (247),
`Mixer` (85), `ViewsShowingTimeRuler` (80), `VariousEditors` (67),
`ViewsShowingAutomation` (22), `LiveLoopsGrid` (18), `WindowsShowingAudioFiles` (13),
plus Piano Roll, Score, Step Sequencer, Smart Controls, Control Surfaces, …
The arrays live in zero-fill memory and are built by C++ static initializers, and
entries carry no name, so **ID ↔ name cannot be read from the file**; it needs the
running app (e.g. Logic Remote `/keyCommand/commandsQuery`).

## 2. Logic Remote routing (`LgLogicRemoteMessageRouter -messageReceivedAtAddress:withArgument:fromPeer:`)
By address prefix: `/midi…` → MIDI; `BgFaderEventKey` → `-handleFader:`;
`BgStepSequencerEditorActiveKey`; `/cs/` → control-surface Assign processing
(under a read lock); `/loopBrowser/`; `/sendsOnFader/sendsMenu|sendsTarget`;
`/arrangeOverview/request`; `/alert/`; anything else → main queue →
`-routeMessage:withArgument:` (calls the dispatcher with 3/4 etc.).

`-handleFader:` takes ≥12 bytes `{u32 object, …, byte status @5, u16 data @6,
u32 value @8}`, builds a MIDI-style event (status `E0` = pitch bend, else
controller) and posts it with `FUN_00791330(0x0e, &event, object, …)`.

## 3. The sequencer message queue: `FUN_00791330(type, event, object, …)`
Posts into a lock-protected ring of 1024 × 0x78-byte messages read by the
sequencer engine (`DAT_027034a8/ac` indices; on a full queue it waits and then
logs "Sequencer engine timed out after %d milliseconds" and runs `TimerMessage()`).
Type `0x0e` carries an event addressed to an object (`object` = channel-strip
/ environment object id).

Hypothesis H4: class-5 `trackParam` numbers (volume 7, pan 10, mute 9, solo 3,
sends 28–35) are Logic's Environment channel-strip control numbers, and mixer
changes from surfaces become controller-style events posted to channel-strip
objects through this queue. Confidence: medium (Remote fader path shown; the
`/cs/` Assign path into the queue not yet traced). Counterexample to check: MCU
mute/solo use 128/129.

## Boundary picture (brief §16), as far as observed
```
menus / toolbar / key commands / AX actions / Notes links / Remote "/cs/transport/*"
        └──────────────► FUN_008663d4(befehl) ──► command table ──► handler
control surfaces (MCU, Remote /cs/, TouchOSC, Lua, Controller Assignments)
        └──► Assign {assignmentClass, trackNo|befehl, trackParam}
                 ├─ class 9  → FUN_008663d4(befehl)            (H2, confirmed IDs)
                 └─ class 5  → channel-strip parameter          (H4)
Logic Remote fader data ──► event → FUN_00791330(0x0e, event, object) ──► sequencer engine
```
