# SA-001: Logic Control.bundle (MCU plug-in) — Ghidra first pass

[日本語](SA-001-logic-control-bundle.md) | [English](SA-001-logic-control-bundle.en.md)

| Field | Value |
|---|---|
| Date | 2026-10-01 |
| Binary | `Logic Pro Creator Studio.app/Contents/PlugIns/MIDI Device Plug-ins/Logic Control.bundle/Contents/MacOS/Logic Control` (universal x86_64+arm64, 765,040 bytes; arm64 slice analyzed) |
| Logic | 12.3.1 (6682), bundle id `com.apple.music.apps.midi.device.plugin.Logic-Control` |
| Tool | Ghidra 12.1.4 headless, `Tools/ghidra/analyze.sh` → `Research/raw/ghidra/` (decompiled Apple code is not committed) |
| Result | 142 functions, all decompiled |

## Plug-in ABI (from exported symbols, `nm -gU -arch arm64`)
C entry points shared by every Control Surface plug-in (Logic Remote.bundle and
TouchOSC.bundle export the same core set): `init_dd`, `scan`, `init_dev`,
`deinit_dev`, `transfer`, `get_midi`, `peri`, `CSDefault`, `CSFeedback`,
`CSGroupClassForModel`, `CSLabelSize`, `ModID`, `Version`, `MinHostVersion`,
`NameForModel`, `ManufNameForModel`, `ManufIDForModel`, `FlagsForModel`.
Logic Control adds `CSTemplate`, `CSLabel`, `CSLongLabel`, `CSFeedbackText`,
`CSLongFeedbackText`, `CSRefresh`, `CSAlert`, `CSActivating`, `CSEndOffscreen`,
`CSFaderDBConversionTable`, `ScanAllModels`, `SpecialInfo`, `TimerCallback`.

Unstripped C++ names expose the host data model:
- `DDESCR_LC::CSFeedback(TControlID, long, long, long, AssignFeedbackType, long, AssignHeader const*)`
- `DDESCR_LC::FillTemplate(Assign*, TControlID, unsigned char) const`
- `DDESCR_LC::CSFeedbackText(TControlID, char const*, int, int)`
- `DDESCR_LC::DoHostConnectionQuery(ScanMode)`, `scan(char, ScanMode, char const*, char const*)`

The plug-ins import nothing from Logic's frameworks (`nm -u`): the host must
pass callbacks/data structures in at `init_dd`/`scan` time. Not yet traced.

Hypothesis: `Assign` / `AssignHeader` / `TControlID` are Logic's controller-
assignment model, shared by all control surfaces (MCU, Logic Remote, TouchOSC,
Lua scripts, Controller Assignments) — a candidate for the common
command/state representation (brief §16).
Confidence: medium (type names only). Next: decompile `FillTemplate` and
`CSFeedback` to recover the `Assign` layout; compare with Logic Remote.bundle.

## CSFaderDBConversionTable
Builds (once, `__cxa_guard`) a 35-entry table: 64-bit fader value + 32-bit
16.16 fixed-point dB, passed to `FUN_00000b5c(&table, 0x23)`.

| value | dB | | value | dB |
|---|---|---|---|---|
| 0 | -144 | | 7177 | -12 |
| 192 | -70 | | 7602 | -10 |
| 457 | -60 | | 8084 | -9.1667 |
| 695 | -57.5 | | 8553 | -8.3333 |
| 994 | -55 | | 9017 | -7.5 |
| 1234 | -52.5 | | 9485 | -6.6667 |
| 1446 | -50 | | 9970 | -5.8333 |
| 1753 | -47.5 | | 10450 | -5 |
| 2027 | -45 | | 12441 | 0 |
| 2285 | -42.5 | | 14459 | 5 |
| 2564 | -40 | | 14939 | 6.25 |
| 2797 | -37.5 | | 15440 | 7.5 |
| 3058 | -35 | | 15904 | 8.75 |
| 3567 | -32.5 | | 16380 | 10 |
| 3990 | -30 | | | |
| 4416 | -26.6667 | | | |
| 4912 | -23.3333 | | | |
| 5293 | -20 | | | |
| 5771 | -18 | | | |
| 6256 | -16 | | | |
| 6701 | -14 | | | |

Validation against the dynamic measurement (EXP-MCU-009,
`Research/protocol/mcu-fader-calibration.tsv`): linear interpolation of this
table, rounded to 0.1 dB, equals Logic's LCD reading for **58/58** points.
→ Confirmed: MCU fader value → dB is this table with linear interpolation
(channel strips clamp at +6.0 dB ≈ value 14843).

Applied: `Sources/LogicCore/Backends/MCU/FaderCalibration.swift` now uses this
table. Live check after the change: track 1 -6 / -3.7 / -12 / -30 / 0 dB all
verified (fader values 9874, 10969, 7178, 3990, 12443).
