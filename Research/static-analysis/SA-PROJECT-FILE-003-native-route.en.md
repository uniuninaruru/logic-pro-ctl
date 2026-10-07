# SA-PROJECT-FILE-003: native input gates and project path selection

[Japanese summary](SA-PROJECT-FILE-003-native-route.md) · [Facts and anchors](../protocol/logicx-native-route-boundaries.tsv) · [Evidence manifest](project-native-route-manifest.json) · [Outer delegation](SA-PROJECT-FILE-002-loader-delegation.en.md)

**The native reader compares four header values and delegates decoding; the path resolver can select regular or low-memory autosave data through a modal branch.** These are static input/control-flow findings. They do not establish the complete file schema, effective runtime receiver, successful loading or a product CLI capability.

The completed, locked, read-only 024 export contains **3 definitions / 4388 bytes / 1097 instruction words** in Logic 12.3.1/build 6682. All exported words matched the installed binary and analysis copy. Later bounded metadata/anchor checks reused that immutable proof; they did not repeat the 019/023 workflows, start another Ghidra job or invoke native code. The manifest preserves explicit body ranges, hashes and provenance.

## Reader implementations and output pointers: P024-N01

Both selected Objective-C rows have the selector `setDocumentFileDataFromURL:usedAutoSave:error:` and types `B40@0:8@16^B24^@32`. The 8-byte `CLgUnilibDocManager` body returns 1 without writing either output pointee. The 2556-byte `CLgDocManager` body saves the original output pointers, clears a nonnil `usedAutoSave` byte at `00bcbfd4`, and clears a nonnil error object at `00bcbfe0`. Later branches can write a flow flag at `00bcc794` or an error object at `00bcc7d4`.

Thus the outer wrapper's uninitialized output byte is not initialized by every implementation. The actual `unilibDocManager` receiver and selected runtime implementation remain unknown. The two method bodies alone do not prove a live uninitialized read, successful loading or the semantic meaning of every flag value.

## Four header values and conversion gate: P024-N02–03

The concrete reader calls `NSData.dataWithContentsOfURL:options:error:` with the original URL, options=2 and the original error pointer. A length comparison with 4 gates the first little-endian 32-bit read at `00bcc040`. Recognized comparisons lead to one handling branch, then to the converter branch:

| LE32 constant | Original four bytes |
|---|---|
| `0xabc04713` | `13 47 c0 ab` |
| `0xabc04723` | `23 47 c0 ab` |
| `0x2347c0ab` | `ab c0 47 23` |
| `0x1347c0ab` | `ab c0 47 13` |

The separately saved test package's `Alternatives/000/ProjectData` starts `23 47 c0 ab`. Its 641814-byte file retained SHA-256 `99e722bad78269d74c2e249a3af8f8570eac8e51de341ac87c2807482babd39a` across snapshots 022/024. This matches a static comparison value; it is not a native accepted-file experiment and does not describe unsaved state.

At `00bcc250`, the actual bytes and length, a zero-initialized converted-data local and original error pointer reach `convertLegacyLogicSongDataIfNeededFromInBytes:inSize:outConvertedData:outError:`. A zero w28 result continues with the original data. A nonzero result requires a nonnil converted object; otherwise it takes a failure route. A nonnil converted result replaces x20, the selected data, and clears the flow flag. The converter body and broader return contract are unread.

## Deeper field and payload route: P024-N04–05

At `00bcc2a0`, the selected data's bytes+6 supplies an unaligned 64-bit value. That value is compared with `0x09be0d7ddcea4ef4`. The equal branch calls `getBytes:range:` with x3=22 and x4=0, then calls unread `013517d0` with bytes+22 and length−22. The local SDK declares `NSRange` as location followed by length. Under that standard layout, the register pair describes location 22 and length 0; it does **not** support a claim that this call copies a 22-byte header.

The original saved file's bytes+6 gives `0x0001000000040003`, which differs from that constant. This observation concerns the original file bytes: conversion may choose different data before the comparison. Neither value is identified here as a version, ID, length or schema marker. The initial four-byte guard does not establish a complete minimum-length contract for the later reads; malformed-input behavior is unverified.

The reader also reaches unread `01584ae8`, replaces internal object state, and can populate errors. Native helper decoding, other import/feature/error routes, ownership and exception behavior remain outside this bounded semantic report. The reader is not established as a pure header probe.

## Project path resolver: P024-PATH-01–08

The 1824-byte `015e9a6c` keeps the retained input path and original variant argument. It clears the original flag byte unconditionally, with no null-pointer guard. The initial `fileExistsAtPath:isDirectory:` result must be nonzero and the directory byte exactly 1; otherwise it returns nil with flag=0. This flag is distinct from the reader's `usedAutoSave` output.

For lowercased `logicx` or `band`, a negative signed64 variant argument calls unread `015ea320` with the actual input path. A negative signed32 helper result returns nil; a nonnegative result is zero-extended for the variant index. `grid` uses index 0. The verified selector `pathForVariant:baseURL:acceptMissing:` receives the actual ProjectInformation receiver, index, constructed URL and w4=0. Its actual returned base supplies the regular `ProjectData` path. Other extensions use imported directory/file-name variables whose loaded values remain unknown.

The same actual base supplies a separate `documentData_lowmem` candidate. Its existence check does not inspect the output directory byte. If it exists, the body creates an actual NSAlert object, sets message/buttons/informative text and calls `runModal`. Verified source button titles occur in order: autosaved data, cancel, regular data. The informative format receives the retained actual basename as a variadic argument; decompiled C omits that value and several returned-object receivers. No private basename is published.

The actual numeric modal result chooses the candidate:

| Numeric result | Static chosen candidate |
|---|---|
| 1001 (`0x3e9`) | nil |
| 1002 (`0x3ea`) | regular data |
| Every other result | low-memory data |

These are numeric branches, not a verified native button/enum contract. Only a nil chosen candidate writes flag=1. A nonnil candidate must pass the final existence check with a directory byte of 0; missing final files or final directories return nil with flag still 0. The chosen retained path is the actual helper return used by the outer URL wrapper.

The modal block also changes static counters/globals and copies a buffer around unread state helpers. Their meaning and complete restoration remain unknown. This path helper is not established as a pure path lookup. Imported component values, variant selection internals, native failures, complete ownership, effective dispatch, actual dialog display/choice, actual URL, successful parser acceptance, save/reload and Undo remain unverified. Every published fact retains `runtime_verified=false` and `product_capability=false`.
