# Private AppleEvent to transport command bridge

Language: [日本語](appleevent-command-dispatch.md) · [English](appleevent-command-dispatch.en.md)


## Result

Static evidence connects `aUeV/Spt2`, with `sPmo = 6`, to Logic's existing
command dispatcher. For negative `sPkc` values the handler negates the value,
narrows it to a signed 16-bit command ID, and dispatches it. Independently
identified `DfDocument` transport methods use command IDs 3 (play), 5 (stop),
and 7 (record) with the same dispatcher.

Consequently, `sPmo = 6, sPkc = -3` selects the command used by the document's
play callback in this binary. The corresponding intended stop/record inputs
are `-5` and `-7`. This is a binary-derived connection, not a guess based on
parameter names. Dynamic success, transport-state readback, and project-state
requirements are separate evidence; this document performs no dynamic event
experiment.

## Sources and provenance

| Field | Recorded value |
|---|---|
| Date | 2026-10-01 |
| Application version | 12.3.1 (6682), read from installed `Contents/Info.plist` |
| Image | `Contents/Frameworks/Logic.framework/Versions/A/Logic`, arm64 |
| Installed image SHA-256 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| Ghidra analyzed copy | `/Users/nagataharuto/GhidraProjects/logicctl/bin/Logic.arm64` |
| Analyzed copy SHA-256 | identical to installed image SHA-256, freshly checked |
| Ghidra exports | `Research/raw/ghidra/q-appleevent-spot-handler.c`, `q-cmd.c`, `q-cmdtable.c`, `q-menu.c`, `Logic.arm64.functions.tsv` |
| Independent instruction snapshots | `Research/raw/20261001-084358-command-dispatch/{spot_handler,play,stop,record,dispatcher,command_registration}.asm` |
| Provenance manifest | `Research/raw/20261001-084358-command-dispatch/manifest.json`, including commands and SHA-256 for source/export files |

The method names and function bounds come from the Ghidra Objective-C
analysis and its function export. Selected instructions were disassembled
again with Xcode's `llvm-objdump` against the matching analyzed copy. All
addresses below are preferred VM addresses in this image, without a live
process's ASLR slide.

## 1. Registered event and mode-6 handler

Source: `q-appleevent-spot-handler.c`, query `0x590e30` and its registration
caller `FUN_004f0d24`. The registration caller contains:

```c
_AEInstallEventHandler(0x61556556, 0x53707432, FUN_00590e30, 0, 0);
```

The values decode as `aUeV` and `Spt2`. The handler at `0x590e30` reads
parameter `0x73506d6f` (`sPmo`) with descriptor type `0x6c6f6e67` (`long`),
stores the mode at global `0x2633d60`, and selects this branch:

```c
if (DAT_02633d60 == 6) {
    /* size/type validation omitted from this excerpt */
    _AEGetParamPtr(event, 0x73506b63, 0x6c6f6e67,
                  &actualType, &keyCommand, size, &actualSize);
    if ((int)keyCommand < 0) {
        command = -(short)keyCommand;
    } else {
        /* bounded positive values use a separate lookup table */
        command = *(short *)(&DAT_01cbeb70 + keyCommand * 2);
    }
    FUN_008663d4((int)command, song, 0, 2, 0);
}
```

This is a shortened, renamed excerpt for readability. Exact decompiler
variable types and full error paths are retained in the raw export. Assembly
confirms the behavior without depending on those inferred C types:

| Address | Instruction / significance |
|---:|---|
| `0x590e7c` / `0x590e80` | form base constant `w23 = 0x73506669` |
| `0x590e84` / `0x590ecc` | `w1 = w23 + 0x706 = 0x73506d6f` (`sPmo`) |
| `0x590ee4` | call the `AEGetParamPtr` stub with that keyword and `long` type |
| `0x591304` | load the stored mode |
| `0x591308` / `0x59130c` | compare to 6 and leave this branch if unequal |
| `0x591340` | `w1 = w23 + 0x4fa = 0x73506b63` (`sPkc`) |
| `0x591354` / `0x591358` | construct requested type `0x6c6f6e67` (`long`) in `w2` |
| `0x59135c` | call `AEGetParamPtr`, writing the value to `[sp + 0x30]` |
| `0x591368` / `0x59136c` | load the parameter and test signed bit 31; negative values branch to `0x591578` |
| `0x591578` | `neg w8, w8` |
| `0x59157c` | `sxth w0, w8`: signed 16-bit command ID |
| `0x591580`–`0x59158c` | pass saved song pointer in `x1`, then `0, 2, 0` in the remaining arguments |
| `0x591590` | `bl 0x8663d4`: invoke the command dispatcher |

Both the positive-parameter lookup path and the negative path join at
`0x59157c`. The negative encoding is exact for the small values under
discussion; this is not a claim that arbitrary negative 32-bit numbers are
valid command IDs.

