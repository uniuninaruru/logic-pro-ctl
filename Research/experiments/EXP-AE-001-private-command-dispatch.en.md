[日本語](EXP-AE-001-private-command-dispatch.md) | [English](EXP-AE-001-private-command-dispatch.en.md)

# EXP-AE-001: aUeV/Spt2 command dispatch with an open test project

| Field | Value |
|---|---|
| Date | 2026-10-01, Asia/Tokyo |
| Logic | Creator Studio 12.3.1 (6682), `com.apple.mobilelogic` |
| macOS | 27.0 (26A5416b), arm64 |
| Test project | `/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx` |
| Initial state | `playing=false`, `recording=false`; exactly one scripting document |
| Single variable | Event class, event ID, one parameter's presence/type/value, or initial playing state per case |
| Readback | Existing `logicctl status`, backend MCU, independent of the AppleEvent reply |
| Final state | `playing=false`, `recording=false` |

## Result

The originally reported `aUeV/Spt2, sPmo=6, sPkc=-3` succeeds with the test
project open and starts playback. Native `AESendMessage` reproduces this
without using AppleScript to send the private command. Both direct commands
(`-3` play, `-5` stop) and positive mapped indices (`11` play, `1` stop) were
verified by transport feedback. The event is explicitly registered by
Logic.framework; its interpretation does not depend on inference from an
error message.

The earlier `-38` was not reproduced in this open-project run. Static evidence
identifies an exact early return when the active owner pointer is null or its
`currentSong` pointer is null, before `sPmo` or `sPkc` is inspected. It does not
establish which pointer was null in the user's earlier session.

## Document and UI observations

The first read-only document query waited while Logic displayed an audio
interface availability notification. The notification was acknowledged with
the computer-use tool. The resulting window was `LogicCLI-Test - トラック`,
with URL `file:///Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx/`.

The following standard scripting query returned:

```text
1, LogicCLI-Test, /Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx
```

```applescript
tell application id "com.apple.mobilelogic"
    set n to count documents
    if n > 0 then
        return {n, name of document 1, path of document 1}
    else
        return {n, "NO DOCUMENT"}
    end if
end tell
```

Thus this running Creator Studio instance does expose the open project as a
Cocoa scripting document. Its SDEF contains Standard Suite, Text Suite, Type
Definitions, and Type Names, and no occurrence of the four private FourCCs.
Raw SDEF: `Research/raw/20261001-appleevent-dynamic/sdef.xml`.

## AppleScript reproduction and negative controls

Raw: `Research/raw/20261001-appleevent-dynamic/osascript-controls.json`.

| Case | Event | Parameters | osascript exit / error | MCU transport |
|---|---|---|---|---|
| Baseline | `aUeV/Spt2` | `sPmo=6, sPkc=-3` | 0, no error | stopped → playing |
| ID only changed | `aUeV/ZZzz` | same | 1, `-1708` | remains playing |
| Class only changed | `ZZzz/Spt2` | same | 1, `-1708` | remains playing |
| Baseline repeated | `aUeV/Spt2` | same | 0, no error | remains playing |

The initial batch ended with `logicctl transport stop`, which returned
`verified=true`; its response is `restore-stop.json`. Subsequent batches use
native guarded stop restoration. A successful repeated play command is not a
toggle in the tested state.

## Native sender matrix

Raw: `Research/raw/20261001-appleevent-dynamic/native-results-final.json`
(final code rerun); the initial matrix remains in `native-results.json`.
Every case has `AESendMessage` status 0. Handler outcomes are separately read
from the reply's `errn` parameter. Integer parameters have descriptor type
`long` (signed 32-bit), and text controls have descriptor type `utxt`.

| Case | Changed input | Reply errn | Readback playing | Verified expectation |
|---|---|---:|---|---|
| Unknown event ID | `aUeV/ZZzz` | -1708 | false | yes |
| Unknown event class | `ZZzz/Spt2` | -1708 | false | yes |
| Missing mode | no `sPmo` | -1701 | false | yes |
| Wrong mode type | `sPmo=utxt:"6"` | 0 | false | yes, successful no-op |
| Missing key | no `sPkc`, `sPmo=6` | -1701 | false | yes |
| Wrong key type | `sPkc=utxt:"-3"` | 0 | false | yes, successful no-op |
| Zero key | `sPkc=0` | 0 | false | yes, successful no-op |
| Direct play 1 | `sPkc=-3` | 0 | true | yes |
| Play while playing | `sPkc=-3` | 0 | true | yes |
| Direct stop 1 | `sPkc=-5` | 0 | false | yes |
| Direct play 2 | `sPkc=-3` | 0 | true | yes |
| Direct stop 2 | `sPkc=-5` | 0 | false | yes |
| Mapped play | `sPkc=11` | 0 | true | yes |
| Mapped stop | `sPkc=1` | 0 | false | yes |

