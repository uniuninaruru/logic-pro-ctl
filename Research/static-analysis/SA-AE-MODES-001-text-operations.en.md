[日本語](SA-AE-MODES-001-text-operations.md) | [English](SA-AE-MODES-001-text-operations.en.md)

# SA-AE-MODES-001 — Static inputs, processing, and replies for AppleEvent modes 7–14

Modes 7–14 of `aUeV/Spt2` branch into setting loading, XML generation and file writing, FileChecks persistence, plugin setting application, MIDI file processing, a possible audio output path, window-mediated processing, and file/record updates. This report records ARM64 calls and stores. It does not establish the complete operation meanings, runtime success, completion, Undo, or retry safety. Every row has `runtime_verified=false`; no product capability was added.

The shared reply `sPer:long=0` does not report operation success. Mode 13 does not write that reply. Mode 8 also contains a conditional record write inside its string generator, so it cannot be classified as read-only.

## Target and evidence

| Item | Value |
|---|---|
| Analysis date | 2026-10-02, Asia/Tokyo |
| Version | Logic Pro Creator Studio 12.3.1 / build 6682 |
| Image | `Contents/Frameworks/Logic.framework/Versions/A/Logic`, thin ARM64 |
| Saved Executable SHA-256 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| Ghidra program / language | `Logic.arm64` / `AARCH64:LE:64:AppleSilicon` |
| Addresses | Unslid addresses in this image, not runtime pointers |
| Method | Bounded Ghidra headless `-readOnly -noanalysis` decompilations and instruction/pointer exports, checked against branches, register dataflow, and selector references. Instruction/pointer scripts guard the stored program name and Executable SHA-256 |
| Execution | This analysis sent no AppleEvents, performed no Logic runtime actions or connections, and changed no product code. Headless exports saved local raw evidence without reanalyzing or modifying the analysis DB |

See [SA-IDENTITY-001](SA-IDENTITY-001-binary-inputs.en.md) for binary identity and [appleevent-registration](appleevent-registration.en.md) for registration and the shared entry point. Export/log/script hashes and provenance are in [appleevent-mode-analysis-manifest.json](appleevent-mode-analysis-manifest.json). Local evidence is listed below. `Research/raw/` is ignored by Git; this report curates addresses and short instruction excerpts.

- [q-appleevent-modes-001-machinecode.txt](../raw/ghidra/q-appleevent-modes-001-machinecode.txt): handler, eight helpers, instruction bytes; the header records the SHA-256 above.
- [q-appleevent-modes-callees-001-machinecode.txt](../raw/ghidra/q-appleevent-modes-callees-001-machinecode.txt): instructions and references for `0x001a1dcc`, `0x01a15c7c`, `0x017b0308`, `0x004b2a08`, and `0x01b215e0`.
- [q-appleevent-mode-strings-001.txt](../raw/ghidra/q-appleevent-mode-strings-001.txt): contents, pointers, and lengths of nine CFStrings and the full FileChecks selector, guarded by the same Executable SHA-256; no data mutations.
- [q-appleevent-xml-block-001-machinecode.txt](../raw/ghidra/q-appleevent-xml-block-001-machinecode.txt) and [q-appleevent-xml-block-001.c](../raw/ghidra/q-appleevent-xml-block-001.c): mode 8 block `0x017b0598` and iterator `0x01a15eb0`; block ABI and iterator stores checked against instructions.
- [q-appleevent-xml-node-001-machinecode.txt](../raw/ghidra/q-appleevent-xml-node-001-machinecode.txt), [q-appleevent-xml-node-001.c](../raw/ghidra/q-appleevent-xml-node-001.c), and [q-appleevent-xml-strings-001.txt](../raw/ghidra/q-appleevent-xml-strings-001.txt): factory/child boundaries of `0x0154d8fc`, newline, and type/format pointer tables and strings; not a complete XML schema export.
- [q-appleevent-text-modes-001.c](../raw/ghidra/q-appleevent-text-modes-001.c) and [q-appleevent-object-resolvers-001.c](../raw/ghidra/q-appleevent-object-resolvers-001.c): readable control-flow aids. Inferred C parameter/return types and variable names are not authoritative evidence.
- [appleevent-text-modes.tsv](../protocol/appleevent-text-modes.tsv): compact eight-mode mapping.