The stub identities are provided by the Ghidra import analysis; the generic
`llvm-objdump` nearest-symbol annotations are not used to infer their names.
See the separate handler-registration analysis for its complete argument and
error contract.

## 2. Independent transport method call sites

Source: `q-cmd.c`, `Logic.arm64.functions.tsv`, and the freshly saved bounded
assembly snapshots.

| Objective-C method | Method entry | Command setup | Dispatcher call | Command ID |
|---|---:|---:|---:|---:|
| `-[DfDocument _playCallbackWithWillFreeze:]` | `0x14fba08` | `0x14fbae4` | `0x14fbaf4` | 3 |
| `-[DfDocument stop]` | `0x14fc100` | `0x14fc2f8` | `0x14fc308` | 5 |
| `-[DfDocument recordCallback]` | `0x14fb364` | `0x14fb550` | `0x14fb560` | 7 |

Play:

```asm
0x14fbae0  mov x1, x0
0x14fbae4  mov w0, #3
0x14fbae8  mov w2, #1
0x14fbaec  mov w3, #2
0x14fbaf0  mov x4, #0
0x14fbaf4  bl  0x8663d4
```

Stop:

```asm
0x14fc2f4  mov x1, x0
0x14fc2f8  mov w0, #5
0x14fc2fc  mov w2, #1
0x14fc300  mov w3, #2
0x14fc304  mov x4, #0
0x14fc308  bl  0x8663d4
```

Record:

```asm
0x14fb54c  mov x1, x0
0x14fb550  mov w0, #7
0x14fb554  mov w2, #1
0x14fb558  mov w3, #2
0x14fb55c  mov x4, #0
0x14fb560  bl  0x8663d4
```

The play callback has a synchronized-transport priming branch that postpones
the dispatcher call. The normal branch shown above uses 3. The record method
also has a separate early tail call to this dispatcher at `0x14fb408`, with
command 7. The stop method has cleanup and state-update code surrounding its
command-5 call. Accordingly these IDs identify command selection, not the
complete behavior of every transport mode.

The document callbacks pass third argument 1; the AppleEvent branch passes 0.
The dispatcher converts that boolean to `0x40000000` for its lower executor
when nonzero. This difference remains material when comparing document UI
callbacks with direct AppleEvent invocation.

## 3. Dispatcher and table evidence

Source: `q-cmd.c` (`FUN_008663d4`), `q-cmdtable.c` (`FUN_00865cec`), `q-menu.c`
(`FUN_00864230`), and `dispatcher.asm` / `command_registration.asm`.

The dispatcher is a shared internal command boundary. At `0x86640c`–
`0x866414` it bounds the command ID at `0x1356` (4950 inclusive), then loads
an entry from a pointer table at `0x26883b0` using the ID as index:

```asm
0x86640c  mov w8, #0x1356
0x866410  cmp w22, w8
0x866414  b.hi 0x866464
0x866418  adrp x25, 0x2688000
0x86641c  add x25, x25, #0x3b0
0x866420  ldr x24, [x25, w22, sxtw #3]
```

It recognizes an alias handler at entry offset `+0x18` and resolves aliases
through table `0x1cd1d98`, then calls lower executor `0x865cec`. The lower
executor uses view/song context, focused views, and the command groups. A
valid number alone does not ensure that a command is available in the current
project state.

Command-table builder `0x864230` handles 40-byte entries. Its loop advances
the entry pointer by `0x28` at `0x8642a4`. At `0x8642d8` it reads the signed
16-bit command field at the start of the entry; at `0x8642dc` it stores the
entry pointer into `0x26883b0[id]`. Function/argument pairs reside at entry
offsets `0x18` / `0x20`, as the `ldp` at `0x8642b0` and indirect call at
`0x864340` demonstrate. These instructions corroborate the command-ID
interpretation instead of inferring it from names alone.

## Reproduce the focused checks

After identifying the current installed executable and ensuring its hash
matches the analyzed copy, these existing Ghidra queries regenerate the
relevant function/caller exports:

```sh
Tools/ghidra/query.sh Logic.arm64 q-command-bridge \
  0x590e30 0x8663d4 'callers:FUN_008663d4'
Tools/ghidra/query.sh Logic.arm64 q-command-table \
  0x864230 0x865cec
```

Do not run concurrent headless queries against the same Ghidra project. A
bounded independent assembly check is:

```sh
xcrun llvm-objdump --arch=arm64 --disassemble \
  --start-address=0x14fba08 --stop-address=0x14fbb10 \
  '/Users/nagataharuto/GhidraProjects/logicctl/bin/Logic.arm64'
```

Use ordinary disassembly mode for these bounds. On this installation adding
`--macho` caused `llvm-objdump` to ignore the requested start/stop addresses
and disassemble the full text section. The bounded snapshot manifest records
the working commands for each method. No new concurrent Ghidra query was run
for this triangulation.
