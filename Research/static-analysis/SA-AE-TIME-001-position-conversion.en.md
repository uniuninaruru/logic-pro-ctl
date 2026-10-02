# SA-AE-TIME-001: Position conversion for AppleEvent file placement

[日本語](SA-AE-TIME-001-position-conversion.md) · [English](SA-AE-TIME-001-position-conversion.en.md)

| Item | Details |
|---|---|
| Date | 2026-10-02 |
| Baseline | Logic Pro Creator Studio 12.3.1 / build 6682, `Logic.framework` ARM64 |
| Baseline SHA-256 | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| Scope | Position conversion wrappers called by the file/region helper, conversion cores, context initialization, fallback map |
| Execution | Static audit of saved read-only/noanalysis output only. No events, connections, or live operations against Logic |
| Manifest | [appleevent-time-analysis-manifest.json](appleevent-time-analysis-manifest.json) |

This pass establishes **input/output arithmetic and internal cache writes**. Samples, BPM, PPQ, and adaptation to the actual song's rate remain hypotheses. It does not establish an externally usable read-only API or successful file placement.

Addresses are image addresses before the slide in the baseline build. This builds on the [file and region branch](SA-AE-FILE-001-file-region.en.md) and [registration analysis](appleevent-registration.en.md). Do not infer ABI or units solely from C prototypes, aliases, or function names.

## 1. Evidence and function boundaries

| Local output | Targets |
|---|---|
| `q-appleevent-time-core-001.c` / `q-appleevent-time-core-001-machinecode.txt` | `0x019adc00`, `0x019fd568`, `0x019ade8c`, `0x019ae130` |
| `q-appleevent-time-constructor-001.c` / `q-appleevent-time-constructor-001-machinecode.txt` | `0x01a125c4` |
| `q-appleevent-modes-callees-001-machinecode.txt` | Wrappers `0x007abc8c` / `0x007ac29c` |
| `q-appleevent-modes-001-machinecode.txt` | Caller `0x00592328..0x00592388` |

These remain local under `Research/raw/ghidra/`; full decompilations and large instruction dumps are not added to Git. Use the manifest to match the analysis target and outputs.

## 2. ABI recovered from ARM64

| Function | Input register roles | Output and confirmation |
|---|---|---|
| `FUN_019adc00` | `x0=song`, `w1=target selector` | `x0=map candidate`; fallback returns `0x027771c0` (`0x019ade6c..0x019ade78`). C's `void` is inaccurate |
| `FUN_019fd568` | `x0=context`, `x1=anchor`, `x2=position`, `x3=map`, `x4=optional cache` | If `x1!=0`, returns `convert(position)-convert(anchor)`. Two recursive calls and subtraction: `0x019fd668..0x019fd698` |
| `FUN_019ade8c` | `x0=context`, `x1=anchor`, `x2=integer-domain increment`, `x3=map`, `x4=optional cache` | Returns a **delta, not the converted absolute position**, via `sub x0,x9,x1` at `0x019ae0e0` |
| `FUN_01a125c4` | `x0=context`, `x1=rate-like initial integer` | Stores at `+0`/`+8` and links cache nodes into a global list (`0x01a125f4..0x01a12628`) |

The C output for `FUN_019fd568` aliases post-call registers to original parameter names, making the subtraction appear to use the same variable twice. Instructions retain the first return in `x23` and subtract it from the second return. Each absolute conversion has its own `+1`, `FCVTZS`, and `ASR16`; reducing a general interval to a single proportional formula loses those rounding steps. Do not interpret the result as zero or an absolute value.

Wrapper `FUN_007abc8c` obtains a map through `FUN_019adc00(song,-1)` when `x3==0`, then tail-calls `FUN_019fd568` with context `0x0266b680` and `x4=0` (`0x007abcb0..0x007abcec`). `FUN_007ac29c` also obtains a map and tail-calls `FUN_019ade8c` with the same context and `x4=0` (`0x007ac2c8..0x007ac2fc`).

The file helper receives the delta from `FUN_007ac29c(song,anchor,sPss,-1)` and adds it to the anchor at `0x00592344`. It compares an inverse-wrapper conversion with the input, increases raw position by `0x100000000` if needed, and stores a positive residual as a 32-bit correction (`0x00592328..0x00592388`). This boundary includes placement correction, beyond a simple integer unit conversion.

## 3. Context initialization and unresolved rate behavior

Both wrappers initialize the context with **immediate `0xac44 = 44100`** in constructor `w1` (`0x007abd34..0x007abd38`, `0x007ac334..0x007ac338`). The Ghidra annotation referencing `FUN_0000ac44` does not indicate a function pointer here.

The constructor stores the integer with `str x1,[x0]`, multiplies it by 625 as a 64-bit integer, converts it to double with `SCVTF`, and stores that double at `[x0,+8]` (`0x01a125f4..0x01a12614`). The cores read this double as their scale.

At `0x01a12618..0x01a12628`, it links context `+0x10`, `+0x48`, and `+0x80` in sequence, then updates global `0x02777108` to `context+0x80`. This links three internal nodes rather than merely registering one context pointer. Initialization also has a guard and atexit registration.

**Unresolved:** This pass does not trace later rate/scale updates or consumers of the linked global list. The initial 44100 neither proves that the actual project sample rate is 44100 nor that this context remains fixed at 44100 for 48/96 kHz songs.

