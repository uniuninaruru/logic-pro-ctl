# SA-AE-FILE-001: AppleEvent file and region branch

[日本語](SA-AE-FILE-001-file-region.md) · [English](SA-AE-FILE-001-file-region.en.md)

| Item | Details |
|---|---|
| Date | 2026-10-02 |
| Target | Logic Pro Creator Studio 12.3.1 / build 6682, `Logic.framework` ARM64 |
| Baseline SHA-256 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| External entry | `aUeV/Spt2` → `FUN_00590e30` → `FUN_00591de0` |
| Method | Static inspection of read-only/noanalysis output from the existing Ghidra program. No events, connections, or live operations against Logic |
| Local evidence | `Research/raw/ghidra/q-appleevent-file-region-001.c`, `q-appleevent-file-units-001.c`, `q-appleevent-object-resolvers-001.c`, `q-appleevent-modes-001-machinecode.txt`, `q-appleevent-modes-callees-001-machinecode.txt` |
| Types | Inferred C prototypes are not adopted as specifications. “Confirmed” below means static confirmation from addressed ARM64 instructions and API references. Runtime behavior and semantic units require separate validation |

Addresses are image addresses before the slide in this build. See the [existing registration analysis](appleevent-registration.en.md) for registration and currentSong preconditions. This branch is not yet ready to expose as a general region editing or read-only API.

## 1. Entry and type checks

The caller routes modes 4, 6, and 7–14 to separate handlers, and sends other modes to `sPfi` parsing. Comparisons are at `0x00590ef8..0x00590f6c`, `0x005911c0..0x005911cc`, and `0x00591300..0x00591398`. File input branches are at `0x005913c0..0x00591458`.

| Field | Exact descriptor type | Default/storage | Machine-confirmed path |
|---|---|---|---|
| `sPfi` | `bmrk` / `furl` / `fsrf` | `CFileRef` at `0x02633cf0` | Type comparisons `0x005913e0..0x00591410`; `furl` to CFileRef `0x00591598..0x005915f4`; bookmark resolution `0x005915fc..0x00591690`; FSRef assignment `0x00591414..0x00591454` |
| `sPve` | Optional `long` | 1, low 16 bits at `0x02633ce0` | `0x00591698..0x005916fc`; `strh` stores the input's low 16 bits |
| `sPtn` | Optional `long` | 1, u32 at `0x02633d5c` | `0x00591704..0x00591764` |
| `sPss` | Optional `long` | 0, u32 at `0x02633d64` | `0x0059176c..0x005917c8`; the helper reads it signed using `ldrsw` |
| `sPst` | Optional `long` | 0, u32 at `0x02633e68` | `0x005917d0..0x0059182c` |
| `sPsp` | Optional `long` | 0, u32 at `0x02633e6c` | `0x00591834..0x00591890` |
| `sPrg` | `utxt` / `utf8` | Pascal string buffer at `0x02633d68`, capacity `0x100` | Type comparisons `0x00591894..0x005918d0`; UTF-8 conversion `0x005918d4..0x00591934`; UTF-16 conversion `0x005919dc..0x00591a14` and `0x00591ab4..0x00591ad0`; Pascal conversion `0x00591ad4..0x00591af4` |

Optional fields are retrieved with `AEGetParamPtr` only when `AESizeOfParam` succeeds and the type is exactly `long`. Missing fields or different types retain defaults. Retrieval errors take the caller's error return path. Type checking does not establish complete size/range validation or safe execution.

`sPrg` is required at this entry, but **has not been established as a selector that searches existing regions by name**. In the helper's non-MIDI path, it writes a name into a file-side structure. The CFString created from UTF-16/UTF-8 is converted to a Pascal string using `CFStringGetSystemEncoding`. The result of `CFStringGetPascalString` is not checked before proceeding (`0x00591adc..0x00591b10`). Full preservation of arbitrary Unicode names and correct contents after conversion failure are therefore not established.

The `sPve` store is confirmed, but no direct read of its storage was found in the helper. Do not infer a semantic meaning such as version from its abbreviation.

## 2. Target selection

The helper uses current song and a structure selected by an auxiliary function. At `0x00591e18..0x00591e40`, it calls `FUN_004f1cf4(0x7049)` and reads a 32-bit target from the returned structure's `+0x74` if its `+0x70 == 0x7049`; otherwise it reads song `+0x10`. The structure's formal type is unresolved. A relationship to UI/focus is a Hypothesis, confidence: medium.

