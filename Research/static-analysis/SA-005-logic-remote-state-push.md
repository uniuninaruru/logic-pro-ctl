# SA-005: How Logic pushes state to a Logic Remote peer (read direction)

| Field | Value |
|---|---|
| Date | 2026-10-01 |
| Logic | 12.3.1 (6682), arm64 |
| Binaries | `Logic.framework` (`LgLogicRemoteController`), `MACore.framework` (`MAPeerRouter`, `Bg*` constants), `Logic Remote.bundle` |
| Method | Static only (Ghidra 12.1.4 decompile of already analysed programs, `Tools/ghidra/query.sh`; constant resolution with `Tools/research-scripts/macore_wire_keys.py`). Nothing was sent to Logic. |
| Derived table | `Research/protocol/logic-remote-wire-keys.tsv` (83 constants) |

Scope: which messages carry **state from Logic to a Remote client**, as a candidate
read path that does not depend on MCU. No dynamic confirmation yet; everything
below is "code says", not "wire shows".

## 1. Wire constants (MACore exports, resolved to strings)
Messages are `{address-or-key: argument}` dictionaries (SA-002 §3). The names the
Logic side uses, resolved from MACore's exported `Bg*` CFString constants:

| Constant | Wire value | Role (from use in Logic.framework) |
|---|---|---|
| `BgGInstAndTrackFaderDataKey` | `/gtFaderData` | batched fader/mute/solo/rec state |
| `BgGInstFaderDataGInstDataSubKey` / `…TrackDataSubKey` | `g` / `t` | instrument-keyed / track-keyed sub-dictionaries |
| `BgGInstFaderDataVolumeLevelLongKey` | `vL` | volume level (32-bit, signed byte shifted to the top, see §3) |
| `BgGInstFaderDataMuteStateKey` / `…SoloStateKey` | `m` / `s` | mute / solo state |
| `BgTrackFaderDataRecEnableStateKey` | `r` | record-enable state |
| `BgFaderEventKey` | `/fader` | fader events *from* the Remote (`handleFader:`) |
| `BgAllTracksInfoKey` / `BgSelectedTrackInfoKey` | `/ati` / `/sti` | track list / selected-track info |
| `BgTrackInfo…Key` | `n` name, `tn` track number, `t` type, `p` pan type, `ip` independent pan, `c` colours, `nc` channels | members of those dictionaries |
| `BgTrackSelectionStatePrefix` | `/trackSelectionStates` | selection states |
| `BgLevelMeters…Key` | `lmL`, `lmR`, `ti`, `iMT`, `mlmv`, `pklv` | meters |
| `BgProtocolVersionPrefix` | `/protocolVersion` | protocol version message |
| `BgHostTypeKey`, `BgJSONSupportKey`, `BgHostLocaleIdentifierKey` | `/hostType`, `/jsonSupport`, `/hostLocaleIdentifier` | handshake-time properties |
| `BgKeyCommand…` | `/keyCommand`, `/commandsQuery`, `/commandsResponse`, `/groupsQuery`, `/groupsResponse`, `/commandSearch`, `/commandResponse`, `/actionNum`, `/localizationRequest|Response`, `/keyCommandDictResponse` | key-command listing and execution (not traced yet) |

Already known from `strings` (SA-002/osc-address-strings): `/transport/headerState`,
`/transport/playButtonFlags`, `/transport/stopButtonState`, `/transport/pauseplay`,
`/transport/sync`, `/transport/clickWhileRecording`, `/logicClock/currentTempo|locator|songLength`,
`/mixerLevels`.

## 2. Connection sequence (Logic side)
`LgLogicRemoteController -didConnectToPeerID:` runs, on the main queue, block
`FUN_01699828`:
1. tells the router about the peer;
2. for every registered Remote control-surface object bound to this peer, runs the
   feedback refresh `FUN_00efe9b4` (a full re-send of surface feedback);
3. calls a "send everything" routine on the controller with the current song;
4. if the peer's **protocol version is < 10**, shows "The version of Logic Remote on
   … needs to be updated …" and calls a disconnect handler.

→ A client must report a protocol version ≥ 10. This matches the Bonjour TXT
`/protocolVersion=10` that Logic itself advertises (architecture.md §3.1). Whether the
client's version travels as `/protocolVersion` is a hypothesis (medium: the constant
exists and the check reads a per-peer version).

## 3. The state dictionary and its change mask
`-_addGInstAndTrackFaderStatesDictForInstWithID:trackID:pSong:changedMask:`:
- creates/updates a per-instrument dictionary keyed by `NSNumber(instID)` and fills:
  `vL` if `mask == 0` or bit 0; `s` if `mask == 0` or bit 13; `m` if `mask == 0` or any of
  bits 12/14; and, into the track dictionary, `r` if `mask == 0` or bit 2.
- **`changedMask == 0` includes every key.** It is the "full" mode; non-zero masks
  produce partial updates.
- `-collectGInstFaderStatesForInstID:changedMask:` with `instID == 0xFFFFFFFF` visits
  all instruments; `-handleUpdateBits:` consumes `updateBitsArray` change
  notifications and calls the per-element handler, i.e. incremental updates.
- `-sendCollectedGInstAndTrackFaderDataIfNeeded` builds `{g: instDict, t: trackDict}`
  and sends it as `/gtFaderData` **over TCP** (`useTCP: 1`), only if either dictionary
  is non-empty.

`vL` encoding seen in code: `(int8 at +0x8b) << 24`, i.e. a signed byte in the high
8 bits (not yet tied to dB).

## 4. Transport
- `-setHeaderState:` stores a 64-bit value and, **only when it changed**, sends
  `/transport/headerState` with an integer.
- `-updateTransportButtonStates` reads `transportStopButtonStateForSong:` and calls two
  selector stubs (`FUN_01ba7fa0`, `FUN_01ba7f20`) that were not resolved to message
  names. Hypothesis: they send `/transport/stopButtonState` and
  `/transport/playButtonFlags`. Confidence: medium. Not verified.

## 5. Constraint recorded: an initial snapshot is not a complete state
Observation reported by the project owner from a live Logic Remote-style session
(not reproduced by me; no capture in the repo): the first response omits state
entries whose value is 0.

Static side:
- the function in §3 emits all keys when `changedMask == 0`, so **it is not what omits
  zeros**. The omission must happen elsewhere (which entries are enumerated and
  collected, the per-element handlers, or serialization). Mechanism: **unknown**.
- Consequences for any client or for logicctl: treat an absent key as "not reported"
  (unknown), never as 0 / off; build state from the initial reply **plus** later
  incremental updates; never mark a write `verified` from a snapshot in which the
  field is merely absent.

Next validation experiments (in order):
1. Static: decompile `FUN_00efe9b4` (feedback refresh) and the per-element handler
   called from `handleUpdateBits:` (`FUN_01b407c0` is a selector stub — resolve it).
2. Static: locate where `/ati`, `/sti`, `/trackSelectionStates` dictionaries are built
   and whether zero-valued members are skipped there.
3. Dynamic (needs a real Logic Remote or our own MPC peer): capture the first reply and
   a mute ON/OFF update of one track; compare keys present before/after.

## 6. Correction to SA-002
`Logic Remote.bundle` `_CSFeedback` is **not** the message builder: it returns the
feedback type of an Assign (`0` if the table entry's pointer at `+0x30` is null, else the
value at `+0x38`, default 8). The extractor `Tools/ghidra/remote_table.py` prints the
word at `+0x18` as "flags"; its meaning is unverified. Entries therefore carry at least a
feedback pointer (`+0x30`) and feedback type (`+0x38`) that SA-002 did not decode.
