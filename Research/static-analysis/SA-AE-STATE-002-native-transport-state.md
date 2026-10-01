# SA-AE-STATE-002: Transport state getters, Logic Remote feedback, and mode 4 writes

The binary contains a Logic Remote peer message that reaches command-state
subscription and evaluation: `/keyCommand/keyCommandDictResponse`. That is a
concrete external protocol candidate for native state readback. Its initial
response is sparse: zero command states are omitted. Neither a reliable full
transport snapshot nor an independently connected CLI peer has been validated.
The current product must therefore keep MCU readback for AppleEvent writes.

AppleEvent mode 4 remains unsuitable as a read-only transport-state API. Its
`(-1, 0)` helper arguments select existing song tempo and suppress one
notification path; they do **not** suppress the helper's tempo-record and song
flag writes. These claims are confirmed from ARM64 instructions, not inferred
only from the decompiler's C types.

## Provenance and scope

| Field | Value |
|---|---|
| Date | 2026-10-01, Asia/Tokyo |
| Target | Logic Pro Creator Studio 12.3.1 / 6682, ARM64 |
| Installed framework | `/Applications/Logic Pro Creator Studio.app/Contents/Frameworks/Logic.framework/Versions/A/Logic` |
| Imported source | `/Users/nagataharuto/GhidraProjects/logicctl/bin/Logic.arm64` |
| Both Logic source SHA-256 values, checked this investigation | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| Installed MACore SHA-256, checked for imported constants | `76ab2a5f50b3ef120786369b5bf8b53dfc87a3b4107438e0894ab5f9b8095c52` |
| Tools | Ghidra 12.1.4 headless; `query.sh` / `XrefDecompile.java`; `TransportStateReport.java`; `nm`; read-only Mach-O segment/chained-pointer decoding |
| Ghidra execution | Existing `Logic.arm64`, `-noanalysis -readOnly`; no saved analysis changes |
| Local evidence manifest | `Research/raw/ghidra/q-transport-state-002-manifest.json` |
| Curated predecessor | `appleevent-registration.md`, `appleevent-command-dispatch.md`, `SA-002-control-surface-assign-model.md`, `SA-004-command-and-engine-boundaries.md` |

All addresses below are unslid image addresses for this exact framework,
including data addresses. They are not runtime addresses or stable exported
APIs. No AppleEvents, MIDI messages, remote peer messages, record commands,
memory reads of the live process, or target modifications were performed.

Fresh query exports are the local files
`q-transport-state-002-{anchors,feedback,entrypoints,routing,key-state}.c` under
`Research/raw/ghidra/`. `q-transport-state-002-machinecode.txt` contains Ghidra's
instruction bytes, addresses, resolved strings, selector slots, and data refs.
The manifest hashes these local exports. The custom report verifies the
imported executable's SHA-256 before using its fixed anchors.

The decompiler still has inaccurate prototypes for some unnamed helper and
Objective-C stub calls. In particular, a C temporary can appear to retain an
argument where ARM64 actually uses the call's result in `x0`. The key claims
below were checked against instructions and resolved selector data.

## 1. Internal document getters

`DfDocument::isPlaying` at `0x014fc9d4` follows the named Objective-C selectors
`logicModel` then `logicDocument`. The resulting document pointer is passed
to `FUN_01838684`, which resolves/checks its song pointer. The getter tests
**the returned song's byte `+0xb9`**, rather than the document object itself:

```asm
014fca04  mov   x0,x20
014fca08  bl    0x01838684
014fca0c  cbz   x0,0x014fca24
014fca10  ldrb  w8,[x0,#0xb9]
014fca14  cmp   w8,#0
014fca18  cset  w0,ne
```

`DfDocument::isRecording` at `0x014fcb04` resolves the song similarly, calls
`FUN_01103948(song, 0, 2)`, returns true when that result is nonzero, and
otherwise tail-calls the named `isCellRecording` selector. In the helper's
`param_3 == 2` branch, song byte `+0xbd` is checked, with additional recording
configuration logic. **A complete recording state cannot be reduced to one
byte without retaining the Live Loops/cell recording path.**

The named getters below use command-state evaluation rather than a direct
byte load. Each resets the global state accumulator `DAT_026883a0`, calls
`FUN_00865cec`, and reads whether the accumulator's low byte is nonzero:

| Getter | Entry | Command ID | Fourth evaluator argument |
|---|---:|---:|---:|
| `DfDocument::isPause` | `0x014fca44` | 4 | `0x40000002` |
| `DfDocument::isForward` | `0x014fcd18` | 11 | `0x40000002` |
| `DfDocument::isRewind` | `0x014fcdd8` | 10 | `0x40000002` |

These are internal methods used by Logic's object graph. Finding them does
not establish an AppleEvent, socket, or cross-process method invocation that
returns their values. No external CLI entry to these getters was found in
this bounded investigation.

## 2. What `updateTransportButtonStates` actually sends

`LgLogicRemoteController::updateTransportButtonStates` at `0x0168f070` reads
`DAT_0276de68 -> +0xc0` to get the current song. Its two results are:

1. `CLgTransportView::transportStopButtonStateForSong:` (`0x00bdacd0`) passed
   to `setTransportStopButtonState:` (`0x0168fa54`).
2. `FUN_01a26938(song)` passed to `setTransportClickWhileRecording:`
   (`0x0168fad4`).

The machine code proves the helper's `x0` result is moved into selector
argument `x2` at `0x0168f0bc`; the raw C incorrectly displays the song value
at that call. The selector slots resolve as follows:

| Stub | Selector pointer slot | Confirmed selector |
|---|---:|---|
| `0x01ba7fa0` | `0x0256bba0` | `setTransportStopButtonState:` |
| `0x01ba7f20` | `0x0256bb80` | `setTransportClickWhileRecording:` |

This method does **not** directly produce a complete `(playing, recording,
position)` snapshot. Stop-button state is an integer computed from song
transport state, Live Loops activity, preferences, and position comparisons;
its observed static return range is 0, 1, or 2. Its value is not established
as a direct Boolean substitute for `isPlaying`.

Confirmed outbound message constructors:

| Message address | Producer | Argument constructor / source | Delivery |
|---|---:|---|---|
| `/transport/stopButtonState` | `0x0168fa54` | `NSNumber numberWithInteger:`; cached at controller `+0x70`, sent when changed | default wrapper `useTCP=1` |
| `/transport/clickWhileRecording` | `0x0168fad4` | `NSNumber numberWithBool:`; cached at controller `+0x68`, sent when changed | default wrapper `useTCP=1` |
| `/transport/playButtonFlags` | `0x0168f238` | `NSNumber numberWithChar:` from signed byte `DAT_02765b85` | default wrapper `useTCP=1` |
| `/logicClock/spl` | `0x0168f314` | `NSNumber numberWithLongLong:` from `FUN_001a388c(song, 0)` | explicit `useTCP=0` |
| `/logicClock/currentTempo` | `0x0168f314` | `NSNumber numberWithInt:` from `FUN_001a9314(song, position)` | explicit `useTCP=0` |
| `/keyCommandStateUpdate` | `0x01683ad8`, `0x0168e1d4`, `0x0168f0dc` | dictionary of numeric command IDs to numeric status values | default wrapper `useTCP=1` |

The exact stop/flags/click/state-update strings are resolved from Ghidra's
CFString data and underlying C strings. `/logicClock/spl`'s position units
and `/logicClock/currentTempo`'s scale have not been dynamically validated.
The `useTCP` name is the program's selector argument; do not infer a raw TCP
port or implement an ordinary OSC socket from this alone.

`LgLogicRemoteController::sendMessage:withArgument:` (`0x01683acc`) forwards
to `sendMessage:withArgument:toPeer:useTCP:` with peer nil and `useTCP=1`.
The latter (`0x016839d4`) first calls the controller's `connected` selector.
Only a nonzero result forwards the message to `MAPeerRouter sharedRouter`.
The resolved selector stub is `0x01b1c480`. Thus merely locating the message
constructor does not make it available to an unconnected CLI.

`sendWakeupMessageInSong:activeSongChanged:` (`0x016843b8`) also emits cached
stop-button, header, click, and play-flags values during wakeup. The connected
peer callback (`0x016837a0`, block `0x01699828`) reaches this wakeup path and
performs protocol-version handling. Existing MACore analysis in SA-002 shows
MultipeerConnectivity session transport and tagged JSON/plist/archive message
framing; that transport has not been implemented or exercised by this task.

## 3. A concrete peer message reaches command-state evaluation

`LgLogicRemoteMessageRouter::messageReceivedAtAddress:withArgument:fromPeer:`
at `0x011df620` dispatches ordinary application messages onto the main queue,
then reaches `routeMessage:withArgument:` at `0x011e0118`. That method's
`BgKeyCommandListKey` branch calls `keyCommandStateSetup:`.