## Shared input and reply ABI

The handler begins at `0x00590e30`. It reads the owner at `0x0276de68` and currentSong at `owner+0xc0`. If either is null, the branch at `0x00591054` returns **-38**. `sPmo` must have the exact descriptor type `long`. In this report, `song` refers to this currentSong, not a public stable ID.

| Mode | Call in handler | Helper | Additional input | Reply after the normal call path |
|---|---|---|---|---|
| 7 | `0x005911e8` | `0x017af4ac` | `sPpn:utxt` or `sPpn:utf8` | `sPer:long=0` for a non-null reply |
| 8 | `0x005912b0` | `0x017b1c9c` | Same | Same |
| 9 | `0x00591198` | `0x017afd88` | Same | Same |
| 10 | `0x00591290` | `0x017b1e8c` | Same | Same |
| 11 | `0x00591170` | `0x017b174c` | Same | Same |
| 12 | `0x005912a0` | `0x017b201c` | Same | Same |
| 13 | `0x005911d4` | `0x017b22f8` | Does not read `sPpn` | Does not write `sPer` on this path |
| 14 | `0x005911b8` | `0x017b19c0` | `sPpn:utxt` or `sPpn:utf8` | `sPer:long=0` for a non-null reply |

`AESizeOfParam` for `sPpn` is called at `0x00590f88`; type comparisons occur at `0x00590f98–0x00590fb4`. UTF-8 goes through `CFStringCreateWithBytes` (`0x0059101c`, encoding `0x08000100`, externalRepresentation `0`). UTF-16 goes through `CFStringCreateWithCharacters` (`0x00591100`, a signed division of actualSize by 2 supplies the character count). The resulting NSString is held in `x23` and passed to the helper as `x0=song, x1=NSString`. No check rejecting an odd UTF-16 byte count is visible in this interval.

An unaccepted `sPpn` type branches `0x00590fb4 → 0x005911d8`, calls no helper, returns handler status `0`, and does not write `sPer`. A nil NSString branches `0x0059113c → 0x005912b4`, so the ordinary `sPer=0` can be written without invoking a helper. Nonzero `AESizeOfParam` / `AEGetParamPtr` errors reach the exit status. Neither a handler return of `0` nor `sPer=0` proves that an operation ran.

The shared tail contains these actual instructions. No instruction derives status from a helper result.

```asm
005912b4  mov w22,#0x0
005912b8  str wzr,[sp,#0x30]
005912d0  add x3,sp,#0x30
005912d8  mov w1,#0x6572             ; combined with movk: sPer
005912e0  mov w2,#0x6e67             ; combined with movk: long
005912e8  mov w4,#0x4
005912ec  bl 0x01aeca4c              ; AEPutParamPtr
005912f0  mov x22,x0
00591070  sxth w0,w22
```

The result of `AEPutParamPtr` itself reaches the handler's signed 16-bit return. Mode 13 instead sets `w22=0` at `0x005911d8` after its call and exits directly. Helper results, file errors, and downstream completion are not conveyed in the reply.

## Confirmed object-resolution boundaries

`0x001a1dcc(song, uint32 at song+0xd4, uint16 at song+0xd8)` sign-extends its third argument with `sxth` and requires a value of at least 1. It checks song magic `0xabc04723` / `0xabc04713`. Second-argument values `0x7ffffff8` / `0x7ffffffc` take special branches. Other values must have their low two bits and sign bit clear; a shift right by 2 selects a pointer-array entry. From selected-container bounds at `+0x330/+0x338`, it returns the **0x50-byte record** indexed by `(arg3 & 0x7fff)-1` (`0x001a1eac–0x001a1ef0`). Failure returns null.

This establishes dataflow between `song+0xd4/+0xd8` and an internal record. It does not establish a UI track number, plugin slot, region ID, or identifier lifetime. Parts of container selection are also inlined into modes 8 and 9.