- `sPtn <= 0` is changed to 1 (`0x00591e44..0x00591e64`).
- Song signatures `0xabc04723` / `0xabc04713` are checked (`0x00591e68..0x00591e88`).
- Target values `0x7ffffff8` / `0x7ffffffc` use special resolution paths. Other values reject the top bit and low two bits, then index a pointer array using `id >> 2` (`0x00591e8c..0x00591f24`).
- The resolved structure's `+0x330..+0x338` is an array with stride `0x50`. Counts depend on type bytes and other conditions; `FUN_019fb130(entry, owner)` maps the input ordinal to another 1-based index (`0x00591f34..0x00592170`). The final value is handled as 16 bits; bit 15 terminates processing (`0x00592174..0x0059217c`, `0x005923a8`).

**Confirmed boundary:** `sPtn` is not used simply as an MCU mixer position or stable track ID. Its ordinal is transformed using the current target array and predicate; mode 2 may replace it with a song/selection-derived value.

**Additional machine confirmation:** `FUN_019fb130` is not a pure read predicate. When the next candidate's and current candidate's `+0x12` bytes differ by at least 2, `strb w9,[x8,#0x12]` at `0x019fb294` writes into the current candidate (comparison/store `0x019fb280..0x019fb2a0`). The helper calls it during target resolution, so internal metadata may change before file import. Its relationship to disk dirty state remains unvalidated.

**Hypothesis, confidence: medium:** This array and predicate relate to displayed track hierarchy, visibility, or collapsing. The meanings of type bytes, `+0x12`, and flags at `+0x14` remain unresolved.

Small resolver `FUN_001a1dcc` also returns a candidate from the same stride `0x50` array using song/target value/a 1-based 16-bit index (callee instructions `0x001a1dcc..0x001a1ef0`, C output `q-appleevent-object-resolvers-001.c`). This helps narrow the target type, but does not establish stable track IDs or equivalence to mixer positions.

## 3. Position selection by mode

The table describes **branches and data sources**, not runtime-validated mode names.

| `sPmo` | Machine-confirmed behavior | Addresses |
|---:|---|---|
| 1 | Uses the 64-bit return from `FUN_001a388c(song, 0)` | `0x00592220..0x00592234` |
| 2 | If song `+0x38 == -1`, uses that getter and selects a track candidate by comparing the auxiliary structure with song data. Otherwise uses song `+0x28` and `+0x22`. Track candidates 0/`0xffff` become `0xffff` | `0x005921a8..0x005921d0`, `0x00592238..0x00592274` |
| 3 | Reads `sPss` signed 32-bit; converts it through `FUN_007ac29c(song, anchor, input, -1)`. Compares using the apparent reverse conversion `FUN_007abc8c`; if needed, increases position by `0x100000000` and recalculates. Keeps a positive difference as a 32-bit correction | `0x005921d4..0x005921dc`, `0x00592328..0x00592388` |
| 5 | Computes an offset from the structure returned by `FUN_001a924c`, a format index from song `+0xc4` clamped to 0..11, table `0x01d58bd0`, global `0x025ecad8`, and constant 1001; subtracts it from `sPss`. Negative/out-of-range results terminate processing. Then follows the mode 3 conversion | `0x005921e0..0x00592324` |
| Other | Skips those special cases and proceeds toward file classification/import with the default anchor | `0x00592188..0x005921e4` → `0x00592398` |

The anchor is `0x960000000000`; the upper limit is `0x3ffff0ff00000000`. Positions for modes 1/2/3/5 are bounded by these values (`0x0059238c..0x005923a4`). The non-MIDI placement candidate uses the position minus the anchor (`0x005927dc..0x005927e4`, `0x00592858..0x00592860`). This demonstrates an encoded/biased time representation, but does not establish ticks, beats, or samples.

**Hypothesis, confidence: medium:** `sPss` may be a placement value in a sample/time domain, and mode 5 may handle a reference offset such as timecode. The [position-conversion follow-up](SA-AE-TIME-001-position-conversion.en.md) traces the small callees into `FUN_019adc00`, `FUN_019fd568`, and `FUN_019ade8c`, confirming the initial rate value 44100, fixed-point arithmetic, delta/anchor addition, and internal cache writes. Units, epoch, and runtime rate updates remain unresolved. One-second, one-beat, and one-sample boundaries and dependence on sample rate/tempo changes have not been validated live.

**Unknown-mode reachability is machine-confirmed:** For modes 0, negative values, and values ≥15 that the caller does not route elsewhere, the helper's default branch does not reject the import path. Depending on file/target conditions, MIDI/non-MIDI processing is reachable. Do not send or explore unknown modes on the assumption that they do nothing. This does not assert that every input successfully mutates state.

## 4. MIDI and non-MIDI mutation paths

The helper copies a `CFileRef` and branches on `CFileUtilFileType`: `.MID` / `idiM` / `Midi` select MIDI (`0x005923ac..0x005923f4`); other values select the non-MIDI path. Not every non-MIDI file is established as valid audio.

