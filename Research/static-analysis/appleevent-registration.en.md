# SA-AE-REG-001: arm64 AppleEvent registration and Spt2 handler

Language: [日本語](appleevent-registration.md) · [English](appleevent-registration.en.md)


| Field | Value |
|---|---|
| Date | 2026-10-01, Asia/Tokyo |
| App examined | `/Applications/Logic Pro Creator Studio.app` |
| Bundle ID | `com.apple.mobilelogic` (read from this app's plist) |
| Version/build | 12.3.1 / 6682 |
| Binary | `Contents/Frameworks/Logic.framework/Versions/A/Logic` |
| Architecture | arm64 |
| UUID | `641ea797-e5a3-3ff1-8188-b36067cf8361` |
| SHA-256 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| Tools | macOS `nm`, `otool`; standard-library Python; Ghidra 12.1.4 headless |
| Experiment type | Static, read-only; no AppleEvents sent by this investigation |
| Raw evidence | `Research/raw/2026-10-01-appleevent-registration/`; targeted Ghidra queries also under `Research/raw/ghidra/q-appleevent-*.c` |

## Result

**Confirmed from machine code:** this build explicitly installs an application
handler for `aUeV/Spt2`. Its mode 6 parses `sPkc` and enters the same command
dispatcher used by other Logic command paths. Recognition is therefore not an
inference from a successful script response or a generic unknown-event handler.

**Confirmed negative result with bounded scope:** one direct C registration
call and one Objective-C registration tail call were recovered in
`Logic.framework` arm64. They register `aUeV/Spt2` and `GURL/GURL`, respectively;
neither uses `****`. This does not rule out indirect registration, framework
defaults, or handlers installed elsewhere at runtime.

## Experiment record and reproduction

Single research action: recover each direct call to the imported
`AEInstallEventHandler` and known
`setEventHandler:andSelector:forEventClass:andEventID:` stub from the arm64
disassembly, then inspect the registered handler and command-table bytes.

`Tools/research-scripts/appleevent_handlers.py` scans the app main executable,
top-level bundled frameworks and dylibs (68 binaries in this run), records
import status per binary, writes the entire arm64 disassembly locally, extracts
registration contexts, and decodes the mode-6 positive command table directly
from the Mach-O. It requires the app path rather than hardcoding the app name
or bundle ID.

```sh
python3 Tools/research-scripts/appleevent_handlers.py \
  '/Applications/Logic Pro Creator Studio.app' \
  --out Research/raw/2026-10-01-appleevent-registration
```

When the disassembly already exists, add
`--reuse-disassembly Research/raw/2026-10-01-appleevent-registration/Logic.arm64.disassembly.txt`.
The script's address anchors describe this examined build. They must be
recovered again for another version; they are not ABI stability promises.

The existing analyzed Ghidra program is `Logic.arm64` in the `logicctl` project.
These read-only targeted queries provided the original function/xref evidence:

```sh
Tools/ghidra/query.sh Logic.arm64 q-appleevent-registration refs:0x1aeca40
Tools/ghidra/query.sh Logic.arm64 q-appleevent-spot-handler 0x590e30 refs:0x590e30
Tools/ghidra/query.sh Logic.arm64 q-appleevent-selectors \
  s:setEventHandler:andSelector:forEventClass:andEventID:
Tools/ghidra/query.sh Logic.arm64 q-appleevent-objc-registration \
  refs:0x1b8ed20 0x10e3628 0x19ae630 0x1079a2c
Tools/ghidra/query.sh Logic.arm64 q-appleevent-owner-provenance \
  0x168bba4 0x146f914 0xdb6f88 0x579e1c 0x57badc
```

`Tools/ghidra/AppleEventHandlerReport.java` applies SDK-informed prototypes
transiently, exports the handler/registration/dispatcher, and records xrefs to
the current owner global. Run with `-readOnly`; the headless log explicitly
reports `Discarding changes to ... /Logic.arm64`.
Before changing any in-memory types, the post-script checks the Ghidra program
name and stored executable SHA-256 against the examined image. The wrapper
also checks the installed binary and loose analyzed copy; the database check
prevents a different program in the same project from passing those file checks.

```sh
JAVA_HOME='/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home' \
GHIDRA_HEADLESS_MAXMEM=10G \
/opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless \
  '/Users/nagataharuto/GhidraProjects/logicctl' logicctl \
  -process Logic.arm64 -noanalysis -readOnly \
  -scriptPath '/Users/nagataharuto/logicpro cli/Tools/ghidra' \
  -postScript AppleEventHandlerReport.java \
  '/Users/nagataharuto/logicpro cli/Research/raw/2026-10-01-appleevent-registration'
```

The SDK sources are the installed macOS SDK's
`CoreServices.framework/Frameworks/AE.framework/Headers/AppleEvents.h`,
`AEDataModel.h`, and `usr/include/MacTypes.h`. `OSErr` is signed 16-bit; `Size`
is signed 64-bit `long`; `SRefCon` is `void *` under LP64. `AEDesc` has the
SDK's two-byte packing, a four-byte type plus eight-byte handle. The imported
handler return is `OSErr`; the caller tests the full 32-bit `w0` register.

Two decompilation outputs deliberately distinguish the layers:

- `typed-decompiled.c` uses exact SDK-sized `OSErr` API return declarations.
- `abi-normalized-decompiled.c` models imported API return registers as 32-bit
  `OSErr_W0_register` to avoid Ghidra's unknown-upper-bits/`CONCAT` artifacts.
  The application handler itself still returns SDK `OSErr`. This rendering aid
  does not redefine the SDK interface.

Some unrelated C++/Objective-C function signatures remain unresolved. Raw
decompiler casts or pointer names in those paths are not evidence of their
actual source types. The curated pseudocode and assembly are the evidence for
the claims below.

## Registration sites

| Mechanism | Call site | Class / ID | Handler | Additional arguments |
|---|---|---|---|---|
| `AEInstallEventHandler` | `0x004f11fc` inside `FUN_004f0d24` | `aUeV` / `Spt2` | `0x00590e30`, `FUN_00590e30` | refcon `0`; system handler false |
| `NSAppleEventManager setEventHandler:andSelector:forEventClass:andEventID:` | tail branch `0x017ccb08` inside `CLgAppManager::addURLhandler`, `0x017ccab8` | `GURL` / `GURL` | receiver is app manager; selector `handleGetURLEvent:withReplyEvent:` | guarded by `FeatureAvailable(4)` |

The private registration occurs immediately after the startup progress string
`InitializingSpotRegionHandlers` and before
`InitializingSequencerandAudioEngines`. The `AEInstallEventHandler` return
status is not checked here; static registration intent alone does not prove
runtime installation succeeded.

Exact import stub: `0x01aeca40`. Handler address comes from
`adrp x2, 0x590000; add x2, x2, #0xe30`. The class/ID immediates are
`0x61556556` and `0x53707432`, not strings found by scanning resources.

The Objective-C selector text is at `0x01f59e5a`, referenced through selector
pointer `0x02565700` by stub `0x01b8ed20`. That stub has one recovered caller,
the `GURL/GURL` tail branch. The receiver and selector are distinct arguments:
`x2` is the app manager and `x3` is `handleGetURLEvent:withReplyEvent:`;
`w4`/`w5` are event class/ID.

## Handler entry and the source of -38

Entry at `0x00590e30` first loads the pointer at global `0x0276de68`, then
loads the pointer at offset `+0xc0`. Either null pointer branches to
`0x00591054`, which sets `w22 = 0xffda`; the epilogue at `0x00591070`
sign-extends its low 16 bits and returns **-38**.

The semantic name of the second pointer is independently supported by named
Objective-C getters:

- `LgLogicRemoteController::song`, `0x0168bba4`: return
  `global_0276de68 ? *(void **)(global_0276de68 + 0xc0) : NULL`.
- `CLgSelectionBasedAudioViewController::currentSong`, `0x0146f914`:
  identical pointer load and return.
- `PrefsGlobalView::song`, `0x00db6f88`: identical in the targeted decompile.

Thus **-38 is a pre-parameter current-song availability failure in this
handler**. It is independent of a parameter value `sPkc = -38`, which maps to
command 38 after the current-song check succeeds.

The owner global can change. `FUN_00579e1c` at `0x00579e1c` clears it on a
zero argument and otherwise validates a candidate against the pointer vector
`0x02633be0..0x02633be8` before selecting it; `FUN_0057badc` saves the old
global through an output pointer and temporarily selects a validated
candidate. This is additional provenance for active owner state; the owner's
original C++ class name is still unknown. The complete static global-xref
inventory is recorded in `owner-state-xrefs.tsv` (raw).

## Mandatory mode parameter

After the current-song check, the handler calls:

```c
AESizeOfParam(event, 'sPmo', &actualType, &size);
// require actualType == 'long'
AEGetParamPtr(event, 'sPmo', 'long', &actualType,
              &global_02633d60, size, &size);
```

The static comparison is exact `'long'` (`0x6c6f6e67`), not an implicit
coercion request accepting arbitrary descriptor types. If `AESizeOfParam`
fails, its error is returned. If it succeeds but the type differs, the code
returns that successful status (zero) immediately, without dispatch. The same
pattern exists for the mode-6 `sPkc` parameter. Therefore a successful
AppleEvent reply alone cannot prove a command ran.

The parser passes the size returned by `AESizeOfParam` onward; no independent
`size == 4` guard was found in the corresponding machine-code span. Normal
`'long'` inputs are four-byte signed integers. Malformed payloads were not
tested, and callers should generate canonical four-byte descriptors.

## Mode 6: exact command conversion

`sPmo = 6` branches at `0x00591308`. It requires `sPkc` of exact type `'long'`
and loads its four-byte signed value. The branch at `0x0059136c` tests bit 31.

For a negative value, instructions `neg w8, w8` (`0x00591578`) and
`sxth w0, w8` (`0x0059157c`) produce the signed low 16 bits of the 32-bit
negation. Consequently `-3` dispatches command 3, `-5` dispatches command 5,
and `-38` dispatches command 38. Values outside the ordinary 16-bit command
range truncate: for example `-65539` also maps to command 3. This is a static
arithmetic result, not a dynamic test recommendation.

For nonnegative `sPkc`, the sequence
`sub w9, w8, #15; cmn w9, #14; b.lo no_op` accepts precisely values 1..14.
The handler loads the corresponding unsigned halfword and then uses the same
`sxth`. Zero and values >=15 return successful no-op.

Table at `0x01cbeb70`, 15 little-endian signed 16-bit values:

| sPkc index | Dispatched command |
|---:|---:|
| 0 | not accepted; stored table value 0 |
| 1 | 5 |
| 2 | 535 |
| 3 | 10 |
| 4 | 11 |
| 5 | 12 |
| 6 | 13 |
| 7 | 7 |
| 8 | 1272 |
| 9 | 1273 |
| 10 | 4 |
| 11 | 3 |
| 12 | 14 |
| 13 | 754 |
| 14 | 753 |

Bytes:
`0000050017020a000b000c000d000700f804f904040003000e00f202f102`.
Command names and dynamic behavior belong in the separate dispatcher and
experiment records; the table itself proves only the numeric conversion.

Call at `0x00591590` is:

```c
FUN_008663d4(command, currentSong, 0, 2, 0);
return 0;
```

The dispatcher result is ignored and the handler returns zero after the call.
`FUN_008663d4` indexes command entries through table `0x026883b0`, checks the
range `< 0x1357`, resolves a special indirect command entry, sets command-source
state to 2, and eventually calls `FUN_00865cec`. Its failed-command path can
call `NSBeep` and display `Commandnotavailablebecause___`. Thus recognized
event, accepted payload, and completed requested command are separate facts.
See `SA-004-command-and-engine-boundaries.md` and
`appleevent-command-dispatch.md` for the command table/handler analysis.

## Other proven branches and fields

| Mode | Additional input / branch | Proven calls or reply fields |
|---:|---|---|
| 4 | no `sPkc` read; reply descriptor must differ from `'null'` | `sPsr:long` four bytes; `sPfr:long` four bytes; `sPso:utf8` variable bytes |
| 7 | `sPpn` exact `utxt` or `utf8` | `FUN_017af4ac(currentSong, NSString)` |
| 8 | same text parsing | `FUN_017b1c9c` |
| 9 | same text parsing | `FUN_017afd88` |
| 10 | same text parsing | `FUN_017b1e8c` |
| 11 | same text parsing | `FUN_017b174c` |
| 12 | same text parsing | `FUN_017b201c` |
| 13 | no text parameter read | `FUN_017b22f8(currentSong)` |
| 14 | same text parsing | `FUN_017b19c0` |
| all other modes | file/region branch | `sPfi` exact `bmrk`, `furl` or `fsrf`; optional `sPve`, `sPtn`, `sPss`, `sPst`, `sPsp` exact `long`; mandatory `sPrg` exact `utxt` or `utf8`; then `FUN_00591de0` |

Text is converted to an NSString through UTF-16 `CFStringCreateWithCharacters`
or UTF-8 `CFStringCreateWithBytes`. After the listed text-mode action the
handler puts `sPer:long = 0` into a non-null reply. It does not propagate the
action function's return as a reliable operation status. Wrong text/file
descriptor types can likewise produce successful no-op.

For mode 4, `sPsr` is the return of `FUN_003b1c58(currentSong)` and `sPfr` is
the signed byte at currentSong `+0xc4`, clamped into 0..11. `sPso` is the UTF-8
encoding of the string returned by `FUN_01079a2c`. The binary proves these
relationships. Human meanings of the abbreviated keys are not yet dynamically
validated.

**Mode 4 is not established read-only.** Before producing `sPso`, it invokes
`FUN_010e3628(currentSong, -1, 0)`. The targeted decompile includes tempo state
creation/normalization, writes to current-song state and a
`ChangeTempo_und` label. The branch must be treated as potentially mutating
until a dedicated experiment resolves its behavior.

Some other branches have explicit file writes/import/export-looking code:
mode 8 calls `writeToFile:atomically:encoding:error:`, mode 9 updates a
metadata property list (`FileChecks`), mode 11 checks MIDI file types and
imports parsed data, and mode 12 creates a temporary file and an `.aac` path.
These are static observations, not complete validated operation definitions.
No live probes of these modes were performed in this investigation.

## Remaining unknowns

- Original owner/current-song C++ type names; every selector-backed offset
  claimed above is proven without them.
- Meaning, supported values, and units of non-command mode inputs/replies.
- Whether indirect or system/framework-installed wildcard handlers exist.
- Runtime handler-table contents and the ignored registration return status.
- Reliable operation success/readback for commands beyond experiments
  separately documented for the dedicated test project.

No static result here changes `Sources/`, disables system protection, alters
the application, or relies on a real music project.