`0x01a15c7c` uses another pointer array at `song+0x788 → +0x1e0/+0x1e8`, checks record `+0x69==0x11` and signed byte `+0x335<13`, then uses the array at `+0x150/+0x158` and signed short record field `+0x320` to return an object. A non-null third argument receives an intermediate container (`0x01a15d84`). Earlier failures clear both the return and out parameter, but inner-index failure after that store (`0x01a15d8c..0x01a15d9c`) can return 0 with a non-null out parameter. These unnamed internal structures are not stable external identifiers. See [TARGET-003](SA-AE-TARGET-003-target-resolution.en.md).

## Observations and hypotheses by mode

Confidence describes the proposed operation name, not runtime success. Directly observed calls and stores are separated in the detailed sections below.

| Mode | Hypothesis: unverified operation meaning | Confidence | Main machine-code boundary |
|---|---|---|---|
| 7 | Load a channel setting / patch into a selected target | Medium-high | `loadSettingFromURL:…importFlags:`, songID, track and ginst in/out pointers |
| 8 | Write selected-target Patch / Channels XML to a file | High for the XML path | XML selector → Patch wrapper → NSString → file write; target-byte and iterator cache / entry stores |
| 9 | Update FileChecks metadata in a specified plist | Medium-high | `createFileChecksForTrack:inSong:inSeqID:`, plist read/write |
| 10 | Load and apply a target plugin setting / preset | Medium-high | `.aupreset`, loader, apply call, object flags, notification string |
| 11 | Import MIDI using current position and track | Medium-high | MIDI file types, parser, song/buffer/track/position arguments, song flags |
| 12 | Generate a temporary current-track output and convert to AAC | Medium | Temporary CFileRef, possible generation, extension change, possible conversion, removal |
| 13 | Run an editor action through a type `0x7049` window | Low | `fenster` and a tail call to `0x005e559c` |
| 14 | Update a selected target's file reference, name, and related fields | Medium | Filename / parent-directory strings, buffer stores, candidate setters |

### Mode 7 — `0x017af4ac`

At `0x017af4e4`, the helper resolves a target record and loads its 32-bit `+0x20` field into `w22`. It compares pathExtension against CFString `0x0233f748` with options `1`; equality calls `0x017af538 → 0x002c66f8(song,id,1,0)`. The pointer/data output confirms that CFString as **`cst`**, length `3`, payload `0x01d5c656`.

It allocates the receiver identified as `ChannelSettingsUtilities` in the decompilation and calls `initWithSongID:` using `song+0x860`. Selection field `song+0xd8` maps signed `-1` and `0` to `-1`, otherwise subtracting 1, in the local passed to `intoTrack:`. `0x017af5cc → 0x01b59e00` calls **`loadSettingFromURL:withCategory:intoTrack:withGinst:inFolderWithID:enablePatchMerging:importFlags:`** with category `0`, pointers to track / ginst locals, folder value `song+0x10`, patchMerging `0`, and stack importFlags `0x10c`.

The normal tail `0x017af5e0–0x017af5fc` has no explicit `w0/x0=0` assignment. The decompiler's `return 0` is not evidence of operation status. After the helper, the caller runs a loop comparing a counter with the result of `0x0065d80c` and conditionally calls `0x0065d5a8` and other functions (`0x00591220–0x00591284`). Calling this loop a setting-load completion wait remains unproven.

### Mode 8 — `0x017b1c9c` → `0x017b0308`

The generator's result at `0x017b1db0` is retained into `x20`. The write receiver at `0x017b1de4` is that **generated string**, not song. After `maStringByResolvingSymlinksAndAliasesInPath`, `writeToFile:atomically:encoding:error:` (`0x017b1df4 → 0x01bcd400`) receives atomically `1`, numeric encoding `4`, and an NSError pointer. A zero result bit 0 triggers NSLog. The normal tail `0x017b1e38–0x017b1e50` has no explicit status return.