Each case changes one variable from its comparison case. Transport is checked
before and after each event. The native matrix confirmed all 14 expectations
and ended stopped with recording false. The full responses, target PID,
descriptors, stderr, and command argv are retained in the raw JSON.

The negative controls are consistent with Apple's definition of
[`errAEEventNotHandled`](https://developer.apple.com/documentation/coreservices/erraeeventnothandled).
The installed SDK additionally defines `errAEEventNotHandled=-1708` and
`fnOpnErr=-38` in `CarbonCore.framework/Headers/MacErrors.h`.

## Static evidence connecting inputs to behavior

The installed binary and the analyzed Ghidra copy have identical SHA-256
`2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998`.
See `Research/static-analysis/appleevent-registration.md` for handler
registration, typed Ghidra exports, state checks, modes, and the positive
mapping table. See `Research/static-analysis/appleevent-command-dispatch.md`
for independent `DfDocument` play/stop/record call sites and exact instructions.

Confirmed mode 6 behavior, simplified from decompilation and ARM64 instructions:

```c
if (activeOwner == NULL || activeOwner->currentSong == NULL)
    return -38;

mode = read_exact_long_parameter(event, 'sPmo');
if (mode == 6) {
    key = read_exact_long_parameter(event, 'sPkc');
    if (key < 0)
        command = (int16_t)(0u - (uint32_t)key);
    else if (key >= 1 && key <= 14)
        command = positive_key_table[key];
    else
        return 0;  // no-op
    dispatch_command(command, currentSong, 0, 2, 0);
    return 0;      // dispatcher outcome is not returned to the sender
}
```

This pseudocode omits the exact API error/type branches and other modes.
In particular, the actual wrong-descriptor-type checks can return 0 without
dispatching, as the native matrix demonstrates. Negative values undergo
16-bit narrowing; a production adapter must validate inputs rather than
accept arbitrary negative int32 values.

## Reproduction

From `/Users/nagataharuto/logicpro cli`, with the dedicated test project open:

```sh
swiftc Tools/research-scripts/appleevent_probe.swift -o .build/appleevent-probe

# Dry-run by default; inspect the planned cases without sending.
python3 Tools/research-scripts/appleevent_experiments.py matrix \
  --project '/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx'

# Send the bounded matrix, independently read transport, and restore stop.
python3 Tools/research-scripts/appleevent_experiments.py matrix --send \
  --project '/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx'

# Individually usable native control, with MCU verification.
python3 Tools/research-scripts/appleevent_experiments.py play --send \
  --project '/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx'
python3 Tools/research-scripts/appleevent_experiments.py stop --send \
  --project '/Users/nagataharuto/Music/Logic/LogicCLI-Test.logicx'
```

The native sender discovers the running app from bundle metadata or accepts
`--app` / `--bundle-id`, targets its PID, checks exactly one open document and
its canonical test-project path, and refuses differently named symlink targets.
Its raw reply alone always has `verified=false`; the experiment wrapper sets
`verified=true` only when the expected reply and independent MCU state match.
Restoration uses the same project guard. A recording-state or readback failure
is recorded and does not trigger an unguarded write to another project.

The Ghidra export can be reproduced with a hash-guarded read-only wrapper:

```sh
bash Tools/ghidra/appleevents.sh \
  '/Applications/Logic Pro Creator Studio.app'
```

It reuses the existing `Logic.arm64` analysis, corrects AppleEvent API types
in memory, exports exact-SDK and ABI-normalized decompilations plus owner
xrefs, and discards database changes. The installed app is only read.

## Practical limits and next experiments

- Play and stop are dynamically verified for this build and test project.
- `sPkc=-7` reaches the same command ID as `DfDocument::recordCallback`
  statically. No record event was sent; it is not dynamically verified.
- The mode-4 reply path includes `sPsr`, `sPfr`, and `sPso`, but also calls a
  function that can modify tempo data. Do not expose it as a pure status read
  until the complete side effects are established. It was not tested live.
- Modes 7–14 and file/region branches need further static interpretation before
  runtime testing. No mixer, plugin, track-selection, or seek semantics are
  claimed from these FourCCs.
- At the EXP-AE-001 research checkpoint, product `Sources/` remained unchanged. An optional AppleEvent transport
  backend can reuse the confirmed inputs while retaining independent state
  verification; MCU supplies that verification in this experiment. The subsequent
  product integration is recorded in [EXP-AE-002](EXP-AE-002-cli-backend.md).
