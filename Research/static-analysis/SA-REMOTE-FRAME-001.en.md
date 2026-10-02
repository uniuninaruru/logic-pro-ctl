[日本語](SA-REMOTE-FRAME-001.md) | [English](SA-REMOTE-FRAME-001.en.md)

# SA-REMOTE-FRAME-001: The Logic Remote frame — tag, compression, types, order

| Item | Value |
|---|---|
| Date | 2026-10-02 |
| Logic | 12.3.1 (6682), arm64 |
| Binary | `MACore.framework` (arm64 slice SHA-256 `99a4a9ad…`, universal whole file `76ab2a5f…`) |
| Method | **Static only** (targeted Ghidra decompilation, ObjC method-list matching, disassembly). Nothing was sent to Logic and no connection was made |
| Implementation | `Sources/LogicCore/Backends/Remote/RemoteFrame.swift` (decoder only), tests `Tests/LogicCoreTests/RemoteFrameTests.swift` |
| Fixtures | `Tests/Fixtures/logic-remote/` (**synthetic**, not captures. Generator: `Tools/research-scripts/make_remote_fixtures.py`) |
| Machine-readable | `Research/protocol/logic-remote.ksy` (Kaitai, **not compiled**), `Research/protocol/logic-remote.schema.json` |
| Related | [SA-REMOTE-SESSION-001](SA-REMOTE-SESSION-001.en.md) (connection), [SA-002](SA-002-control-surface-assign-model.en.md) §3 (overview), [SA-005](SA-005-logic-remote-state-push.en.md) (state push) |

**Confidence convention:** what matches the decompiled code is "confirmed", inferences are "hypothesis". Not confirmed on the wire.

## 1. Frame structure (confirmed)

```text
frame     = tag (1 byte) + payload
tag       = bit 7: payload is a MAZP container / bits 0-6: format
format    = 1 property list / 4 JSON / anything else = keyed archive (the writer uses 2)
MAZP      = "MAZP"(4) + header length u16 BE (=10) + uncompressed length u32 BE + zlib stream
content   = dictionary { address : argument }  /  array of such dictionaries (an ordered batch)
```

| Part | Evidence |
|---|---|
| Receive: tag, format and inflate branches | `MAPeerRouter::processReceivedData:fromPeer:` (0x000f7ac8) |
| Send: format choice and the compression decision | serializer `FUN_000f98c8` (0x000f98c8) |
| Inflate: reading MAZP | `-[NSData maUncompressedData]` (IMP 0x56698), matched through the method list |
| Deflate: writing MAZP | `-[NSData maCompressedDataWithCompressionLevel:]` (IMP 0x5659c) |
| Generic zlib/gzip inflate | `-[NSData decompressedData]` (IMP 0x56390), `inflateInit2(47)`. A **different** function from MAZP |

## 2. How the sender picks a format (confirmed)

1. Every peer supports JSON (`canUseJSON`, [SESSION §4](SA-REMOTE-SESSION-001.en.md)) and the object is valid JSON → **format 4 (JSON)**.
2. Otherwise, if it is valid as a binary plist (format 200) → **format 1**.
3. Neither (for example a dictionary with number keys) → **format 2 (keyed archive)**, root key `NSKeyedArchiveRootObjectKey`.
4. When the payload (after the tag) is **over 1024 bytes**, compress it into MAZP at level 9.
   Only when the result is **smaller** than the original is the tag's bit 7 set and the payload replaced.

While any peer lacks JSON support, format 4 is not used (so the first messages right after connecting should be plist — hypothesis).

## 3. The receiver's rules (confirmed), and where this parser differs