The generator calls `0x017b04b8 → 0x0154d8fc`, uses its returned object as the receiver for `XMLStringWithOptions:1` (`0x017b04cc`), and wraps the result with `stringWithFormat:` (`0x017b0518`) before returning an autoreleased object. A second path passes block `0x017b0598` to `0x01a15eb0` to populate a NSMutableString. A bounded follow-up confirms block arguments, filtering, XML append, iterator stores, and factory/child boundaries of `0x0154d8fc`. [XML-002](SA-AE-XML-002-channel-node-schema.en.md) confirms factory/child tags, attributes, and omission rules. Complete target coverage and reimport compatibility remain unestablished.

The wrapper is established by stack varargs and CFString bytes. Format `0x02414488` is `%@%@\n%@` (length `7`); first object `0x024144a8` is `<?xml version="1.0"?>\n<Patch>\n<Channels>\n` (length `41`); second object is generated content `x20`; third object `0x024144c8` is `</Channels>\n</Patch>` (length `20`). The Patch / Channels XML wrapper is therefore confirmed. Channel/slot coverage and whether the output can be reimported remain unproven.

A direct side effect is visible: after scanning forward through 0x50-byte records, if the next relevant record's `+0x12` byte exceeds the target's byte by at least 2, `0x017b03ac: strb w9,[x1,#0x12]` writes the target. Its meaning is unknown, but classifying XML generation as read-only would be incorrect.

**Block ABI and filtering.** The stack block constructed at caller `0x017b03e0–0x017b041c` matches the invocation dataflow. The block below is retained by the iterator. The callback's C signature shows three parameters, but the actual call passes four.

| Item | Instruction-confirmed behavior |
|---|---|
| Invoke | Block `+0x10 = 0x017b0598`. Iterator `0x01a15fe4–0x01a15ff4` indirectly calls it with `x0=block, x1=song, x2=entry, x3=&stopByte` |
| String capture | NSMutableString at block `+0x20`, read as the append receiver at callback `0x017b0690` and `0x017b06f8` |
| Filter capture | uint32 at block `+0x28`, captured from the original 0x50-byte record `+0x20`. Callback `0x017b05ac–0x017b05c4` proceeds only if entry `+0x30` **or** `+0x48` equals it |
| Stop byte | Initialized to 0 at iterator `0x01a15f84`, with bit 0 tested after invocation. This callback neither consumes nor updates its fourth argument |

The callback checks entry `+0x69==0x11`, signed byte `+0x335<=12`, and song magic. It chooses `base=0x20` for byte<=9 or `0x50` otherwise, requiring base+byte×4 to be nonnegative. It resolves an object through the pointer array at `song+0x788 → +0x150/+0x158`, selected-container bounds `+0x50/+0x58`, and entry signed short `+0x320`. Entry `+0x30` selects an element from `+0x1e0/+0x1e8`, falling back to the first element for an invalid/nil selection, and its `+0x86` UTF-8 string supplies a candidate name.

The **returned object** from `0x017b06b0 → 0x0154d8fc(object,nameNSString)` receives `XMLStringWithOptions:1` (`0x017b06c4`). The resulting XML string is appended to the captured NSMutableString at `0x017b06dc`. The tail call at `0x017b0714` appends CFString `0x02344a28` to that same string. A separate pointer/data export confirms its contents as **newline** (payload `0x01d70fd1`, length `1`, bytes `0a00`).

**Iterator stores.** When song `+0x658` equals `0xffffffff`, `0x01a15eb0` scans the pointer array at `song+0x788 → +0x1e0/+0x1e8`, linking entries with `+0x69==0x11` by encoded index (array index×4). It stores the first index at song `+0x658` (`0x01a15f10`), each next index at the previous entry `+0x6b4` (`0x01a15f64`), and `0xffffffff` at the tail (`0x01a15f74`). No matching entry stores song `+0x658=0xfffffffe` (`0x01a15f80`). A non-initial cache skips this construction.

For every traversed valid type `0x11` entry, **`0x01a15fdc: str w21,[x2,#0x30]`** executes before loading the next index from `+0x6b4` and invoking the callback. Thus entries rejected by the callback's XML filter receive this store first. These observations establish stores, not that existing values always change, persist to the project, or set dirty/Undo state. The iterator's normal tail `0x01a16000–0x01a1601c` also has no explicit return `0`; the decompiler's `return 0` is not a success status. Do not equate every entry with a UI track or stable entity.

