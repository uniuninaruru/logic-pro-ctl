[日本語](SA-REMOTE-TRACKTYPE-001.md) | [English](SA-REMOTE-TRACKTYPE-001.en.md)

# SA-REMOTE-TRACKTYPE-001 — `t` (track kind) and `c` (the colour bytes) of `/ati`

| Item | Value |
|---|---|
| Status | **Static analysis only. Not confirmed on a Logic Remote connection** (PLAN-05 is not approved; nothing was connected) |
| Date | 2026-10-05 |
| Subject | Logic 12.3.1 (6682), the arm64 `Logic.arm64` (SHA-256 `2f141e1a…0998`) |
| Evidence | Machine-code excerpts (`Research/raw/ghidra/q-p6-ati-006-machinecode.txt`, `q-p6-ati-colour-006-machinecode.txt`, `q-p6-colourmap-006-machinecode.txt`; not tracked by Git) and an [anchor table](../protocol/logic-remote-trackcolor-anchors.tsv) (269 rows) that checks instructions and constants against the image file |
| Machine-readable tables | [`logic-remote-track-types.tsv`](../protocol/logic-remote-track-types.tsv) · [`logic-remote-colour-bytes.tsv`](../protocol/logic-remote-colour-bytes.tsv) |
| Prerequisite | [SA-REMOTE-STATE-001](SA-REMOTE-STATE-001.en.md) §4 (the 13 columns of `/ati`) |

## 1. Conclusions

| Item | Conclusion | Kind | Confidence |
|---|---|---|---|
| Byte order of `c` | **R, G, B, A.** Each component is the low byte of `trunc(x × 255.0)` | Static fact (instructions; §5) | High |
| Which colour goes with which key | The four `NSData` go to `nc`, `sc`, `tnc`, `tsc` in that order | Static fact (stack layout and selector checked) | High |
| How `t` is decided | Eight rules are tried in order and the first that applies gives the value. Values are 0 to 10 (§2) | Static fact | High |
| `t = 5` | The ginst object's kind word is `0x44`. Logic itself names a single selected strip of this kind "Master Track" | Fact (the name is used) + hypothesis "the Master strip" | High |
| `t = 9` | Kind word `0x42`. `ginstNeedsMidiClipType:` is true for this kind | Hypothesis "a MIDI-driven strip (software instrument)" | Medium |
| The other values of `t` (1, 2, 3, 4, 6, 7, 8, 10) | The conditions are read, but the Logic track kinds they correspond to are not settled | Hypothesis (confidence in the table) / unresolved | Low to medium |
| `/sti`'s `t` | **The result of the same function, merged over the selected strips.** Values 0 to 4 | Static fact. The earlier wording (a different computation) was a **misreading** (§6) | High |
| `nc` and `p` of the same call | Both are read from *G*. The table for `nc` (1, 2, 4, 4, 6, 7, 8, …, 16) and the one for `p` were read out (§9) | Static fact (machine code). The earlier "a song value" was a misreading | High |
| Values on a real connection | **Unconfirmed** | — | — |

## 2. `t` — how it is decided

The inputs of `trackTypeForTrack:seqID:ginst:inSong:` (`0x01693e90`) are a track entry *E* (0x50 bytes: kind at +0x10, depth +0x12, flags +0x14, id +0x20), `seqID`, `ginst` and the song.

**The ginst object *G*.** The function first calls `FUN_01a15c7c(song, ginst, NULL)` (`0x01693ebc`). It returns *G* only when the strip that `ginst` selects has type byte (+0x69) **0x11** and class byte (+0x335) below 13; it looks *G* up in a table on the song. Otherwise it returns NULL. The "kind word" is the leading `ushort` of *G* with bit 3 cleared (`and #0xfffffff7`). The name `ginst` is Logic's own term (the same root as `gindex`; **guess**: generic instrument).

**What `/ati` passes.** *E* is the track entry; `seqID` is the strip's `folder` (the upper 16 bits of `BgTrackInfoTrackIDKey`); `ginst` is **the value of the same register** as `n.gindex` (the same as the keys of `g` in `/gtFaderData`; anchors `TT-callsite`, `CB-gindex`); `song` is the song. The `/sti` block passes no *E* and gives the selected strip's index as `ginst` (§3).

