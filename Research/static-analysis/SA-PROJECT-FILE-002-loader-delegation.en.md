# SA-PROJECT-FILE-002: version comparison and loader delegation

[Japanese summary](SA-PROJECT-FILE-002-loader-delegation.md) · [Six facts, critical anchors and limits](../protocol/logicx-loader-delegation-boundaries.tsv) · [Evidence manifest](project-loader-delegation-manifest.json) · [Version classifier and outer wrapper](SA-PROJECT-FILE-001-logicx-loader.en.md)

**The comparator returns numeric thresholds; the data wrapper delegates to the actual document-manager receiver; the URL helper uses the actual resolver-returned path.** These three bodies still do not establish the native `ProjectData` parser, effective runtime dispatch or output-pointer contracts. All facts retain `runtime_verified=false` and `product_capability=false`.

The completed 023 read-only job covers exactly **3 definitions / 364 bytes / 91 instruction words** in Logic 12.3.1/build 6682. A new bounded offline checker matched every exported word against installed Logic and its analysis copy, checked the two selected Objective-C method rows and necessary selector/import bindings, and rejected missing, duplicate and changed-word negatives. All 16 input hashes were unchanged across the check. Manifest records the three contiguous ranges/body hashes and input/raw provenance; the table holds the critical instruction anchors. No frozen 019 checker or utility top-level workflow was rerun, and no additional callee body was read.

## Signed32 comparison: P023-01–02

`DfDocument` owns the class method `checkDocumentVersion:currentRunningVersion:`. The document and current arguments arrive in w2/w3. Signed32 `document<10000` selects the low 32 bits of `document*10000`; otherwise the original document value is selected. Thus this is not a clamp or a check that the input is a valid version. Multiplication and threshold addition wrap 32 bits.

The verified ARM64 operations imply the following arithmetic, where `s32` interprets a low 32-bit result as a signed integer and the arguments are already interpreted as signed32:

```text
n = s32(document * 10000) if document < 10000 else document
if n <= current:                 return 0
if n >= s32(current + 5000):     return 1
if n >= s32(current + 1000):     return 2
return 0
```

The `n>current` guard runs before either threshold, and +5000 is tested first. When current is 55000, there is no threshold overflow:

| Normalized document value | Numeric return |
|---|---:|
| <=55999, including 55001–55999 | 0 |
| 56000–59999 | 2 |
| >=60000 | 1 |

For short inputs, 5 normalizes to 50000 and yields 0; 6 normalizes to 60000 and yields 1 at current 55000. These are instruction-derived arithmetic examples, not native execution. Version encoding, negative-input meaning and the semantic enum for 0/1/2 are unknown. In particular,0 cannot be described as rejecting or accepting a newer version merely because 55001–55999 produce it.

## Actual manager receiver and output contract: P023-03–04

The 116-byte `CLgSongDocument` instance method `setDocumentFileDataFromURL:usedAutoSave:error:` retains the original URL. It sends `unilibDocManager` to the original self, retains the actual returned object, and sends `setDocumentFileDataFromURL:usedAutoSave:error:` to that object. The receiver x0 remains the actual manager return; x2 is the retained original URL, x3 the original `usedAutoSave` pointer, and x4 the original error pointer. The same selector name is therefore not proof of self recursion. Decompiled C hides the manager receiver behind `func_0x01c72660` and suggests a recursive call that the register flow does not support.

The delegate's actual return x0 is saved in x20 across releases of the manager and URL, then restored to x0 for return. This body has no read/write of the two output pointees and no initialization of the `usedAutoSave` byte. Output writes, numeric success meaning and parser behavior depend on the delegate. Its effective runtime class/implementation and the manager getter internals are unread. The outer 019 caller's uninitialized `usedAutoSave` byte remains an unresolved output contract.

## Actual resolver path and nil routes: P023-05–06

The 172-byte `FUN_015ea7b8` preserves original x1 and x2, retains the input URL and obtains its `path`. It sends the getter's actual path in x0 to unread `FUN_015e9a6c`, with original x1 and original x2 restored as the other arguments. There is no nil gate between the path getter and this resolver call: a nil getter path still reaches the resolver.

The resolver's actual return is retained and saved in x20. The original getter path is released; only then does a nil resolver-result gate skip URL construction. For nonnil result, `fileURLWithPath:` receives the bound `NSURL` class as receiver and **x2=x20**, the actual resolver-returned path. The decompiled C appears to reuse the original path because it omits this returned-object assignment. The verified instructions show a different argument.

A nil retained input skips both getter and resolver and takes an explicit nil result route. A nil resolver result also returns nil without calling `fileURLWithPath:`. Otherwise the actual URL-construction result is saved in x22, returned through x0 and tail-branched to the bound `_objc_autoreleaseReturnValue`. The helper does not itself dereference or write original x1. Resolver 015e9a6c is only identified by inventory (1824 bytes); its body was not expanded in 023. Path selection, flag writes, variant meaning, returned runtime types and actual selected URL remain unknown. Native URL creation nil/exception behavior and complete ownership are unverified.

This closes the two decompiler argument/receiver ambiguities in the outer [PROJECT-FILE001](SA-PROJECT-FILE-001-logicx-loader.en.md) narrative, while preserving its boundaries around native parsing and side effects. No actual saved-package acceptance, runtime URL, live state, header/schema, save/reload/Undo or product capability was verified. This publication performed no new Ghidra job, Logic/AppleEvent/GUI action, build or Git operation.