The imported symbol's exact string was checked in the installed MACore:

| Item | Address / bytes / value |
|---|---|
| Logic imported symbol pointer | `0x02282358` |
| MACore `_BgKeyCommandListKey` slot | `0x00185130`, bytes `80 2e 19 00 00 00 10 00` |
| MACore CFString structure | `0x00192e80` |
| MACore C string | `0x001514fe`, length `0x22` |
| Exact address | `/keyCommand/keyCommandDictResponse` |
| MACore chained pointer format | 6 (`DYLD_CHAINED_PTR_64_OFFSET`), `__DATA_CONST` and `__DATA` |

The source name contains `Response`, but Logic **receives** this message
from the peer. It is not `/keyCommand/list` or `/keyCommandStateSetup`.
`q-transport-state-002-constants.json` records the symbol lookup and decoded
CFString chain, alongside the other `_BgKeyCommand*` strings.

The router's ARM64 compare-and-call sequence is:

```asm
011e0ff4  adrp  x8,0x2282000
011e0ff8  ldr   x8,[x8,#0x358]        ; imported BgKeyCommandListKey
011e0ffc  ldr   x2,[x8]
011e1004  bl    0x01b51300            ; isEqualToString:
011e1008  cbz   w0,0x011e1158
...
011e1030  mov   x2,x19               ; received argument dictionary
011e1034  bl    0x01b55f80            ; keyCommandStateSetup:
```

`keyCommandStateSetup:` at `0x01683ad8`:

- Replaces the global subscription set `DAT_02750110`.
- Iterates `argument.allKeys`, applies `intValue`, and subscribes numeric IDs.
  Dictionary values are not read by this method.
- Skips current-state evaluation for IDs 0 and 5.
- For IDs marked available in `DAT_02687010`, resets `DAT_026883a0` and calls
  `FUN_00865cec(commandID, currentSong, 0, 2)`.
- Sends `/keyCommandStateUpdate` with one numeric ID/status pair **only when
  the initial status is nonzero**.

The initial-zero omission is machine-code confirmed:

```asm
01683c38  sxth  w0,w23               ; command ID
01683c3c  mov   x2,#0
01683c40  mov   w3,#2
01683c44  bl    0x00865cec
01683c48  ldr   x25,[x22,#0x3a0]     ; DAT_026883a0
01683c4c  mov   w8,w25
01683c50  cbz   x8,0x01683b8c        ; skip sending this entry
```

The evaluator's fourth argument 2 is a state path, as supported by its named
fallback selector branch: at `0x00866178` it compares the flag with 2 and
calls `befehlStatus:` (`0x01b0f3c0`) at `0x00866188`; flag 0 instead reaches
`performBefehl:` (`0x01b6bb40`) at `0x00866198`. The shared evaluator also
reaches registered command handlers and mutates internal caches/globals.
The per-command handlers for IDs 3 and 7 have not yet been fully audited for
their state-output semantics or side effects.

`keyCommandStateChanged:` at `0x0168e1d4` checks the subscription set and
emits an update even when a subscribed ID's later status is zero.
`handleUM_PLAY:` at `0x0168f0dc` has a separate `/keyCommandStateUpdate`
construction with constant numeric **key 3 and value 0**; both constants
were checked in data at `0x0242fd30` and `0x0242fcb8`. Its internal message
conditions have not yet been matched to runtime play/stop observations.

**Static boundary now established:** an incoming peer message reaches a
state evaluator and an outgoing peer status dictionary. **Runtime boundary
still unestablished:** an independently connected CLI peer has not received
these messages, and a silent initial zero cannot distinguish stopped state,
disabled/unavailable command, an unrecognized payload, or transport failure.
It is therefore premature to replace MCU readback with this subscription.

## 4. Mode 4 has conditional tempo mutations even with `(-1, 0)`

The AppleEvent handler's exact helper call is:

```asm
005914c0  mov   x0,x19               ; current song
005914c4  mov   x1,#-1
005914c8  mov   w2,#0
005914cc  bl    0x010e3628
```

In `FUN_010e3628`, negative parameter 2 reads the existing integer at song
`+0xcc` (`0x010e376c`). The helper inspects the tempo-event list returned by
`FUN_01a14040`. More than one counted event reaches an early return of 1 at
`0x010e374c`; the zero/one-event branches continue into creation or updating.
On those branches the following writes are present:

| Address | Instruction/effect | Condition |
|---|---|---|
| `0x010e37f4` | `strh w8,[x19,#0xde]` after OR with 1 | normalization/change branch; includes undo setup named `ChangeTempo_und` |
| `0x010e3818` | `str w8,[x22,#0x10]` | existing event branch, clamping the integer into 50,000..9,900,000 |
| `0x010e3828` | `str x8,[x22,#8]` after setting bit 63 | event mark bit not already set |
| `0x010e3834` | writes 2 to `DAT_025e23d8` | existing event branch |
| `0x010e383c` | calls `FUN_010e230c(song)` | existing event branch |
| `0x010e38a0` | calls `FUN_010e1fd8(song, 0, 0x960000000000, 0, existingValue, 2, flags)` | no event counted; creation helper includes explicit tempo record construction |

`flags == 0` skips the later notification call `FUN_019c3b50(0x97)` and
song `+0x758 |= 8` at `0x010e3840..0x010e3858`. Those flags do not gate the
preceding writes or the creation-helper call. The handler does not use the
tempo helper's result as a stop condition before producing its reply fields.

After that call it fetches an event using `FUN_019ae630(song, 3, 0, 0)`,
loads integer `event +0x18`, and passes it to `FUN_01079a2c` to make the
`sPso` string (`0x005914d0..0x005914ec`). That formatter temporarily changes
global formatting flags and restores them on its normal-return path.

Existing `sPsr`, `sPfr`, and `sPso` facts remain: `sPsr` comes from
`FUN_003b1c58`; `sPfr` is song byte `+0xc4` clamped to 0..11; `sPso` is the
formatter's UTF-8 string. `FUN_003b1c58` has a default integer `44100` and
audio-rate-looking calculation. **Hypothesis, medium confidence:** `sPsr`
describes sample rate and the other fields describe timing/format metadata.
This has not been dynamically checked. Nothing in this branch establishes
a playing/recording response field.

**Decision:** keep mode 4 outside any read-only product state query. This
task proves potentially reachable mutation instructions; it does not claim
that every song or every mode 4 invocation changes an on-disk project.

## Next bounded checkpoint

The next investigation should produce a packet schema and state-semantics
table for **only command IDs 3 (play) and 7 (record)**:

1. Trace their registered handler's `flags == 2` path to its exact
   `DAT_026883a0` assignment, with machine-code crosschecks; compare with the
   named document getters and account for Live Loops/cell recording.
2. Resolve the remaining `MAPeerRouter` connection/protocol-version path and
   the one peer message needed to establish the command-state subscription.
   Do not send actionNum, transport flags, position, or arbitrary commands
   as part of a state query experiment.
3. In a separately recorded experiment using only `LogicCLI-Test.logicx`,
   observe a real connected peer while the dedicated project is stopped,
   playing, then stopped. Record exact payload types and whether a complete
   initial false state is recoverable. Compare with MCU timestamps/readback.

The success criterion is an externally received, positively identified
playing value for **both true and false**, plus a defined timeout/error when
there is no valid peer or subscription. Sparse silence is not a verified
false value. Recording semantics require a separate later experiment;
this checkpoint does not authorize a record event implicitly.

Mode 4's next discriminator is a separate tempo-map experiment, with
different zero/one/multiple-event song states and checks of tempo, undo
history, and project dirty state. It is independent of the command-state
subscription work and is not a prerequisite for transport CLI integration.

## Reproduction

Fresh targeted decompilation, using the existing read-only project:

```bash
bash Tools/ghidra/query.sh Logic.arm64 q-transport-state-002-anchors \
  0x0168f070 0x014fca44 0x014fcd18 0x014fcdd8 0x010e3628
bash Tools/ghidra/query.sh Logic.arm64 q-transport-state-002-key-state \
  refs:0x01b55f80 0x016955bc 0x01a14040 0x019ae76c \
  0x010e1fd8 0x010e230c 0x003b1c58 0x01079a2c refs:0x010e3628 0x00590e30
```

The hash-gated instruction/data report can be reproduced with
`TransportStateReport.java` as the post-script of the same
`-process Logic.arm64 -noanalysis -readOnly` headless command, passing an
output file under `Research/raw/ghidra/`. It only reads the Ghidra program;
it neither attaches to nor launches Logic.
