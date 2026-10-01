# EXP-MCU-001…009: Logic Control (MCU) over a virtual MIDI port pair

| Field | Value |
|---|---|
| Date | 2026-10-01 13:27–13:33 JST |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | ~/Music/Logic/LogicCLI-Test.logicx (1 Piano inst, 2 Audio, 3 Bass inst, 4 Synth inst; all 0.0 dB, unmuted) |
| Tool | `Tools/research-scripts/mcu-probe.swift` (virtual source + destination `logicctl-mcu`), `Tools/packet-analyzer/mcu_log.py` |
| Raw | `Research/raw/20261001-132705-mcu/` (manual handshake), `Research/raw/20261001-133000-mcu-auto/` (auto handshake, all later steps) |

Directions: RX = Logic → probe, TX = probe → Logic.

## EXP-MCU-000: probe ports appear (no action in Logic)
Within 0.3 s of the virtual ports appearing, Logic sent, unprompted, to the
new destination:
`F0 00 00 66 <m> 00 F7` for m = 10, 11, 14, 15, 17 and `F0 00 00 66 <m> 13 00 F7`
for m = 14, 15, 17. Logic scans every new MIDI port for Mackie devices.
No GUI configuration was done.

## EXP-MCU-001/002: manual replies 18 s later
TX connection query (`14 01` + serial + 4 challenge bytes) → RX `14 13 00` twice.
TX version (`14 14 "V1.02"`) → nothing. Control Surface Setup window showed
「デバイスが見つかりません」. Not installed.

## Auto handshake (probe restarted with MCU_AUTO=1, replies within 1 ms)
RX query 00 → TX 01; RX 13 → TX 14. Logic did **not** send cmd 02 (connection
reply) — the public spec's challenge step was skipped. Within 40 ms Logic
started sending surface state:
- LCD (`14 12`, offset 0): `Piano  Audio  Bass   Synth  St Out Master` / `Pan …`
- Faders: pitchbend ch0–5 = 12443, ch6–7 = 0, ch8 (master) = 12443
- LEDs on: 0x00 (strip-1 rec arm), 0x18 (strip-1 select), 0x2A, 0x4A, 0x59, 0x5D, 0x72
- Also cmd 0A, 0B, 0C, 0E, 20, 21, 72 (meaning not checked)

Matches the GUI: track 1 R lit and selected, all faders 0.0 dB, 4 tracks + Stereo Out + Master.
Unknown: whether the earlier manual attempt failed because of timing or because
Logic had already given up on that port.

## EXP-MCU-003/004: GUI mute track 1, single action
| Action | RX |
|---|---|
| GUI Mute OFF→ON (mixer strip M, AXPress) | `90 10 7F`, then `90 50 7F` |
| GUI Mute ON→OFF | `90 10 00` |

Note: AXPress on the *track header* M checkbox had no visible effect;
AXPress on the inspector strip's `ミュート` AXSwitch worked.
`90 50 7F` stayed on after unmute — meaning unknown.

## EXP-MCU-005/006: MCU write mute, single action
| TX | RX | GUI |
|---|---|---|
| `90 10 7F`, `90 10 00` (press, release) | LCD offset 56 "Muted", then `90 10 7F` (+33 ms) | M lit |
| same again | LCD offset 56 "--", then `90 10 00` | M off |

The mute button is a toggle; LED feedback confirms the new state.

## EXP-MCU-008: MCU write fader, single action
TX `90 68 7F` (touch strip 1), `E0 78 55` (11000), `90 68 00` (release)
→ RX LCD offset 56 "-3.7 dB ", RX `E0 59 55` (10969). GUI: -3.7.
Logic quantizes the value and echoes the quantized one.

## EXP-MCU-009: fader sweep 0…16383 step 256
Table: `Research/protocol/mcu-fader-calibration.tsv`. Highlights:
| sent | echo | LCD |
|---|---|---|
| 0 | 0 | -oo dB |
| 7680 | 7660 | -9.9 dB |
| 9472 | 9467 | -6.7 dB |
| 11264 | 11248 | -3.0 dB |
| 12443 (restore) | 12443 | +0.0 dB |
| 14848 | 14845 | +6.0 dB |
| ≥15104 | (none) | (none: clamped at +6.0) |

LCD updates are diffs: only changed characters are sent at the offset where
they start (e.g. offset 58 "4.7" after "-56.9 dB"). The analyzer keeps a
112-char buffer.

Restored afterwards: 12443 → LCD "+0.0 dB", echo 12443, GUI 0.0.

## Hypotheses
Hypothesis: Strip-1 Mute is note 0x10 (toggle on press), LED feedback uses the same note.
Confidence: high for track 1 / strip 1 (2 GUI + 2 MCU observations).
Counterexamples: none.
Next validation experiment: mute tracks 2 and 4 (expect 0x11, 0x13); solo (expect 0x08+n).