**Bounded XML node factory check — `0x0154d8fc`.** It saves the internal object from `x0` in `x22` and retains the name from `x1`. If name is nil, it calls `stringWithCString:encoding:` on object `+0x73` with numeric encoding `0x1e`. The receiver at `0x0154d9c8 → 0x01af4980` is the class slot identified as `MAXMLElement` in the decompilation. Arguments are `x2=name, x3=typeCFString, x4=formatCFString, x5=emptyCFString`. [XML-002](SA-AE-XML-002-channel-node-schema.en.md) adds the full selector, implementation resolved through relative method metadata, and XML tag/attribute names.

| Label selection | Instruction and pointer/data mapping |
|---|---|
| Type | If unsigned short `((object uint16 type & ~0x8)-0x40)` is below 7, use table `0x02326220–0x02326250`. Indices 0–6 are `AudioTrack`, `Other`, `Aux`, `Instrument`, `Output`, `Bus`, `Master`. Otherwise use `Other` CFString `0x02362368` |
| Format | If object byte `+0x89` is below 5, use table `0x02326258–0x02326278`. Indices 0–4 are `Mono`, `Stereo`, `Left`, `Right`, `Surround`. Otherwise use empty CFString `0x02338b48` |

These are channel-like classification labels passed to the XML-object factory. Strings such as `AudioTrack` do not establish UI track entities, stable IDs, or a public schema.

Two groups use signed short object counts `+0x4e` / `+0x4c`. They select from pointer bounds `+0x30/+0x38` at indices `i + signed(+0x4c) + signed(+0x4a)` / `i + signed(+0x4a)`, respectively. With type bit `0x40`, type `!=0xc0`, an in-range index, and non-null child pointer, `0x0154da68` / `0x0154daf4` call `0x0154dcb4(child,object)`. Non-null returned children are added to the array. A nonempty array is passed to wrapper `0x0154db2c → 0x01af4b40`, then root `addChild:` at `0x0154db44`. [XML-002](SA-AE-XML-002-channel-node-schema.en.md) establishes the static child/wrapper structure. It does not establish public IDs or reimport compatibility.

A subsequent fresh array scans the signed short `+0x4a` group, but this interval contains no child generation or `addObject:` call. The contents of an ordinary empty `arrayWithCapacity:` are not increased in this body; the `0x01af4b80` / `addChild:` code is only guarded by a nonzero count. This is not confirmed runtime inclusion. A nonzero result from `_IsALPCheckForEmptySlots` at `0x0154dbfc` passes the internal object and XML root to `0x0154dc14 → 0x01b16080`. [XML-002](SA-AE-XML-002-channel-node-schema.en.md) adds the conditional tag insertion and alert selector call. Complete lower callee behavior remains unaudited.

No store directly updates the input `x22` in this node body, but downstream side effects cannot be excluded. This check establishes name/type/format selection, the ABI returning an XML root, two child groups, and the additional-processing frontier.

### Mode 9 — `0x017afd88`

The stub `0x017afeb0 → 0x01b215e0` uses selector slot `0x0254a130`. The complete string resolved in the machine report is **`createFileChecksForTrack:inSong:inSeqID:`** at `0x01edba48`. The decompiled pointer label stops at `…inSong:` and must not be used as the full selector. Actual arguments are `x2=return from 0x001a1dcc`, `x3=song`, and `x4=selected container pointer` (`0x017afe9c–0x017afeac`). The words Track and SeqID do not establish those arguments' representation types.

It reads NSData from the alias-resolved path and calls `propertyListWithData:options:format:error:` with options `2`. When a dictionary exists, a non-null collection stores `allObjects` under CFString key `0x02406048`; a nil collection removes the existing key. The pointer/data output confirms **`FileChecks`**, length `10`, payload `0x01e28056`. Persistence uses a plist serializer (`0x017b005c`, format `200`, options `0`), followed by NSData `writeToFile:options:error:` (`0x017b0090`, options `1`). Some read/serialize/write errors go to NSLog.