| Path | Statically confirmed changes/calls | Addresses |
|---|---|---|
| MIDI | If `FUN_004f3ba8` returns 0, passes the target 16-bit index and 64-bit position to `FUN_002a2ee0` | `0x005923f8..0x00592410`, `0x0059245c..0x0059249c` |
| MIDI postprocessing | Under conditions, ORs 3 and 4 into song `+0xe4`, and 8 into `+0x96`; calls `FUN_001be198` between stores | `0x005924a8..0x00592510` |
| Non-MIDI | Obtains a file-side object candidate through callback-based `FUN_0106cb7c`, existing-candidate `FUN_019cfff0`, or fallback `FUN_00256820`. Also changes global flags | `0x00592574..0x0059260c` |
| Non-MIDI metadata | Selects a candidate from the object's `+0x2e8..+0x2f0` array with stride `0x2f8`. Copies/fixes `sPrg` as UTF-8 at `+0x30`; writes `sPst` at `+8`, zero at `+0xc`, `sPsp-sPst` at `+0x18` if `sPsp > 0`, and the mode-derived correction at `+0x20` | Candidates `0x0059263c..0x00592724`; stores `0x00592764..0x005927b8` |
| Non-MIDI placement candidate | Searches via `FUN_0029c998`, then compares target, track, and position. On mismatch, calls `FUN_0029d5b0`, followed by selection/update-like helpers and a global flag clear | `0x005927c4..0x005928c4` |

The `sPst/sPsp` stores address a metadata array on the file object. **An API for addressing an arrange region by ID and arbitrarily editing its position/length has not been established.** In particular, this path writes `sPrg` into metadata before comparing placement candidates; it is not a name written after searching for an existing region.

**Hypothesis, confidence: medium:** `sPst` may be a start within the file, `sPsp` an end, and `+0x18` a length. Samples, bytes, and ticks remain unresolved. The `sPsp > 0` check does not validate `sPsp >= sPst` or valid file bounds at this location.

Complete audits of Undo, dirty state, and region creation in the large callees `FUN_002a2ee0` / `FUN_0029d5b0` remain outstanding. The stores above directly demonstrate mutation potential, but human-readable flag meanings and saved disk results have not been validated live.

**Metadata selection also calls an initializer:** At `0x00592678`, the helper calls `FUN_0042120c` with `w5=1`. That callee scans stride `0x2f8` candidates. If the candidate's first short is 0 and its signed byte at `+0x24` is nonnegative, it passes candidate `+0x28c` to `CUUIDBase::Init(...,0)` (`0x00421264..0x0042130c`). Instructions and the import name confirm the call, but the initializer's exact stores and the UUID's meaning are outside this audit. Do not treat it as a getter that only searches existing candidates. Its return combines a low 32-bit index and upper flag, including failure candidate `0xffffffff` (`0x004212a4..0x004212bc`, `0x00421318..0x0042132c`). Do not use the inferred C return type as a simple pointer.

## 5. Success and error returns

Immediately after the helper call at `0x00591b10`, `0x00591b14` branches to `0x005911d8`, which executes `mov w22,0`; `0x00591070` returns `w22` narrowed to signed 16 bits. **The helper return is not converted into an operation result.** This normal file/region return path does not write `sPer`. Do not confuse it with text modes' `sPer=0` replies.

The helper can return early for invalid targets, out-of-range positions, parser errors, and other cases; the common exit is `0x00592424..0x00592458`. The caller may still return 0 afterward. Descriptor retrieval errors instead propagate through caller `w22`. Recognition, decoding, import execution, and the requested outcome must be treated separately.

No reliable external readback, returned region ID, completion notification, or long-running job contract has been established. A successful reply alone cannot justify `verified: true`.

## 6. Next bounded analysis

1. Inspect the meaning of the confirmed `FUN_019fb130` store and the internals of `CUUIDBase::Init` called from `FUN_0042120c`, within a limited scope. Separate internal metadata changes from song dirty state, Undo, and saved results.
2. Follow the conversion wrappers one level into `FUN_019adc00` / `FUN_019fd568` / `FUN_019ade8c` to establish input/output/rounding units. Do not infer samples from names.
3. Inspect `FUN_0029c998` block `FUN_0029ca8c` and file import `FUN_0041e870` within a limited scope; distinguish file object IDs, metadata indices, and arrange events.
4. Then inspect `FUN_002a2ee0` / `FUN_0029d5b0` for creation/replacement, Undo, dirty state, notifications, and error boundaries.

Once the static contract is established, dynamic validation requires a separate experiment record: dedicated project, one field, multiple values/targets, before/after, save/reload, and independent readback. This record contains no event-sending or unknown-mode execution experiment.