| Item | Logic | This parser (`RemoteFrameParser`) |
|---|---|---|
| Format 1 / 4 / other | 1 = plist, 4 = JSON, **everything else = keyed archive** | Only 1 / 4 / 2. Others reported distinctly as `unknownFormat(n)` |
| Keyed-archive types | Allowed classes: `NSDictionary`, `NSString`, `NSURL`, `NSNumber`, `NSArray`, `NSIndexPath`, `NSData` | The same 7 classes |
| Bit 7 without a header | Under 10 bytes is dropped. **Anything not starting with "MAZP" is used as is** | Under 10 bytes: `truncatedContainer`. No header: passed through as `flaggedWithoutHeader` |
| Header length | The zlib stream starts at that offset (10 is not assumed) | Under 10 or beyond the data: `badContainerHeader` |
| Uncompressed length | Allocated as declared, **no upper bound** (up to 4 GiB). The real length is **not checked** | Capped at 16 MiB (`declaredSizeTooLarge`). A different real length is `sizeMismatch` |
| zlib checksum | `uncompress` checks it | Adler-32 checked here (`decompressionFailed`) |
| JSON fragments (`"text"`) | Refused (`NSJSONSerialization` default) | Same (`decodeFailed`) |
| plist syntax | Auto-detected, **old-style ASCII plists are read too** | Same. A bare word becomes a string, then `unexpectedTopLevel` |
| Top level | Dictionary → deliver each key. Array → deliver each element dictionary **in order** | Dictionary = one group, array = ordered groups. Anything else: `unexpectedTopLevel` |
| Non-string address | Unverified (may throw at `hasPrefix:` etc.) | `nonStringAddress` |

## 4. Order, number keys, binary arguments

| Question | What was confirmed |
|---|---|
| Order | **The order of array elements is kept** (`FUN_000f94f8` handles them in turn). **Key order inside one dictionary is not defined** (dictionary enumeration order). Arrays are sent only to peers at **protocol version 7 or later**; below 7 the dictionaries are sent one by one (`_sendOrderedMessages…`, 0x000f67f0) |
| Number keys | plist / JSON dictionaries have string keys only. **A dictionary with number keys can only travel as format 2.** The inside of `/gtFaderData` (a dictionary keyed by `NSNumber` instrument IDs, [SA-005 §3](SA-005-logic-remote-state-push.en.md)) is such a case, so **`/gtFaderData` is presumably sent as format 2** (hypothesis, confidence medium, not seen on the wire) |
| Binary arguments | `NSData` travels in a plist (data) and in a keyed archive, not in JSON. The parser keeps it as `.data` |
| Delivery | `useTCP` true = reliable send (`MCSessionSendDataReliable` = 0), false = unreliable (1). A dictionary containing `/mixerLevels`, or any send with `useTCP` false, goes out **one key per data message** |
| On arrival | `/alert` runs on a higher-priority queue, everything else on the main queue. **Low-level messages** (`/disconnectImmediately`, `/jsonSupport`, `/protocolVersion`) are handled before delivery ([SESSION §5](SA-REMOTE-SESSION-001.en.md)) |

## 5. Tests and limits

- Of the 92 tests, 11 cover frames: good cases (plist, JSON, ordered array, an archive with number keys, two compressed forms, no header) and
  bad cases (empty, unknown format, broken JSON/plist/archive, under 10 bytes, bad header, size limit, size mismatch, damaged checksum, too deep).
- Injecting a defect that skips the checksum check, or one that accepts unknown formats, makes the matching test fail.
- **The fixtures are synthetic.** They are built as this document reads the format, so they show "the parser follows this reading"
  but not "Logic really sends this". Real captures (PLAN-05, needs approval) will replace them.
- The difference between Logic's decoder (it just sets the declared length) and this strict parser is the table in §3.

## 6. Unknowns

| Item | Status |
|---|---|
| The default sent for a message without an argument (`NSConstantIntegerNumber`) | Unknown. I tried to read the constant in the binary, misread its layout and could not settle it |
| Whether the receiver of an argument-less `/jsonSupport` reads an argument | Unknown (presumably not needed — hypothesis) |
| Dates (plist `NSDate`) | Not known whether Logic accepts them. The parser says `unsupportedType` |
| Resource sends (`sendResourceAtURL:`, region transfer, …) | A separate path, not part of this frame |
| The MPC per-send size limit, and the largest message Logic accepts | Unverified |
| That `/gtFaderData` is format 2 | Hypothesis (above); to be checked against a capture |
| Correctness of the `.ksy` | Unverified (no compiler installed). The Swift parser is the reference |