`0x017b0094` saves the write result in `x25`; `0x017aff80` returns it as `x0=x25`. This candidate bool really survives at the helper ABI, but caller `0x0059119c` discards it by branching to the shared zero-status path. File updating is directly supported; collector internals, full plist schema, key contents, and additional song changes remain unknown.

### Mode 10 — `0x017b1e8c` → `0x004b2a08`

After both resolvers, it requires type `0x43` after masking bit `0x8` and object `+0x48` index at most **12 (`0x0c`)**, established by `cmp w8,#0xc` at `0x017b1efc` and `b.hi` at `0x017b1f00`. The earlier `0x12` was a numeric transcription error. It searches a linked entry from `0x002c8a10` / `0x002c90cc` results. If CFileRef `IsFile` is nonzero, it calls `0x017b1f94 → 0x004b2a08(CFileRef,entry)`. Whether this type and entry identify a specific plugin slot remains unknown.

The callee checks extension `.aupreset` (`0x01e0ed4b`) and passes the file and target to `0x004b2adc → 0x004b1234`. A non-null buffer path assigns the target `+0xa8` CFileRef, clears `+0x110` at `0x004b2b38`, and calls `0x004b2be8 → 0x004afaa0(buffer,entry,2,dictionary)`. It tests that result in `w22`; the nonzero branch ORs entry `+0x18` with `0x40000` / `0x20000` (`0x004b2ce8/0x004b2cf0`) and passes CFString `0x0234cce8` to `0x004b0ad4`. The complete pointer/data contents are **`com.apple.logic.pluginsetting_loaded`** (length `36`, payload `0x01d76217`). Punctuation must not be reconstructed from the decompiler's symbol spelling.

The downstream normal branch from `0x004b2d20` returns `0`; the candidate apply-failure branch at `0x004b2d3c` returns `-1`. The no-buffer branch also returns `0`, so these values alone do not establish a success definition. The mode helper and AE caller do not convey this as operation status. Application, notification, and object stores are visible; preset coverage, load completion, and Undo behavior are unknown.

### Mode 11 — `0x017b174c`

It checks non-null song/path, selection field `song+0xd8 != -1`, and CFileRef `IsFile` bit 0. It saves the result of `0x017b17d8 → 0x001a388c(song,0)` in a position local. FileType comparisons use `0x2e4d4944` / `0x6964694d` / `0x4d696469`. When candidate MAMem parser `0x004f3ba8` (`0x017b182c`) returns **0**, the branch calls `0x017b18cc → 0x002a2ee0` with song, buffer, track pointer, position pointer, `w4=1, x5=0, w6=0x3c`, and filename.

Without checking that call's result, it conditionally ORs song `+0xe4` with `3` / `4` (`0x017b1928/0x017b193c`) and `+0x96` with `8` (`0x017b1948`). These stores are confirmed; names such as dirty / Undo / completion bits are not. MIDI import is a strong candidate, but position units, conditions for creating tracks, tempo handling, and parser details remain unverified.

### Mode 12 — `0x017b201c`

It skips processing when selection field `song+0xd8` is `-1`. It constructs a CFileRef for the requested path and a **separate mutable CFileRef** from `NSTemporaryDirectory`. The candidate track local is this selection field minus 1. `0x017b211c → 0x0037b858` receives song, folder `song+0x10`, the track pointer, temporary CFileRef pointer, flags `0x2200` or `0x40002200`, and other arguments. Only a nonzero return calls `0x017b2180 → 0x00354128`, using a string formed by deleting the requested path's extension and appending CFString `0x023469a8`. The pointer/data output confirms **`aac`** (length `3`, payload `0x01d72138`). The operation names render / convert for these two callees remain hypotheses.

After the candidate generation call, even on return 0, it passes `CopyFileSystemPath` of the temporary CFileRef to `removeItemAtPath:error:` (`0x017b21d0`, nil error pointer) and ignores its result. [EXPORT-002](SA-AE-EXPORT-002-temporary-output.en.md) establishes an early zero-return producer path leaving the temporary reference unchanged, **allowing a temp directory path to reach the removal API**. No actual deletion was observed. This concrete boundary excludes mode 12 from live tests and product admission. Output completion, codec, range, overwrite, asynchronous work, and conversion failure cannot be confirmed from the reply.