**The sequence *Q*.** A `seqID` of 0x7ffffff8 or 0x7ffffffc selects an element of another array (+0x318); any other value is an ordinary ID, a multiple of 4, that indexes the array at +0x228. A set bit 0 at *Q*+0x30 marks it invalid. If no *E* is passed, the function looks in *Q* for the entry whose id (+0x20) equals `ginst`.

**Rules.** They are tried from the top; the first that applies is returned.

| Rule | Condition | Value |
|---|---|---|
| R1 | *E* and *Q* are known and `FUN_019fa680(E, Q)` is true. It is true when *E*'s kind is not 3, 4, 5 or 0xc and the first entry after *E* whose kind is neither 5 nor 0xc is exactly one level deeper than *E* | **7** if bit 6 (0x40) of *E*+0x14 is set, **8** if not. Also 8 when the internal checks disagree |
| R2 | *G* exists and the kind word is `0x44` | **5** |
| R3 | *G* exists and the kind word is `0x46` | **10** if the signed `short` *G*[+2] is positive, otherwise **6** |
| R4 | *E* is known and its kind is 4 (a kind-0xc entry takes the kind of the nearest preceding entry that is neither 0xc nor 5); or *E* is of kind 3, has a deeper next entry, and its parent entry is of kind 4 | **3** |
| R5 | *G* exists; kind word `0x40` gives **1**, `0x43` gives **2** | 1 / 2 |
| R6 | *E* is known and the type byte of the strip that *E*'s id (+0x20) selects is below 0x13 and not 0x11 | **4** |
| R7 | *G* exists and the kind word is `0x42` | **9** |
| R8 | none of the above | **0** |

When *E* is unknown (and not found in *Q* either), R4 and R6 are skipped. The result is sign-extended as a `char`. The instructions behind each rule are the `TT-*`, `GI-*` and `PT-*` rows of the anchor table.

**Side effect (statically confirmed).** When the next entry is two or more levels deeper, the function rewrites *E*'s depth (+0x12) to that entry's depth (`0x01694040`, `0x019fa708`). A call that should only read tidies Logic's internal table. It can happen each time `/ati` is built. The effect is unconfirmed.

### 2.1 Clues to the meaning (hypotheses)

| Clue | What it tells |
|---|---|
| `updateSelectedTrackInfo` (`0x0168e754`) uses `cf_MasterTrack` (`0x02338f08`; the real text is "Master Track") as the name when a single strip is selected and *G*'s kind word is `0x44` | Kind word `0x44` is Master; `t = 5` is this kind |
| `ginstNeedsMidiClipType:` is true for kind word `0x42`; `pluginsForTrack:isMIDI:` also looks at `0x42` | `0x42` is a MIDI-driven kind: `t = 9` |
| `importChannelStripWithGInstID:` treats `0x44` and `0x46` together with `(kind \| 2) == 0x46` | `0x46` is close to `0x44` (output side; **hypothesis**, confidence low to medium) |
| `createBusWithDestinationInstrument:…` looks at kind word `0x45` | `0x45` is a bus. It does not appear in the rules for `/ati`'s `t`; after R4 it goes on to R6 or R8 |
| In the default colours per kind (§4) only key 3 has its own number (76) | `t = 3` is treated differently (folder-like hypothesis; confidence low to medium) |

