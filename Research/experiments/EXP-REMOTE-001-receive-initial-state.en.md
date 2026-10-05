[日本語](EXP-REMOTE-001-receive-initial-state.md) | [English](EXP-REMOTE-001-receive-initial-state.en.md)

# EXP-REMOTE-001: connect a research peer once under its own name and only receive Logic's initial send

| Item | Value |
|---|---|
| Date and time | 2026-10-05 09:39 to 09:44 (JST). E0 = 09:39:20, E1/E2 = 09:42:34 to 09:43:52 |
| Logic version | 12.3.1 (6682) (Logic Pro Creator Studio) |
| macOS version | 27.0 (26A5416b), arm64 |
| Logic Remote version | Not applicable (no real Logic Remote; the research peer `Tools/remote-research-peer` was used) |
| Test project | LogicCLI-Test.logicx (the only song open) |
| Initial state | 12 strips (order: Piano, Synth, Trk08, Audio, Bass, Trk10, Trk07, Trk06, Trk05, Trk09, St Out, Master, after the user reordered them by hand). All strips at 0 dB, pan centre, nothing muted, stopped, Trk08 selected |
| The one operation | The research peer `logicctl-research-peer` invites → "Connect" is pressed in Logic's dialog → only `/protocolVersion = 10` and `/jsonSupport` are sent, then 60 s of receiving |
| Expected change | Logic's state does not change. Only the peer's registration remains ([approval brief](../plans/PLAN-05-approval-brief.en.md) §2) |
| Repetitions | 1 (E0 once, E1/E2 once). **A single observation**; whether the values are stable is not confirmed |
| Approval | The user approved PLAN-05 (2026-10-05). "Connect" was pressed by Claude with the user's permission |

## Observations

### E0 (browse only)

- The `apple-lgremote` advertisement was found in 0.12 s. The peer name is the host's localized name; `discoveryInfo` is `/hostType = "0"`, `/protocolVersion = "10"` (as in SA-REMOTE-SESSION-001 §2).
- Nothing was sent and nobody was invited.

### E1/E2 (connect and receive)

- `connecting` 16.2 s after the invitation, `connected` 16.3 s after it (a person read the dialog and pressed the button in between). The dialog said that "logicctl-research-peer" wants to connect to Logic Pro; the buttons were "Don't Connect" and "Connect" (Japanese UI).
- Only two messages were sent: `/protocolVersion = 10` and `/jsonSupport = 1` (two `sent` lines in `events.jsonl`). Nothing was sent after that.
- Received in 60 s: **5,947 frames, 6,141 messages, 707 distinct addresses.**
- **The product's `RemoteFrameParser` decoded all 5,947 frames (0 failures).** An independent decoder written in Python (`Tools/research-scripts/remote_capture.py`) also decoded all of them.
- **Every state message passed the schema ([`logic-remote-state.schema.json`](../protocol/logic-remote-state.schema.json)) (0 violations).**
- Formats: JSON (format 4) 5,923, plist (format 1) 19, plist in MAZP 3, keyed archive (format 2) in MAZP 2. Every uncompressed payload was 1,024 bytes or less.
- Logic's state (playback, selection, volume, pan, mute and solo of the 12 strips) was the same before and after (compared with `logicctl state`).
- Raw data: `Research/raw/remote-recv/20261005-093920-e0/`, `Research/raw/remote-recv/20261005-094234-e1/` (not tracked by Git; 27 MB).

### Against the predictions (brief §4 and SA-REMOTE-TRACKTYPE-001 §7)

