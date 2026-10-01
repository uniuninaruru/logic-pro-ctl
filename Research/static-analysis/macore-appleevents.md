# MACore x86_64 AppleEvent reconnaissance

## Result

The inspected MACore x86_64 slice contains AppleScript execution helpers, but
these searches found no `aUeV`, `Spt2`, `sPmo`, or `sPkc` byte sequence or complete
integer immediate. Its positive AppleEvent references resolve to an
`NSAppleScript(iPhotoAdditions)` category that constructs `ascr/psbr` events and
executes them in an AppleScript object. This is not evidence that MACore
registers a private Logic AppleEvent handler.

This MACore-only analysis does not establish the meanings of `sPmo = 6` and
`sPkc = -3`. The separate Logic.framework bridge is traced in
[`appleevent-command-dispatch.md`](appleevent-command-dispatch.md).

## Identity and reproduction

| Field | Recorded value |
|---|---|
| Date | 2026-10-01 |
| Application metadata | `CFBundleShortVersionString = 12.3.1`, `CFBundleVersion = 6682`, read from the installed application's `Contents/Info.plist` |
| Source | `/Applications/Logic Pro Creator Studio.app/Contents/Frameworks/MACore.framework/Versions/A/MACore` |
| Source architectures | `x86_64 arm64`, verified with `file` and `lipo -info` |
| Source SHA-256 | `76ab2a5f50b3ef120786369b5bf8b53dfc87a3b4107438e0894ab5f9b8095c52` |
| Extracted slice | `Research/raw/20261001-083956-macore/MACore.x86_64` |
| Slice architecture | `x86_64`, verified with `file` and `lipo -info` |
| Slice SHA-256 | `ed6674bc1e19bc64b53a23bd8a53d097248e3664db16b184342f3897f10edb05` |
| Reproduction tool | `Tools/research-scripts/macore_x86_appleevents.py` |
| Raw record | `Research/raw/20261001-083956-macore/manifest.json` and complete tool outputs in that directory; directory timestamps are UTC |

Run from the repository root, with the currently discovered app path:

```sh
python3 Tools/research-scripts/macore_x86_appleevents.py \
  --app '/Applications/Logic Pro Creator Studio.app'
```

The script uses `lipo -thin x86_64 -output <raw directory>/MACore.x86_64`, then
records `file`, `lipo -info`, `otool -tvV`, `otool -l`, `otool -ov`, `nm -m`, and
`strings -a`. The application bundle is only read. No event is sent, no process
is attached, and no product source is modified. Three runs during script
development produced the same slice hash and zero FourCC search counts; the
final run additionally records decoded selector references.

## Observations: four target constants

Source: extracted slice bytes, `manifest.json`, and `disassembly.txt`.

| FourCC | Integer | Big-endian bytes | Little-endian bytes | Raw hits in either order | Complete integer/text hits in `otool -tvV` |
|---|---|---|---|---:|---:|
| `aUeV` | `0x61556556` | `61 55 65 56` | `56 65 55 61` | 0 | 0 |
| `Spt2` | `0x53707432` | `53 70 74 32` | `32 74 70 53` | 0 | 0 |
| `sPmo` | `0x73506d6f` | `73 50 6d 6f` | `6f 6d 50 73` | 0 | 0 |
| `sPkc` | `0x73506b63` | `73 50 6b 63` | `63 6b 50 73` | 0 | 0 |

The disassembly search includes full hexadecimal values, unsigned decimal
values, and literal FourCC text. It does not reconstruct arbitrary computed
values or split immediates.

## Observations: AppleEvent APIs and selectors

Source: `symbols.txt`, `strings.txt`, `objc-metadata.txt`, `disassembly.txt`, and
the decoded selref records in `manifest.json`.

The only imported symbol matching the requested AppleEvent terms is
`_OBJC_CLASS_$_NSAppleEventDescriptor` from Foundation. The adjacent symbol
listing also imports `_OBJC_CLASS_$_NSAppleScript`.

No matches were found for these names in the saved symbol/string/metadata
outputs:

- `NSAppleEventManager`
- `setEventHandler:andSelector:forEventClass:andEventID:`
- `AEInstallEventHandler`, `AERemoveEventHandler`
- `AEGetParamPtr`, `AEGetParamDesc`, `AEGetAttributePtr`
- `AESend`, `AESendMessage`

There are 13 disassembly lines referencing the imported descriptor class,
plus these selector strings:

- `executeAppleEvent:error:`
- `initWithEventClass:eventID:targetDescriptor:returnID:transactionID:`
- `setParamDescriptor:forKeyword:`
- `executeHandlerWithName:andArguments:error:`
- `executeHandlerWithName:inScriptAtURL:withArguments:error:`

### Positive reference traced to AppleScript invocation

`otool -ov` records category `iPhotoAdditions`, class
`_OBJC_CLASS_$_NSAppleScript`, at category VM address `0x1b8e50`. It records:

| Method | Implementation VM address | Evidence |
|---|---:|---|
| `-[NSAppleScript(iPhotoAdditions) executeHandlerWithName:andArguments:error:]` | `0x11e450` | instance method name points indirectly through selref `0x1beec0`, whose decoded target is `0x1746f8` |
| `+[NSAppleScript(iPhotoAdditions) _createScriptAtPath:errorInfo:]` | `0x11e680` | class method name points through selref `0x1bd510`, decoded target `0x170369` |
| `+[NSAppleScript(iPhotoAdditions) executeHandlerWithName:inScriptAtURL:withArguments:error:]` | `0x11e7a0` | class method name points through selref `0x1beec8`, decoded target `0x174723` |

The first method provides concrete event-construction evidence:

| Instruction address | Observed operation |
|---:|---|
| `0x11e4b8` | loads selector `initWithEventClass:eventID:targetDescriptor:returnID:transactionID:` through selref `0x1bd4f0` |
| `0x11e4c9` | `%edx = 0x61736372`, ASCII `ascr`, the first method argument after receiver and selector |
| `0x11e4ce` | `%ecx = 0x70736272`, ASCII `psbr`, the next method argument |
| `0x11e4dc` | invokes the constructor |
| `0x11e560` | loads `setParamDescriptor:forKeyword:` through selref `0x1bd500`, holds it in `%r14` |
| `0x11e570` | parameter keyword `%ecx = 0x736e616d`, ASCII `snam` |
| `0x11e575` | invokes that setter |
| `0x11e5b4` | parameter keyword `%ecx = 0x2d2d2d2d`, ASCII `----` |
| `0x11e5b9` | invokes the same setter with converted arguments |
| `0x11e5d0` | loads `executeAppleEvent:error:` through selref `0x1bd508` |
| `0x11e5e2` | invokes it on the saved method receiver with the constructed event and error pointer |

The class helper at `0x11e7a0` repeats the `ascr/psbr` constructor immediates at
`0x11e868` / `0x11e86d`, and invokes `executeAppleEvent:error:` at `0x11e99b`.
The receiver is an AppleScript object loaded by the helper. These method names,
event construction, and call receivers support classification as script-handler
invocation; they do not establish incoming Logic event registration.

### Disassembler annotation caveat

On this installation `otool -tvV` emits misleading Objective-C comments, for
example labeling the invocation at `0x11e5e2` as `setCrcDefined:`. Its selector
load at `0x11e5d0` references address `0x1bd508` containing encoded pointer
`0x100000001746c8`. The image's `LC_DYLD_CHAINED_FIXUPS` declares pointer format
6 (`DYLD_CHAINED_PTR_64_OFFSET`) for `__DATA_CONST` and `__DATA`. Decoding the
rebase target yields `0x1746c8`, whose string is `executeAppleEvent:error:`.

The research script independently parses load commands, locates
`__objc_selrefs`, decodes supported chained rebase pointers, and resolves
RIP-relative selector loads. This is why the method classification above does
not rely on `otool`'s message comments. Six matching loads are recorded in the
final manifest.

## Observations: command and message names

Source: `symbols.txt`; the script records all 161 case-insensitive
`command|dispatch|befehl` matching symbol lines.

Examples of usable local symbols in this slice:

| Symbol | VM address |
|---|---:|
| `-[MAMessageDispatcher initWithLabel:]` | `0x91d00` |
| `-[MAMessageDispatcher addHandlerForMessagesOfKind:block:]` | `0x91d90` |
| `-[MAMessageDispatcher addHandlerForMessagesOfKind:songID:block:]` | `0x91db0` |
| `-[MAMessageDispatcher dispatchMessage:]` | `0x91f20` |
| `+[MAMessageDispatcher sharedDispatcher]` | `0x92440` |
| `-[MAAssetManager handleSpecialCommand:withAttribute:forAssetSet:withContext:]` | `0xbf0b0` |

The symbol inventory also includes Swift `ObjcCommandImpl`,
`ObjcConditionalCommandImpl`, `NullObjcConditionalCommand`, and `Dispatchable`
symbols. These names alone establish neither AppleEvent registration nor
transport command meanings. No `befehl`-named symbol was found in this MACore
slice. See the existing `SA-004-command-and-engine-boundaries.md` for separately
traced Logic.framework command-dispatch evidence; addresses there are from a
different image and architecture.

## Limits and next discriminator

This is a negative result for direct representations and named API references
in one x86_64 framework slice. It is not proof that Logic lacks the interface.
Indirect selector construction, computed constants, other loaded frameworks,
standard Cocoa scripting fallback, and code present only in an arm64 image
remain possible. The running Apple Silicon app loads arm64 code; the x86_64
slice is an analysis aid and does not by itself establish live behavior.

Hypothesis: the observed MACore AppleEvent references are utility code for
AppleScript invocation rather than the source of `aUeV/Spt2` handling.
Confidence: high for the traced category methods; unestablished for all other
possible MACore execution paths.

Next discriminator: compare valid and invalid event-class/event-ID pairs with
the same parameters and document state, and trace registration/dispatch in the
arm64 application frameworks. A shared `-38` response across unrelated event
pairs would weaken the hypothesis that the original pair reached a dedicated
private handler. This document records no dynamic event experiment.