## 4. Map scanning and confirmed arithmetic

Both cores scan the map in **16-byte steps**, skip slots with timestamp bit 63 set, and mask timestamps with `0x7fffffffffff0000` (`0x019fd724..0x019fd72c`, `0x019adefc..0x019adf04`). Scan slot width need not equal logical record width. The denominator is signed 32-bit at the current record base `+0x10`, sign-extended before conversion to double.

For context scale `S`, current denominator `D`, and raw position difference `d`, the integer-domain contribution of a span follows this order:

```text
q = arithmetic_shift_right(d, 16) + 1
span = arithmetic_shift_right(trunc_toward_zero(S * double(q) / double(D)), 16)
```

Instructions perform `ASR16 → +1 → SCVTF → FMUL → signed32 denominator → FDIV → FCVTZS → ASR16`. Intermediate-record accumulation is at `0x019fd73c..0x019fd768`; the final span is at `0x019fd780..0x019fd7ac`. Do not replace this with a continuous formula omitting `+1`, or with ordinary rounding to nearest.

The reverse path locates the record containing the anchor, scans forward for positive input and backward for negative input, and subtracts amounts consumed by complete spans. It converts the remaining integer-domain amount `n` to a raw position difference:

```text
positive remainder: delta = trunc_toward_zero(double(n << 16) * double(D) / S) << 16
negative remainder: subtract the analogous delta for the remaining magnitude
return new_position - anchor
```

Final positive arithmetic is at `0x019ae0bc..0x019ae0e0`; negative arithmetic is at `0x019ae100..0x019ae124`. Floating values are doubles; `FCVTZS` truncates toward zero and right shifts are arithmetic. Left shifts also operate on 64-bit registers: do not equate arbitrarily large inputs with unbounded-precision formulas.

## 5. Arithmetic examples and unit hypotheses

These are **synthetic local arithmetic examples derived from the confirmed formula**, with no native function execution or live results. Assume constant `D=1200000`, constructor initialization `R=44100`, `S=625*R=27562500`, and no crossing of record boundaries; evaluate the reverse delta.

| Integer-domain input | Raw delta | `raw delta / 2^32` |
|---:|---:|---:|
| 0 | 0 | 0 |
| 1 | 186974208 | 0.0435333251953125 |
| 22050 | 4123168604160 | 960 |
| 44100 | 8246337208320 | 1920 |

Because `625 = 600000 / 960`, **Hypothesis, confidence: medium:** `D=BPM*10000`, integer-domain values in samples, and raw positions encoding 960 PPQ in Q32 are consistent with this arithmetic. For example, one second at 120 BPM is two beats, or 1920 ticks. This numerical agreement alone does not establish units, the tempo field, project sample rate compatibility, or the epoch.

## 6. Cache/fallback writes and limits

When `x4==0`, the map does not satisfy the sentinel condition, and execution is on the main thread, cores select caches inside the context. The primary cache is at `+0x10`; the two interval evaluations also use `+0x48`/`+0x80` (`0x019fd594..0x019fd6e8`, `0x019adf58..0x019adfa0`). Non-main-thread and certain sentinel paths bypass the caches.

Cache mismatches update generation-like fields and the map pointer; scans store the record pointer and accumulated integer value (`0x019fd608..0x019fd61c`, `0x019fd778..0x019fd77c`, `0x019adee0..0x019adef0`, `0x019adf50`). Arithmetic functions also mutate internal state, so they are not treated as pure functions.

Map resolver `FUN_019adc00` includes atomic reference-count updates, virtual calls, and map-preparation callees (`0x019adce8..0x019add60`). Its fallback sends the format value at song `+0xc4` and integer at `+0xcc` to `FUN_019ae130`, then returns global record `0x027771c0` (`0x019ade5c..0x019ade78`). All lower-level callee side effects remain unaudited.

Fallback initialization calls `FUN_019ae9dc` twice: first with `x0=0x027771c0` and anchor argument `0x960000000000`, then with **the first call's returned `x0` plus `0x20` as destination** and sentinel argument `0x3fffffff00000000` (`0x019ae254..0x019ae284`). That callee's return behavior and field layout remain unaudited. Nonzero denominator inputs are clamped with signed comparisons to `50000..9900000` and stored at `0x027771d0`; zero preserves the existing value (`0x019ae194..0x019ae1b8`). Format values other than `-1` also update separate global fields (`0x019ae1bc..0x019ae1cc`).

This confirms global/cache writes, not that persisted tempo maps or song dirty flags necessarily change. It also supplies no read-only guarantee for every path. The earlier finding that a file/region caller reply of zero does not prove execution success still applies.

## 7. Next bounded checks

1. Trace references to `0x0266b680` and the globally registered nodes for rate/scale updates, cache generation invalidation, and lifetime.
2. Audit denominator record constructors and setters of song `+0xcc` for units and their relationship to tempo changes.
3. First reproduce flat/multiple-record/bit63/positive/negative/boundary/rounding cases in local fixtures to validate the arithmetic contract. Do not label them equivalent to live snapshots.
4. Then compare sample rate, tempo, and position one condition at a time in a separate dedicated-project experiment, with independent readback and save/reload.

While units, epoch, target scope, side effects, and execution outcomes remain unresolved, do not expose `sPss` as samples in an external API or promise compatibility with native position APIs.