| # | Prediction | Result | Verdict |
|---|---|---|---|
| P1 | `/protocolVersion = 10` and `/jsonSupport` arrive first | 1st `/protocolVersion = 10`, 2nd `/jsonSupport` (argument **0**) | Pass |
| P2 | The initial send starts after waiting for the version | Our two messages were sent at the moment of connection (0 ms), so whether Logic waits cannot be told apart | Cannot tell |
| P3 | The order of the initial send follows the table in SA-REMOTE-STATE-001 §3 | Rows 2 to 16 and 5a to 5f arrived **in this order**. Messages not in the table arrived too (below) | Pass (with additions) |
| P4 | `/ati` is 13 arrays of equal length | 13 arrays of 12 elements. Passes the schema | Pass |
| P5 | `/ati` and `/allTrackCount` / `/trackCount` arrive twice | Twice each. The two `/ati` are identical | Pass |
| P6 | `/sti`'s argument is a MAZP-compressed keyed archive | An `NSData` inside a plist frame, MAZP; it inflates to a dictionary | Pass |
| P7 | The keys of `g` in `/gtFaderData` = the `gindex` values of `/ati` | All 12 match | Pass |
| P8 | Tempo unit and the direction of `/multiTempo` | `/logicClock/currentTempo = 1200000` (120 BPM → **BPM × 10000**). `/multiTempo = true` for a song with one tempo (matches the code reading "1 = all the same") | Confirmed at one point |
| P9 | How `vL` relates to dB | `vL = 0x5A000000` on every strip at 0 dB. The top byte 90 matches `/cs/mixer/volume/volumeN = 0.70866` (= 90/127) | Confirmed at one point (0 dB only) |
| P10 | `s`, `m`, `vL` are present when 0 | All present | Pass |
| P11 | The initial send has no end marker | No fixed final shape. After `/newTrackSheetOpen`, `/undoLabel` and so on only the meters continue | Pass |
| P12a | Master's `t` is 5 | **Master is 6; Stereo Out is 5** | **Fail** |
| P12b | `t` of Piano, Bass, Synth is 9 | **2** | **Fail** |
| P12c | `t` of Audio and Trk05 to Trk10 is 1 | 1 | Pass |
| P12d | `t` of St Out is 6 or 10 | **5** | **Fail** |
| P12e | With only a software instrument selected, `/sti`'s `t` is 0 | The selection was an audio track (Trk08); `/sti`'s `t` = 1. The condition differs, so not tested | Not tested |
| P13a | Each `c` colour is 4 bytes and the fourth is almost always 0xFF | All 48 are 4 bytes with 0xFF fourth. The order matches the visible colours (audio = blue `36 6e aa`, instrument = green `1a a3 30`) | Pass |
| P13b | `tnc` and `tsc` of a colour-number-0 track are `8cc0ffff` | No track had colour number 0 (below) | Not tested |

### What was not predicted

1. **447 `/cs/…` messages arrive right after the connection** (`/cs/mixer/…` for 8 strips, `/cs/transport/…`, `/cs/bankLeftOffset`). This is the "feedback refresh" of SA-REMOTE-SESSION-001 §3.4 (step 2 of the connect block). Logic Remote is also handled as an 8-strip control surface. The values are fractions from 0 to 1 (0 dB = 0.70866 = 90/127; pan centre = 0.50394 = 64/127).
2. Before the initial send: `/libData`, `/docOpen` (twice), `/duplicateTrack`, `/undo`, `/redo`, `/sti` and the selection messages. `/docOpen` arrives twice more inside the initial send (row 14): four times in all, all `true`.
3. **Meters keep flowing while stopped**: `/mixerLevels`, `/bankNavigator/trackLevels` and `/mixer/gainReductionData` at 30 messages per second each (90 frames per second in all).
4. **`gindex` follows creation order, not position**: St Out 80, Master 84, Piano 88, Audio 92, Bass 96, Synth 100, Trk05 104 … Trk10 124. After the user's manual reorder it still kept the original creation order (Piano, Audio, Bass, Synth, Trk05 to Trk10). `BgTrackInfoTrackIDKey` (`0x4000N`) and `tn` (1 to 11) follow the current position. All 12 UUIDs differ.
5. `/ati` names are Logic's names as they are, **with trailing spaces** (`"Piano "`, `"Synth "`, `"Audio "`, `"Bass "`, `"Trk10 "`), a difference the MCU LCD does not show. The output is `Stereo Out` in `/ati` and `St Out` on the MCU LCD.
6. `nc` (column): audio 1, software instrument 2, Stereo Out 2, Master 6. `p`: −1 for Master only, 0 for the others. Master has `tn = -1` and `BgTrackInfoHasArrangeKey = false`; Stereo Out has `BgTrackInfoArrangeHiddenKey = true`.
7. **Each track's colour number**: `c.nc` matched `cellBackgroundColor` of `/colorIndexMap` within one unit: audio = 16, software instrument = 9, Stereo Out = 24, Master = 20. `defaultColorIndexForTrackTypes` = `{0: 9, 1: 16, 2: 9, 3: 76, 4: 9}` (exactly as in SA-REMOTE-TRACKTYPE-001 §4). The difference is at most 1 per component on all 12 strips and `nc` is always the smaller or equal, consistent with `/ati` truncating (`fcvtzs`).
8. In all four `sc` colours the smallest component is `0x99` (= 0.6): saturation 0.40 and brightness 1.00, as read from `FUN_00d35578(number, 40, 100)`.
9. Payload format: the 5 messages that arrived before the `/jsonSupport` exchange are plist, later ones JSON. Those holding `NSData` are plist; dictionaries with numeric keys (`/gtFaderData`, `/colorIndexMap`) are keyed archives (as hypothesised in SA-REMOTE-FRAME-001 §2 and §4).
10. Logic did not drop the connection in the 60 s of receiving, though nothing was sent.

