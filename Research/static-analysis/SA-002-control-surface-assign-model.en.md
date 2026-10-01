# SA-002: Control-surface plug-ins share one Assign model; Logic Remote app-layer framing

[日本語](SA-002-control-surface-assign-model.md) | [English](SA-002-control-surface-assign-model.en.md)

| Field | Value |
|---|---|
| Date | 2026-10-01 |
| Logic | 12.3.1 (6682) |
| Binaries (arm64 slices) | `PlugIns/MIDI Device Plug-ins/{Logic Control,Logic Remote,TouchOSC}.bundle`, `Frameworks/MACore.framework/Versions/A/MACore` |
| Tool | Ghidra 12.1.4 headless (`Tools/ghidra/analyze.sh`); tables rebuilt with `Tools/ghidra/switch_table.py`, `Tools/ghidra/remote_table.py` |
| Derived tables | `Research/protocol/cs-assign-{mcu-switches,remote,touchosc}.tsv` |

## 1. Assign records are built by every surface plug-in
- Logic Control `DDESCR_LC::FillTemplate(Assign*, TControlID, unsigned char)` and
  the `_CSDefault` of Logic Remote and TouchOSC all call
  `AssignSerializedCore::Init`, which lives in **MACore** (imported as
  `@rpath/MACore.framework/.../MACore::AssignSerializedCore::Init`; MACore
  exports only `AssignHeader::Init` and `AssignSerializedCore::Init`).
- Fields written by all three (offsets into the serialized Assign):

| Offset | Size | Written from | Meaning (hypothesis) |
|---|---|---|---|
| +0x3a | int | MCU switch-info `+0xc`; Remote/TouchOSC entry `+0x00` | kind |
| +0x3e | short | MCU strip index / Remote entry `+0x04` | sub (strip offset, or command number for kind 9) |
| +0x40 | int | MCU switch-info `+0x10`; Remote entry `+0x08` | param |
| +0x52 | int | `TControlID` (MCU) / table index (Remote) | control id on the surface |
| Init() result | bytes | MCU: `01 03 90 <note> F5`, `E0|n …` | input message template (MIDI) |

## 2. Shared numbering
kind 5 = channel-strip parameter (bank-relative). Params per table:

| Param | Logic Remote | TouchOSC | Logic Control (MCU) |
|---|---|---|---|
| 3 | `/cs/mixer/solo/` | `/1/solo` | — |
| 7 | `/cs/mixer/volume/volume`, mastervolume (sub 20480) | `/1/volume` | faders (FillTemplate writes 7) |
| 9 | `/cs/mixer/mute/`, mastermute | `/1/mute` | — |
| 10 | `/cs/mixer/volume/pan` | `/1/pan` | — |
| 28–35 | `/cs/mixer/sends/send1…8` | `/2/sendlevel/1…` | — |
| 56–67 | — | `/2/insertbypass/…` | — |
| 128 | — | — | `Ch. n Mute` |
| 129 | — | — | `Ch. n Solo` |
| 259 | `/cs/mixer/select/` | `/1/select/1/1` | `Ch. n Select` |
| 260 | `/cs/mixer/record/` | `/1/recenable` | `Ch. n Record/Ready` |
| 264 | `/cs/mixer/automation/` | — | `Read/Off` |
| 288–295 | `/cs/mixer/sends/sendbypass1…8` | — | — |
| 528–551 | — | `/3/frq/…`, `/3/gain/…` (EQ) | — |

Other kinds in the Logic Remote table: 9 = command with `sub` as command number
(`/cs/transport/stop` 5, `/cs/transport/play` 3, `/cs/transport/cycle` 15,
`/cs/transport/record` 7, `/cs/transport/click` 474, `/undo` 761, `/redo` 796,
`/duplicateTrack` 1728, `/cs/transport/track-`/`+` 1272/1273,
`/transport/marker-`/`+` 1330/1329, solo/mute reset 1040/1041);
10 = bank navigation; 1 = page; 2/3 = group headers; 0 = display-only feedback
(`/cs/mixer/trackname`, `/cs/mixer/level`, `/cs/mixer/panval`).

Hypotheses:
- H1: kind 5 + param is Logic's channel-strip parameter space shared by all
  control surfaces (volume 7, pan 10, select 259, rec 260, automation 264).
  Confidence: **high** for 7/259/260/264 (three independent tables agree);
  medium for the rest. Counterexample: mute/solo are 9/3 in Remote and
  TouchOSC but 128/129 in MCU — two parameter variants (e.g. toggle vs value)?
- H2: kind 9 `sub` values are Logic key-command IDs. Confidence: medium
  (Logic.framework has `/keyCommand/actionNum`; not yet linked).
- Both are candidates for the brief's §16 "common command/state representation".

## 3. Logic Remote application framing (MACore `MAPeerRouter`)
`MAPeerRouter::processReceivedData:fromPeer:` (called from
`session:didReceiveData:fromPeer:`):
- byte 0 = format: bit 7 set → payload is compressed (`-[NSData maUncompressedData]`);
  low 7 bits: **4 = JSON** (`NSJSONSerialization`), **1 = property list**
  (`NSPropertyListSerialization`), otherwise `NSKeyedUnarchiver` with a class
  allow-list.
- bytes 1… = payload. Decoded object: **NSArray** → `routeMultipleMessagesArray:fromPeer:`
  (ordered); **NSDictionary** → for each key/value → `routeMessage:withArgument:fromPeer:`
  (key = OSC-style address, value = argument).
- `MAPeer` carries `protocolVersion` and `supportsJSON`; the router waits for the
  peer's protocol version (`waitForProtocolVersionIfNeededForPeerWithID:`).
- Control-surface traffic is bridged by `CPlugInUserCommunicator_OSC(_ObjcBridge)`
  (`routeOSCMessage:withArgument:`, `sendOSCMessage:withArgument:`), which also
  carries plug-in parameter traffic (`SetParameterFloatingValue`,
  `BroadcastParameterValueChange`, `GetParameterInfo`, …).

Hypothesis H3: a Logic Remote message on the MPC session is
`<1 byte format><JSON or plist of {"/cs/…": arg}>`.
Confidence: medium (static only). Next validation: capture with a real Logic
Remote, or connect our own MPC peer once the MPC transport is reproduced.

## Next
- Logic.framework (running): find who consumes Assign kind 5/9 and where
  `routeMessage:withArgument:` lands (`LgLogicRemoteMessageRouter`).
- `maUncompressedData` algorithm.
- Resolve H1's mute/solo variants and H2 (key-command IDs).