The make-up of the dedicated project (checked on Logic's screen) is 3 software-instrument tracks (Piano, Bass, Synth), 7 audio tracks (Audio, Trk05 to Trk10), the output (St Out) and Master. The predictions in §7 rest on it.

## 3. `/sti`'s `t`

The block `FUN_01696598` (`0x01696598`) calls `trackTypeForTrack` (with a NULL *E*) for each selected strip. It folds the result into one shared byte only when the result is **1 to 4**:

- if the byte is 0, it stores the result;
- if the byte already equals the result, nothing changes;
- if the byte differs from the result, it becomes **2** (a mix);
- a result of 0 or 5 and above leaves the byte alone.

With no selection, or no result in 1 to 4, the value is 0 (the `t` sent when nothing is selected is the constant `0x0242fcd0` = 0; its pairing with the key comes from the decompiler's stack-variable order and is not confirmed in machine code; anchors `ST-none-*`). So `/sti`'s `t` is 0 to 4, and **a strip whose result is 5 or more (software instrument 9, Master 5, output 6/10, parent tracks 7/8) is not counted; selecting only such strips leaves 0**. Selected together with strips of 1 to 4, only those strips count (static fact; anchor `ST-block`).

## 4. Default colour per kind

`createColorDataDictionary` (`0x00a69960`), which builds `/colorIndexMap`, puts in `defaultColorIndexForTrackTypes` a dictionary of five pairs:

| key (a value of `t`) | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| default colour number | 9 | 16 | 9 | 76 | 9 |

The keys are only 0 to 4, the same range as `/sti`'s `t`. The key/value pairing was checked from the stack layout in the machine code and the argument order of `dictionaryWithObjects:forKeys:count:` (`x2` = objects, `x3` = keys; anchors `DC-*`, `SEL-dictionaryWithObjects`). **What colour a number means is unresolved.**

## 5. `c` — the order of the 4 bytes

A strip's colour number is the signed byte at strip+0x85 (`0x01697120`).

| Key | How it is made | The 4 bytes |
|---|---|---|
| `nc` (Normal) | `FUN_00d34de8` turns the colour number into (a hue, two bytes); `FUN_017e5998` (HSV to RGB) is called with **alpha 1.0** | R, G, B, A |
| `sc` (Selected) | `FUN_00d35578(number, 40, 100)`: the hue of the number, saturation 0.40, brightness 1.00; it puts R, G, B, 1.0 into the static at `0x026c6de0` | R, G, B, A |
| `tnc` (IconTintNormal) | `FUN_00d358a0(number, 4)` makes an `NSColor`; `FUN_006d874c` reads it with `getRed:green:blue:alpha:` | R, G, B, A |
| `tsc` (IconTintSelected) | `FUN_00d358a0(number, 2)`, the rest as for `tnc` | R, G, B, A |

All four are packed the same way (`0x01697144` to `0x0169716c` and the like). Each of the four doubles is multiplied by 255.0, converted by `fcvtzs` (**truncation toward zero**: 0.999 gives 254), the low byte of each is taken by `uzp1`, `xtn`, `uzp1`, and `str s0` writes the 4 bytes. The order is the order of the doubles: R, G, B, A.

- `FUN_017e5998` returns R, G, B in `d0` to `d2` and passes **the input alpha through in `d3`**. The alpha of the first colour is 1.0, so the fourth byte is 0xFF.
- Colour numbers −1 and 0 are palette entry 9 in `FUN_00d34de8` (`0x00d34e58`). For `tnc` and `tsc`, `FUN_00d358a0` uses a constant for them (hue 212, bytes 55 and 100, alpha 1.0).
- **A computed value (not a captured one):** running that constant through `FUN_017e5998` with the correction tables in the image (`0x01d434f8`, `0x01d44038`) gives **`8c c0 ff ff`** (R 140, G 192, B 255, A 255). It should match `tnc` and `tsc` of a strip whose colour number is −1 or 0 ([`remote_colour_model.py`](../../Tools/research-scripts/remote_colour_model.py)).
- `nc` and `sc` for a colour number of 1 or more use a palette that `FUN_00d34de8` builds at run time from configuration values, so **their values cannot be derived statically**. `tnc` and `tsc` for numbers of 1 or more come from `tintColorWithHue:withModifier:mode:` of `MASharedInstrumentIconService`, which is not analysed.

## 6. Statements corrected

| Earlier statement | Correction | Why |
|---|---|---|
| SA-REMOTE-STATE-001 §4: "the byte order of the 4 bytes of `c` is not confirmed (one colour starts with 0xFF)" | The order is R, G, B, A. The 0xFF is the **fourth** byte (alpha), not the first | The decompiler lost the return values (`d0` to `d3`) of `FUN_017e5998` and showed the input constant 1.0 as the first component. The machine code takes the four values with `mov v0.d[1], v1.d[0]` and the like |
| Same, §5 (`/sti`): "`t` is the byte at +3 of the selected track's internal record, a different computation from `/ati`'s `t`" | It is the result of `trackTypeForTrack` merged by the rule in §3 | The "+3" (an index on `undefined8*`) was a shared byte the block captures (`byref + 0x18`). Reading the block's body in machine code showed it |
| Ghidra's listing: `fmov d1,-0x4010000000000000` | The value is **−1.0** | `llvm-objdump` prints `fmov d1, #-1.00000000`. Ghidra's form is easy to misread. The correction is `2.0 − table1[hue]` (anchor `CB-hsv-in`) |

## 7. What to check on a real connection (if PLAN-05's E2 is approved)

Predictions for the 12 strips of the dedicated project (Piano, Audio, Bass, Synth, Trk05 to Trk10, St Out, Master). If one is wrong, record it as it is and fix the documents; do not rewrite them to fit.

| # | Prediction | Basis · confidence |
|---|---|---|
| P12a | Master's `t` is **5** | R2. Confidence: high |
| P12b | `t` of Piano, Bass and Synth is **9** | R7 (kind word 0x42). Confidence: medium |
| P12c | `t` of Audio and Trk05 to Trk10 is **1** (kind word 0x40); if not, 4 | Confidence: low |
| P12d | `t` of St Out is **6 or 10** | R3. Confidence: low |
| P12e | With only a software instrument (result 9) selected, `/sti`'s `t` is 0 | §3. Confidence: high (settled statically) |
| P13a | Each `c` colour is 4 bytes and the fourth is almost always `0xff` | §5. Confidence: high |
| P13b | `tnc` and `tsc` of a track with colour number 0 are `8cc0ffff` (check the number separately in `/colorIndexMap`) | Computed. Confidence: medium (whether the number is 0 is confirmed by receiving) |

## 8. How to reproduce the check

```sh
python3 Tools/research-scripts/binary_anchors.py check Research/protocol/logic-remote-trackcolor-anchors.tsv
python3 -m unittest test_binary_anchors   # run in Tools/research-scripts
```

Each row of the anchor table is checked against the image file's bytes, `llvm-objdump`'s instruction, `dyld_info -fixups`'s symbol or the selector string (Ghidra is not used). A different image hash is refused.

## 9. `nc` and `p` of the same call (addendum)

The `nc` and `p` columns that the `/ati` block makes are also read from *G* (the return value of `FUN_01a15c7c`, saved on the stack at `sp+0x80`; anchor `NC-src`).

| Column | Value | Condition |
|---|---|---|
| `nc` | the *n*-th entry of the table at `0x01d59030` (*n* = *G*[+0xd4], 1 to 15): 1, 2, 4, 4, 6, 7, 8, 8, 8, 8, 10, 10, 12, 14, 16 | *G* exists and *n* is 1 to 15 |
| `nc` | 0 | no *G*, or *n* is 0 or above 15 (the constant `0x0242fcb8` = 0) |
| `p` | `0`, `-5`, `-1`, `-4`, `-1`, `-4` for *k* = 0 to 5 | *G* exists, bit 27 of `allowedElementsForStrip:` is set, and the result *k* of `FUN_01a2cc68(G, 0)` is below 6 (byte *k* of the 64-bit constant `0xfcfffcfffb00`) |
| `p` | `-1` | *G* exists but the condition above fails; or no *G* and `t` is not 4 (the constant `0x0242fce8` = −1) |
| `p` | `0` | no *G* and `t` is 4 (the constant `0x0242fcd0` = 0) |

**Correction of an earlier reading:** SA-REMOTE-STATE-001 gave `nc` as "a byte at +0xd4 of the song". The decompiler showed the return value of `FUN_01a15c7c` as discarded and used one variable name for both the song and *G*, which caused the misreading; in machine code the value saved by `str x0,[sp,#0x80]` (*G*) is read later. The shape of the values (1, 2, 4, 4, 6, 7, 8, …, 16) looks like the channel counts of surround formats (**hypothesis**, confidence medium). The meaning of *k*, the result of `FUN_01a2cc68`, is unresolved.

## 10. Unresolved

| Item | State | Next |
|---|---|---|
| Kind words `0x40`, `0x43`, `0x46` and `t` = 1, 2, 6, 10 | Hypothesis (low) | Receive in E2 and line up with the dedicated project's strip kinds |
| `t` = 3, 4, 7, 8 (folder, stack, others) | Hypothesis (low) | A reception with a folder and a stack added to the project (E3 or later; needs separate approval) |
| Where the palette table of `FUN_00d34de8` comes from (configuration reads) | Not analysed | Read the initialisation (`0x00d34ea8` onward) |
| Colours from `MASharedInstrumentIconService` | Not analysed | Analyse another binary |
| How the Remote app interprets `t` and `c` | Not examined (the app is out of scope) | Not needed: this product reads what Logic sends |