### Side effects (confirmed)

- **Logic registered the peer as a device.** `logicctl-research-peer` was added to `ControlSurfaceDevicesDict` in `com.apple.mobilelogic`, and the control-surface settings file `~/Library/Preferences/com.apple.logic.pro.cs` was rewritten at 09:42 (an entry `Control Surface: logicctl-research-peer`).
- Logic's Control Surfaces Setup window shows it as a device (an iPad picture, name `logicctl-researc…`) **in a separate row** from the Mackie Control. It can likely be selected and deleted there (not done: it is a settings change and waits for the user's decision).
- The MCU route (`logicctl status`, `track list`) still worked after the registration.
- macOS's "Local Network" prompt was not shown as far as I (Claude) watched (I watched only Logic's window). Both the browse and the connection succeeded.

## Hypotheses

Hypothesis 1: **The kind word maps to `t` as 0x40 = audio (1), 0x43 = software instrument (2), 0x44 = output (Stereo Out, 5), 0x46 = Master (6).**
Confidence: high (four kinds, one project each).
Evidence: the `/ati` of this experiment. The static rules (SA-REMOTE-TRACKTYPE-001 §2) were right as they are; **the guesses about what each value means were wrong**. Logic using the name "Master Track" for kind word 0x44 fits if the "Master track" of the tracks area stands for the Stereo Out.
Counter-example: in another project (surround output, several outputs) an output is not 5.
Next experiment: E3 or later (separate approval): receive a project with a bus, a folder, a track stack and an external MIDI track added.

Hypothesis 2: **`gindex` is an identifier given in creation order, not a position, and survives a reorder.**
Confidence: medium to high (one reception after a reorder kept creation order).
Evidence: observation 4. There is no reception from before the reorder, so "the same value across a reorder in one session" was not seen directly.
Counter-example: `gindex` changes across a reorder in one session, or is renumbered when the project is reopened.
Next experiment: reorder once while receiving and compare `/ati` before and after (an E3 candidate; the reorder is done by a person). Whether it can serve the product's target check (PLAN-08) is decided from that.

Hypothesis 3: **The top byte of `vL` is the 7-bit fader position (0 to 127); 0 dB is 90.**
Confidence: medium (one point, 0 dB).
Evidence: `vL = 0x5A000000` and the `/cs` volume 90/127.
Counter-example: at a value other than 0 dB the top byte and the `/cs` volume disagree.
Next experiment: change one strip's volume through the MCU route while receiving and line up the `/gtFaderData` delta with `/cs` (an E3 candidate).

## Reproduce

```sh
Tools/remote-research-peer/build.sh
Tools/remote-research-peer/run.sh e0 --seconds 15
Tools/remote-research-peer/run.sh e1 --seconds 60 --target "<the name found in E0>"   # press "Connect" in Logic's dialog
python3 Tools/research-scripts/remote_capture.py report Research/raw/remote-recv/<time>-e1
```