### Mode 13 — `0x017b22f8`

Selection field `song+0xd8 == -1` returns immediately. It passes type local `0x7049` and the global owner to `0x004f1678`, calls `fenster` on the returned object (`0x017b2340`), and **tail-calls** `0x005e559c` (`0x017b237c`) with song, value at returned window `+0x74`, window pointer, and `1,1,0,0`. This helper contains no visible null-window check.

Only a window/editor-related candidate is supported; the concrete action name is unknown. The caller discards the tail-call result, returns handler status `0`, and writes no `sPer` on this path. A schema requiring text for mode 13 is incorrect.

### Mode 14 — `0x017b19c0`

The resolved record's `+0x20` field must be positive and the second resolver non-null. It builds a CFileRef from path via `0x001ab414` and checks `IsValid` bit 0. It passes filename UTF8String to `0x0022cc34(song,id,name)`, then derives the parent directory's lastPathComponent, applies a string replacement, and writes to a record returned after another resolver and `0x0022cadc`. The pointer/data output confirms replacement of CFString **`/`** at `0x0233a448` (length `1`) with the **empty string** at `0x02338b48` (length `0`).

Confirmed writes/calls are `0x017b1b44: bzero(record+0x62,0x40)`, `0x017b1b54: utf8_strlcpy(...,0x40)`, `0x017b1b5c: utf8_check_and_fix`, and `0x017b1b60: strh wzr,[record,#0xae]`. It then calls `0x0022c914(song,id,&fileRef)` and, with a retained CFURL, `0x002bfdb0(song,url,id,container,object,0)`. Filename, parent-directory name, file reference, and target are connected, but whether it changes a sample, instrument, or region—and what it loads—awaits the small setters.

## Finite next steps and acceptance gates

| Gate | Bounded target | Acceptance condition |
|---|---|---|
| M1: unresolved XML boundaries | Factory stub `0x01af4980`, child `0x0154dcb4`, wrapper stubs `0x01af4b40/0x01af4b80`, conditional `0x01b16080` | [XML-002](SA-AE-XML-002-channel-node-schema.en.md) confirms selectors, factory implementations, child attributes, omission rules, and conditional tag/alert boundaries. Next bound lower virtual calls, empty-slot checks, and target coverage; full schema and reimport compatibility remain unestablished |
| M2: target representation | Callers of the two resolvers and known type references | Diagram `+0xd4/+0xd8`, 0x50 record, container, and object separately; do not infer a public ID, UI track number, or slot mapping |
| M3: mode 10 application | Entry/exit of `0x004b1234` / `0x004afaa0`, named selectors | Establish file → buffer → apply result → rollback/notification dataflow; do not claim all preset types |
| M4: mode 11 import | Entry/exit of `0x004f3ba8` / `0x002a2ee0`, position units | Explain why 0 takes the processing path; establish track/position in/out and failure/change conditions |
| M5: mode 12 deletion path | CFileRef updates in `0x0037b858`, completion/error in `0x00354128` | Trace final temporary path on every zero/nonzero return, generation/conversion synchrony and failure, and removal target; [EXPORT-002](SA-AE-EXPORT-002-temporary-output.en.md) records a directory-path removal request after early failure and destination deletion before conversion; keep it outside execution candidates and trace lower generation/wait boundaries statically |
| M6: modes 13/14 meaning | Argument consumers at `0x005e559c`, small setters `0x0022cc34/0x0022cadc/0x0022c914` | Establish window type/action, target/field/file-reference changes, and state updates; avoid an unbounded engine sweep |
| M7: conditional live verification | `LogicCLI-Test.logicx` and dedicated temporary files within defined experiment scope and session authorization | One changed condition per experiment; multiple values and tracks; before/after differences, failure/overwrite/Undo, independent readback; otherwise `verified:false`. Preserve existing authorization; this report itself grants no new sending/connection authorization. Keep the separate PLAN-05 connection-approval gate |

Operation-catalog admission requires resolved target selection, input schema, side effects, failures, completion, and independent readback for each candidate. The present result establishes static call/store boundaries and that replies do not report operation success.