Hypothesis: Fader value v ↔ dB is a fixed monotonic curve; 12443 = 0.0 dB, 14845 = +6.0 dB max.
Confidence: medium (one track, one sweep; resolution 256 → ±0.6 dB between points).
Counterexamples: none.
Next validation experiment: repeat the sweep on track 3 and on the Audio track; finer sweep around 0, -3, -6, -12 dB; check whether readback is exact when Logic's quantized echo value is sent.

Hypothesis: The LCD lower row shows the touched parameter in dB during touch and reverts after ~1 s; usable as human-readable readback.
Confidence: medium.

Hypothesis: Logic auto-installs any port answering the model-0x14 query, without the challenge/response.
Confidence: medium (one auto run). Next: restart the probe and check whether a second "Logic Control" device gets added each time (setup pollution).

## Consequence for logicctl
MCU over virtual MIDI is a viable v0.1 backend with readback:
volume (fader echo + LCD dB), mute (LED), track names (LCD), 8-strip banks.
logicd must keep a long-lived CoreMIDI client (virtual ports exist only while
it runs) and answer the handshake within milliseconds.

# EXP-MCU-010…016 (same session, 13:38–13:41 JST, raw in 20261001-133000-mcu-auto)

All writes from the probe; GUI checked by screenshot where noted. State restored after each.

| ID | TX | RX (readback) | GUI |
|---|---|---|---|
| 010a–c | Mute press strips 2,3,4 (`90 11/12/13 7F`, release) | LCD "Muted" at offset 63/70/77 (=56+7n); LED `90 11/12/13 7F` | M lit on tracks 2–4 |
| restore | same presses | LED `90 11/12/13 00` | — |
| 011a | Solo strip 1 (`90 08 7F`, release) | LCD "Soloed" @56; LED `90 08 7F`; `90 73 01` (rude solo, vel 1); LEDs 0x11–0x13 then **blink** 7F/00 every ~0.75 s | S lit on track 1 |
| 011b | Solo strip 1 again | LCD "--" @56; `90 73 00`; `90 08 00`; LEDs 0x11–0x13 → 00, blinking stops | — |
| 012 | Select strip 3 (`90 1A 7F`, release) | LEDs 0x18→00, 0x1A→7F; rec-arm LED 0x00→00, 0x02→7F | inspector "トラック: Bass", R moved to track 3 |
| 013a | V-Pot strip 1 `B0 10 41` (ccw 1) | LCD lower @56 "-1", upper strip 1 → "Pan"; ring `B0 30 16` | — |
| 013b | `B0 10 45` (ccw 5) | LCD "-6" | — |
| 013c | `B0 10 06` (cw 6) | LCD "0"; ring `B0 30 56` | — |
| 014a | Play `90 5E 7F`, release | LED 0x5E→7F, 0x5D→00; meters `D0 4x` (strip 4 = St Out) | playing |
| 014b | Stop `90 5D 7F`, release | LED 0x5D→7F, 0x5E→00 | stopped (bar 8 beat 2) |
| 015 | Touch strip 2 only (`90 69 7F`), no fader move | LCD @63 "+0.0 dB " | unchanged |
| 016a/b | V-Pot `B0 10 54` (ccw 20), `B0 10 14` (cw 20) | LCD "-20", then "0" | — |

Findings:
- Strip n (0-based): mute note 0x10+n, solo 0x08+n, select 0x18+n, rec 0x00+n, fader touch 0x68+n, V-Pot CC 0x10+n (bit 6 = ccw, low 6 bits = ticks), ring CC 0x30+n. LCD lower row strip n at offset 56+7n. Verified for n=0..3 (mute), n=0 (solo, pan), n=2 (select), n=0,1 (touch).
- 1 V-Pot tick = 1 Logic pan unit, linear up to 20 ticks per message (no acceleration observed).
- **Mute LED is not the explicit mute state while any solo is active**: implicitly muted strips blink. Readback must use the LCD transient ("Muted"/"--", "Soloed"/"--") right after a press, or sample the LED twice >0.8 s apart.
- **Touch without moving reads the exact dB** on the LCD → exact volume readback without writing.
- Selecting a track moves record-arm with it (Logic's auto rec-arm), visible as rec LEDs.

## Accessibility cross-check (13:42, after the user granted Accessibility)
`AXIsProcessTrusted() == true` for the shell (responsible app: `~/Library/Application Support/Claude/claude-code/2.1.284/claude.app`, a versioned path).
Track header: AXSlider "ボリューム" value=173 desc "+0.0 dB"; AXSlider (pan) value=64 desc "0のパン"; AXCheckBox "ミュート" value=0.
Inspector strip: AXSlider "ボリュームフェーダー" value=173 desc "0.0 dB"; AXButton "ミュート" value "オフ".
Transport/position: AXSlider "bar"=8, "beat"=2, "テンポ"=120.
→ Independent second readback channel; not used by v0.1.
