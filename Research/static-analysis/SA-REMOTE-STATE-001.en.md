[日本語](SA-REMOTE-STATE-001.md) | [English](SA-REMOTE-STATE-001.en.md)

# SA-REMOTE-STATE-001: How Logic sends state to Logic Remote — the initial send and deltas

| Item | Value |
|---|---|
| Date | 2026-10-02 |
| Logic | 12.3.1 (6682), macOS 27.0 |
| Target (arm64) | `Logic.framework` (`LgLogicRemoteController`, arm64-only `2f141e1a…`), the `Bg*` constants of `MACore.framework` (arm64 slice `99a4a9ad…`) |
| Method | **Static analysis only.** Targeted Ghidra 12.1.4 decompilation (`Tools/ghidra/query.sh`). Nothing was sent to Logic and no connection was made |
| Output (local only) | `Research/raw/ghidra/q-p6-state.c`, `q-p6-state2.c`, `q-p6-fader.c`, `q-p6-type.c`, `q-p6-stubs*.c` |
| Related | [SA-005](SA-005-logic-remote-state-push.en.md) (overview of state sending) · [SA-REMOTE-SESSION-001](SA-REMOTE-SESSION-001.en.md) (connection) · [SA-REMOTE-FRAME-001](SA-REMOTE-FRAME-001.en.md) (frames) |
| Machine-readable | [`Research/protocol/logic-remote-state.schema.json`](../protocol/logic-remote-state.schema.json) |
| Plan | The **static part** of PLAN-06. The receive experiment needs PLAN-05 (awaiting approval) and has not been done |

**Confidence convention:** a fact that matches the decompiled code is "confirmed"; an inference from it is a "hypothesis".
Nothing was confirmed on a real connection. The "evidence" in the tables is function addresses in `Logic.framework`.

## 1. Key points

1. **The initial send is not a separate mechanism; it runs the delta handlers once.** After a connection,
   `sendWakeupMessageInSong:activeSongChanged:` (0x016843b8) calls the delta `handleUM_*:` handlers with a `nil` argument (§3).
   There is no need to learn separate schemas for the initial send and for deltas (confirmed).
2. **The same address can arrive twice in a row.** During the initial send, `/ati` and `/allTrackCount` / `/trackCount`
   are sent again from a second path (§3.2). A receiver should tolerate resends with the same content (hypothesis; not confirmed on the wire).
3. **`/ati` is not "an array of per-track dictionaries" but 13 parallel arrays.** Elements at the same index describe the same strip (§4).
4. **The `/gtFaderData` dictionaries do not omit a value of 0** (`r` is present only when its target could be looked up). The only 0-omission found is the initial pass of `keyCommandStateSetup:` (§7; confirmed, but in code only).
5. **The argument of `/sti` and `/trackSelectionStates` is an NSKeyedArchiver byte string.** `/sti` is additionally compressed as MAZP (§5; confirmed).

## 2. Functions that send state

| Role | Function | Address |
|---|---|---|
| Initial send (connection, song change) | `sendWakeupMessageInSong:activeSongChanged:` | 0x016843b8 |
| Build and send the track list | `sendChannelStripInfo:` (the no-argument form is 0x0168dcf4) | 0x0168d478 |
| Fill in one strip (block) | `FUN_01696ebc` | 0x01696ebc |
| Send `/ati` (only on change) | `setAllTrackInfo:` | 0x016867b4 |
| `/allTrackCount`, `/trackCount` (only on change) | `setAllTrackCount:mixerTrackCount:` | 0x01686564 |
| Entry of the delta path | `handleUpdateBits:` → `handleUpdateBitsForElement:` | 0x0168a450 / 0x0168a610 |
| Collect fader state | `collectGInstFaderStatesForInstID:changedMask:` | 0x0168c9e0 |
| Dictionary for one instance | `_addGInstAndTrackFaderStatesDictForInstWithID:trackID:pSong:changedMask:` | 0x0168c304 |
| Send `/gtFaderData` | `sendCollectedGInstAndTrackFaderDataIfNeeded` | 0x0168ccdc |
| Selected track | `updateSelectedTrackInfo` / `sendSelectedTrackInfo` | 0x0168e754 / 0x0168e3fc |
| Selection state | `sendTrackSelectionStates` | 0x0168e508 |
| Clock | `handleUM_CLOCK:` | 0x0168f314 |
| Play-button flags | `handleUM_PLAY_BUTTON_FLAGS_CHANGED:` | 0x0168f238 |
| Song change | `handleUM_SONG:` | 0x0168ac84 |
| Whether a song is open | `_sendDocOpen:` | 0x01689c18 |

The small functions Ghidra calls `FUN_01bXXXXX` are Objective-C message-send stubs.
Each stub just names one selector and calls `objc_msgSend`, so decompiling the stub's address reveals the selector
(about 70 were resolved in this work; the procedure is in §9).

## 3. Order of the initial send (confirmed)

In the order `sendWakeupMessageInSong:activeSongChanged:` calls them. The names are those resolved from the stubs.

| # | What is sent / called | Notes |
|---|---|---|
| 1 | Discard pending fader data (`setCollectedGInstFaderData:nil`, `setCollectedTrackFaderData:nil`) | Do not carry old deltas over |
| 2 | `/mixer/hideRecordButtons`, `/mixer/automationEnabled` | From the song's settings if there is a song; defaults otherwise |
| 3 | `setMagicMentorActive:`, `setChordTrainerActive:` | Internal state setters |
| 4 | `/hostType`, `/hostLocaleIdentifier` | The host type and locale identifier |
| 5 | `sendChannelStripInfo` | First sets the `/ati` cache (+0xc0) to `nil`. Contents are **5a–5f** below. §4 |
| 6 | `/allTrackCount`, `/trackCount`, `/undoLabel`, `/redoLabel` | The counts are `allTrackCount` / `mixerTrackCount` |
| 7 | `/ati` (`useTCP: 1`) | Sends the content of `allTrackInfo` once more |
| 8 | `sendMIDIMonoStateForSong:` | MIDI mono state |
| 9 | `setMarkerList:nil` and **`handleUM_MARKER:` `SYNC:` `FORMAT:` `CHSIGNTIME:` `LOCAT:` `VCLOCKSIGNAT:` `CHLEN:` `RULERCHANGED:` `CLOCK:`** (all with `nil`) | Calls the delta handlers as they are |
| 10 | `/keyCommand/currentLogicLocale`, `/tron/loops/setPreviewVolume` | |
| 11 | `handleUM_GLOBALPREFS:`, `handleUM_AUDIOPREFS:` (`nil`), `dimValueChanged:` | |
| 12 | `updateActiveGInstSet:`, `sendSelectedTrackInfo` (→ `/sti`, §5), `updateNoteRepeat`, `sendBgSongSettings:` | |
| 13 | `/transport/stopButtonState`, `/transport/headerState`, `/transport/clickWhileRecording`, `/transport/playButtonFlags` | §6 |
| 14 | `dismissAlert`, `_sendDocOpen:` (passes whether a song is open), `updateLTPorChordTrainerStatus`, `updateRecallSoloState`, `updatePeakHold`, `updateReturnSpeed` | |
| 15 | `/colorIndexMap` | A table of colour numbers |
| 16 | `sendTronFlags:`, `sendCurrentGridFocusInfo`, `sendStepSequencerRegionInfoToRemote…`, `sendSendsOnFaderChangeMessage` | |
| 17 | One call on `tronMessageRouter`, only when `activeSongChanged` is true | Not analysed |

The order inside `sendChannelStripInfo:` (confirmed; the breakdown of row 5):

| # | What is sent / called |
|---|---|
| 5a | Send the per-strip extra messages (§4.3) as one batch. Nothing is sent if the batch is empty |
| 5b | `setAllTrackCount:mixerTrackCount:` → when the counts changed: `/allTrackCount`, `/trackCount`, `/mixerLevels/resetAll`, `/bankNavigator/trackLevels/resetAll` (the last two with a `nil` argument) |
| 5c | `setAllTrackInfo:` → `/ati` (first copy) |
| 5d | `handleUM_TRACKSEL:nil`, `_sendArpState`, `updateNoteRepeat`, `sendTrackSelectionStates` (→ `/trackSelectionStates`) |
| 5e | `collectGInstFaderStatesForInstID:0xFFFFFFFF changedMask:0` (collect all instances, all fields) |
| 5f | `sendCollectedGInstAndTrackFaderDataIfNeeded` → `/gtFaderData` (§8) |

`/gtFaderData` and `/trackSelectionStates` do not appear in the upper table; both are sent inside `sendChannelStripInfo:` (5d–5f).
**`/gtFaderData` should arrive after the first copy of `/ati` and before the second** (order in the code; not confirmed on the wire).

### 3.1 What "initial send = one pass of the deltas" means

Row 9 calls the delta handlers for the clock, time signature, locators, markers and so on with a `nil` argument.
The handlers read **Logic's current values**, not the notification's `userInfo`, so a `nil` argument still sends the current values
(hypothesis; confidence: medium. It was confirmed that `handleUM_CLOCK:` does not use `param_3` and reads the song directly).
So the initial send and the deltas of the **clock and transport share one schema**.

### 3.2 Possible duplicates (hypothesis)

- `sendChannelStripInfo` ends by calling `setAllTrackInfo:`. That method sends `/ati` only when it differs from last time,
  but row 5 sets the cache to `nil` first, so it always sends. Row 7 sends the same content once more.
- `setAllTrackCount:mixerTrackCount:` sends `/allTrackCount` and `/trackCount` only when the counts changed.
  Row 6 sends them unconditionally.
- Both pairs should carry **the same content**, but this is not confirmed on the wire. A client should take "the last one received" as authoritative and not treat a duplicate as an error.

### 3.3 A song change (confirmed; the details of the branches are not worked out)

`handleUM_SONG:` (0x0168ac84) handles the song notification as follows.

1. When the notification kind is not 0xd0, it sets an internal global (`DAT_0276e2a0`) to 0.
2. It looks up the "active song" (the song record whose byte at +0x85c is 1) before and after the notification.
3. **When the active song changed** (a song became active, or another song replaced it):
   - It reloads the document's workspace and mappings (`reloadWorkspaceAndMappingsInDocument:avoiding:`).
   - **Unless tracks are being imported** (`isImportingTracks`), **it calls `sendWakeupMessageInSong:activeSongChanged:` for the new song with `activeSongChanged = YES`.**
     So the initial send of §3 **runs through once more** (the `/ati` cache is cleared too, so `/ati` is sent again).
   - If there was no active song before, it also sends `/docOpen` = true.
4. When there is no active song any more: it sends `/docOpen` = false and sets the stored reference to the song (+0x38) to 0.

`/docOpen` (`_sendDocOpen:`) is a boolean, sent **once over UDP and once over TCP**: the same value arrives twice.

Implications (hypothesis; confidence: medium):

- On a song switch, **nearly all state is sent again**. A client has to drop the old song's tracks, fader values and so on, and rebuild from the new `/ati` onward.
  No end-of-send marker was found, so it is not known when the rebuild has finished.
- A connection (a reconnect included) also calls the same function for its initial send, with `activeSongChanged = NO` (§3.4).
- During a switch while tracks are being imported, the initial send is not called. What is sent in the meantime is not confirmed.

### 3.4 When a peer connects (confirmed)

The order in the block that `didConnectToPeerID:` runs (`FUN_01699828`):

1. Call the router's `waitForProtocolVersionIfNeededForPeerWithID:`. **If the peer's version has not arrived, it waits here** (up to about 2.5 s; SA-REMOTE-SESSION-001 §5; taken as 6 if it never arrives).
2. For each object of Remote's control surface tied to this peer, run a feedback refresh (`FUN_00efe9b4`).
3. **Only when a song is open**, call `sendWakeupMessageInSong:activeSongChanged:` for that song with **`activeSongChanged = NO`**. With no song open this call does not happen.
4. Afterwards, check the peer's version and, **if it is below 10**, show the alert "Logic Remote needs to be updated" and call the disconnect handling.

So the order in the code is "wait for the version → initial send → version check". **A peer whose version is below 10 (including one taken as 6 because it never arrived) should still get the initial send before it is disconnected** (hypothesis; confidence: medium; read from the order in the block, not confirmed on the wire).
The difference from a song change (§3.3) is that `activeSongChanged` is NO (the call of row 17 of the table in §3 does not happen).

## 4. `/ati` — information about all tracks

`setAllTrackInfo:` sends an `NSDictionary` as it is under `/ati` (`useTCP: 1`). **It does not send if the dictionary equals the previous one** (confirmed).
The dictionary has 13 keys, each holding an **array of the same length**. The elements at index *i* all refer to the same strip (confirmed: the block appends one element to each of the 13 arrays per strip).

| Key (wire value) | Array element | Source of the value (confirmed) | Meaning / range |
|---|---|---|---|
| `c` | dictionary `{nc, sc, tnc, tsc}`, each a 4-byte `NSData` | colour computation (four colours) | normal / selected / icon normal / icon selected colours. **The byte order of the 4 bytes is not confirmed** (one of the colours starts with 0xFF) |
| `n` | dictionary `{"name": string, "gindex": integer}` | the track name and the strip info's `identifier` | `gindex` is the **same value** as the keys of `g` in `/gtFaderData` (§8; confirmed: same accessor on the same kind of object; not confirmed on the wire) |
| `t` | integer (`char`) | `trackTypeForTrack:seqID:ginst:inSong:` (0x01693e90) | **can return 0–10**. The meaning of each value is **unresolved** (§10) |
| `nc` | integer | one byte (+0xd4) of the **song**, looked up in the 15-entry table `DAT_01d59030`. 0 if there is no song | number of channels (from the key name; hypothesis. The source is a song-level value, not per strip, so doubts remain) |
| `p` | integer (`char`) | only when bit 27 of `allowedElementsForStrip:` is set, a table lookup from song settings (one of 0, -5, -1, -4, -1, -4). Otherwise -1. With no song, one of two constants depending on whether `t` is 4 (values unresolved) | pan type (from the key name; hypothesis) |
| `tn` | integer | `numberOfStrip:`; -1 when that is 0 | strip number (from the key name; hypothesis) |
| `BgTrackInfoTrackIDKey` | integer (long) | `(folder << 16) \| (track & 0xffff)` | track ID (low 16 bits = track, upper = folder). Lifetime **not confirmed** (PLAN-08) |
| `BgTrackInfoTrackUUIDKey` | string | the track's UUID (`CUUIDBase::CreateStringConst`); a short default string if unavailable (content not confirmed) | |
| `BgTrackInfoIconIDKey` | integer | a 16-bit value inside the strip (+0x7e) | icon number (from the key name; hypothesis) |
| `BgTrackInfoHasArrangeKey` | boolean | position matching | "also exists on the arrange side" (from the key name; hypothesis) |
| `BgTrackInfoArrangeHiddenKey` | boolean | computed from the parent's kind and similar | "hidden in the arrange" (from the key name; hypothesis) |
| `BgTrackInfoCollapsibleInfoKey` | integer | `_collapsibleInfoForTrack:parentMSeq:` (0x0168d3a8) | §4.2 |
| `BgTrackInfoMetaInfoFlagsKey` | unsigned integer | `trackMetaInfoFlagsForTrack:spu:inSong:` (0x016944e4) | 0 or 1: bit 5 of the 32-bit value (+0x84) of the third argument (`spu`); 0 if there is no `spu`. The `/ati` block passes the song object, so the value **may be the same for every strip** (hypothesis; confidence: medium) |

Some keys have a wire value that differs from the constant's name, others do not ([`logic-remote-wire-keys.tsv`](../protocol/logic-remote-wire-keys.tsv)).
The eight keys that start with `BgTrackInfo…` have wire values equal to their constant names (confirmed; MACore constants).

### 4.1 How the columns were matched

Inside `FUN_01696ebc` the arrays are reached through the block's captured variables (`param_5 + offset`).
When `sendChannelStripInfo:` creates the block it packs the captured variables in a fixed order.
The columns above were decided by matching that order (+0x20, +0x28, …) with the order of the values passed finally to `dictionaryWithObjects:forKeys:count: 13`.
The other captured offsets — +0x48 = the caller (self), +0x58 = the mixer controller, +0xb8 = the song, +0xc0 = the number of mixer strips —
agreed with their use inside the block (a cross-check).

### 4.2 Decomposing `CollapsibleInfo` (hypothesis; confidence: medium)

The return value of `_collapsibleInfoForTrack:parentMSeq:` is made of these bits (an expression read from the code).

| Bit | Content |
|---|---|
| 0–7 | nesting depth of the track (the byte at +0x12 of the track record) |
| 8 | bit 7 of the byte at +0x14 of the track record |
| 9 | the next row's depth equals "this depth + 1" (reads as **has children**) |
| 10 | bit 6 of the byte at +0x14 of the track record |

The meaning of bits 8 and 10 is **unknown**.

### 4.3 Per-strip extra messages (confirmed)

Besides the 13 arrays of `/ati`, the block collects **per-strip messages** in one dictionary (the `self` of `sendChannelStripInfo:`).
When it is full they are **sent together** with `MAPeerRouter`'s `sendMessages:toPeer:useTCP:completion:`.
Only strips for which the argument block (it takes a track ID and returns a boolean) returns true are included.

| Address | Argument | Notes |
|---|---|---|
| `/mixer/plugins/audio/%lu`, `/mixer/plugins/midi/%lu` | NSKeyedArchiver bytes (plug-in list) | integer 0 if there is no list |
| `/mixer/eq/state/%lu` | integer 0 / 1 / 2 | 0 = no EQ, 1 = bypassed, 2 = active (the code sets 2 when the `bypassed` output of `pathPointsForEQThumbnailOfStrip:bypassed:` is false; confirmed) |
| `/mixer/eq/path/%lu` | NSKeyedArchiver bytes (EQ curve points) | when there is an EQ |
| `/mixer/plugins/slotbase/%lu` | integer 0 / 1 | 1 when the strip's kind is 1 |
| `/mixer/io/inputname/%lu`, `outputname/%lu` | dictionary `{LgInputNameKey etc.: name, …BypassedKey: boolean}` | `NoInput` / `NotAssigned` is put in when the name is empty. The boolean is true when "the original name is not empty"; whether that agrees with the key name (Bypassed) is **not confirmed** |
| `/mixer/io/inputgain/%lu` | dictionary `{LgInputGainDBKey: dB, LgInputGainKey: gain}` (floating point) | |
| `/mixer/io/hasPhantomPower/%lu`, `phantomPower/%lu`, `hasHighPassFilter/%lu`, `highPassFilter/%lu`, `hasPhaseInvert/%lu`, `phaseInvert/%lu` and others | boolean | |

- The value substituted for `%lu` cannot be seen in the decompilation (variadic arguments). The delta side (§8) builds messages of the same kind with `%i` and uses `updateBitsInstID` (the instance ID).
  The two are presumed to **format the same ID with different integer widths** (hypothesis; confidence: medium).
- Which strips get these extra messages is decided by the block passed to `sendChannelStripInfo:`. The no-argument form (0x0168dcf4) passes a global block.
  The body of that block is **not analysed**, so "which strips get them" is unknown.

## 5. `/sti` and `/trackSelectionStates`

### `/sti` (information about the selected track)

- `updateSelectedTrackInfo` (0x0168e754) builds the dictionary and `setSelectedTrackInfo:` (0x0168df54) compares it with the previous one.
  `sendSelectedTrackInfo` (0x0168e3fc) sends **only when it differs** (confirmed).
- Contents of the dictionary (confirmed):

  | Key | Value |
  |---|---|
  | `n` | the track name; `NoTrackSelected` when nothing is selected |
  | `t` | integer (`char`): the byte at +3 of the selected track's internal record. **A different computation from the `t` of `/ati` (`trackTypeForTrack:…`)**, so the range is not necessarily the same |
  | `BgTrackInfoMetaInfoFlagsKey` | unsigned integer: `trackMetaInfoFlagsForTrack:spu:inSong:` (the same function as in `/ati`) |
  | `tn` | integer (source not worked out; from the key name, the strip number; hypothesis) |
  | `BgTrackInfoShowArpeggiatorButtonKey` | boolean: whether to show the arpeggiator button for the selected track |
  | `BgTrackInfoIndexKey` | integer: the strip index returned by `getStrip:forTrackWithID:`; `NSIntegerMax` (0x7fffffffffffffff) if not found |

  When nothing is selected, `n` = `NoTrackSelected` is sent together with `t`, `BgTrackInfoMetaInfoFlagsKey`, `tn` and `BgTrackInfoIndexKey` (their values are not worked out).

- To send, the dictionary is turned into bytes with `NSKeyedArchiver` and then compressed with `maCompressedDataWithCompressionLevel:9` (confirmed; the selector name was resolved from the stub).
  This compression is presumed to be the **MAZP container** of [SA-REMOTE-FRAME-001](SA-REMOTE-FRAME-001.en.md) (hypothesis; confidence: medium).
  It is a different layer from the compression of the whole frame (bit 7 of the leading tag). So the argument of `/sti` is **a byte string inside a frame that is itself MAZP**.
- Right after sending it calls `_sendArpState`, `updateNoteRepeat` and `sendTrackSelectionStates` (confirmed).

### `/trackSelectionStates`

- `sendTrackSelectionStates` (0x0168e508) sends the dictionary `{"PreviousTrackKey": boolean, "NextTrackKey": boolean}` (the wire values were resolved from MACore's constants)
  as NSKeyedArchiver bytes (confirmed; **not compressed**).
- The two booleans are the result of evaluating the states of key-command IDs `0x4f8` / `0x4f9` (true when `!= 0`).
  When the command is not enabled (the global flags `DAT_02686180/81` are not true), it does not evaluate and sends **always true** (confirmed).
  From the key names this is presumed to mean "can move to the previous / next track" (hypothesis; confidence: medium).

## 6. Transport and clock

| Address | Argument | Sent when (confirmed) | Notes |
|---|---|---|---|
| `/transport/stopButtonState` | integer | initial send (row 13); deltas via `updateTransportButtonStates` | meaning of the values unresolved |
| `/transport/headerState` | integer | initial send; deltas via `setHeaderState:` **only on change** (SA-005) | ditto |
| `/transport/clickWhileRecording` | boolean | initial send; deltas via the setter | |
| `/transport/playButtonFlags` | `char` (global `DAT_02765b85`) | initial send and `handleUM_PLAY_BUTTON_FLAGS_CHANGED:` | The "0x0168f238" of SA-005 §4 is this function. It **only sends the button flags**; it does not build them |
| `/logicClock/spl` | `long long` | `handleUM_CLOCK:` (`useTCP: 0` = UDP) | sample position (from the key name; hypothesis) |
| `/logicClock/currentTempo` | integer | `handleUM_CLOCK:` (UDP) | unit not confirmed (BPM itself, ×100, and so on) |
| `/multiTempo` | boolean | `handleUM_CLOCK:` (UDP) | **mind the direction of the value** (below) |

Caution on `/multiTempo`: the code walks the song's tempo list and **sends 1 if it finds no element whose value differs** (0 as soon as it finds a different one).
The name suggests "there are several tempos", but the shape of the code is the opposite (1 = all the same).
**Which is right (the name, or my reading) is not confirmed.** Whether what is compared really is the tempo value is also not confirmed. Do not base decisions on this value until it is checked on the wire.

`handleUM_PLAY:` (0x0168f0dc) sends `{<constant>: 0}` under `/keyCommandStateUpdate`, except when the notification kind is 0x85 / 0xdd and an internal value (`local_70`) is non-zero.
For other kinds it also sets an internal global (`DAT_0276e2a0`) to 0.
The key (a constant) is unresolved; it looks like a reset of a key-command state to 0, not the play state itself (hypothesis; confidence: low).

The only messages known to carry the **actual play / record state** are the four `/transport/*` messages above.
Interpreting their values belongs to [SA-AE-STATE-002](SA-AE-STATE-002-native-transport-state.en.md) and is not covered here.

## 7. Handling of the value 0 (continuing SA-005 §5)

| Path | Omits 0? | Evidence |
|---|---|---|
| `vL` `s` `m` `ip` of `/gtFaderData` | **No.** With `changedMask == 0` they are always put in as `NSNumber` (even when the value is 0) | `_addGInstAndTrackFaderStatesDict…` (0x0168c304): `numberWithInt:0` is passed to `setObject:forKeyedSubscript:` |
| `r` of `/gtFaderData` | put in only when the record-enable target could be looked up (otherwise the key itself is absent) | same; skipped when the result of `FUN_001a1dcc` is empty |
| the target of `/gtFaderData` itself | if the instrument cannot be looked up (`FUN_01a15c7c` is empty), the instance is **omitted entirely** | `return` at the start of the same function |
| the 13 arrays of `/ati` | No (one element is always appended) | the block |
| `keyCommandStateSetup:` (initial, `/keyCommandStateUpdate`) | **0 is not sent** | 0x01683ad8: if the value is 0, no dictionary is built and it moves on |
| `keyCommandStateChanged:` (delta) | **0 is sent too** | 0x0168e1d4 |

So omission happens **only in the initial pass of key commands**, not in `/ati` or `/gtFaderData` (confirmed in code).
However, even if a value is in the sender's dictionary, **whether it is dropped during framing or receiving can only be checked on the wire**.

## 8. `/gtFaderData` — structure and deltas (a supplement to SA-005 §3)

```
/gtFaderData = {
  "g": { <instID:integer>: { "vL": integer, "s": integer, "m": integer } , … },
  "t": { <trackID:integer>: { "r": integer, "ip": integer } , … }
}
```

- The keys of the inner dictionaries are `NSNumber`. Since plist and JSON only have string keys, this dictionary is presumed to be sent as an NSKeyedArchiver (format 2)
  ([SA-REMOTE-FRAME-001 §4](SA-REMOTE-FRAME-001.en.md); hypothesis).
- `trackID` is the same value as `BgTrackInfoTrackIDKey` of `/ati` (`(folder << 16) | track`; `getOrCreateTrackDict:` uses it as the key via
  `numberWithLong:`; confirmed).
- `instID` is the `identifier` of the mixer strip info. The `gindex` in `n` of `/ati` is the same `identifier` of the same kind of object.
  Both enumerate the elements of `consolidatedChannelStrips` (`/ati` through `consolidatedChannelStripsAndGetMixerStripCount:`, the fader side through `consolidatedChannelStrips`),
  and the delta side's `updateBitsInstID` is also passed to `getStrip:forGindex:`.
  So `gindex` = `instID` can be assumed (confirmed in code; confidence: medium to high; not confirmed on the wire).

### 8.1 The change mask and the fields

| Bit of `changedMask` | Field | Value (confirmed / hypothesis) |
|---|---|---|
| 0 | `vL` (`g`) | 32-bit integer: `(int8)(+0x8b) << 24`, unless the top byte of the internal 32-bit value (+0xcc) agrees with it, in which case that value is used as it is (confirmed). **A signed 32-bit representation of the fader position** (hypothesis). Not the MCU's 14 bits; the conversion is not confirmed |
| 13 | `s` (`g`) | signed byte at `+0x8c`. Range **not confirmed** (values other than 0 / 1 are possible) |
| 12, 14 | `m` (`g`) | basically 0 / 1, sometimes 2 / 3: when bit 1 is set, or under particular conditions (presumed to be the effect of groups and the like). The global flag `DAT_0261e118`, when true, adds 0x80. **Meaning not confirmed** |
| 2 | `r` (`t`) | one of 0, 1, 3, 0x40, 0x80 (from the branches in the code). The kind of record-enable (from the key name; hypothesis) |
| 32 | `ip` (`t`) | a mask of up to 12 bits. Bit *k* is the internal flag (bit 2 of +0x3a) of channel *k* (confirmed). "Independent pan" from the key name (hypothesis) |

- `changedMask == 0` includes every field (confirmed in SA-005 §3).
- The delta entry `handleUpdateBitsForElement:` calls `collectGInstFaderStatesForInstID:changedMask:` when `updateBitsValue` contains any of the bits of `0x100007005` (0, 2, 12, 13, 14, 32)
  and `updateBitsInstID != -1` (confirmed).
  So **the change bit of each field matches the five rows above**.
- Collected values accumulate in two dictionaries on the controller (+0x100 = `g`, +0x108 = `t`). `sendCollectedGInstAndTrackFaderDataIfNeeded` sends them as **one `/gtFaderData`**
  only if either dictionary is non-empty and the connection is valid (`FUN_01b1c480` = `connected`) (confirmed; `useTCP: 1`).
  After sending it empties the accumulators.

### 8.2 Other change bits

`handleUpdateBitsForElement:` sends other messages for other bits (confirmed).

| Bit | What is sent |
|---|---|
| 11 | `/mixer/plugins/audio/%i`, `/mixer/plugins/midi/%i` (plug-in lists, NSKeyedArchiver), `/mixer/eq/state/%i` (integer 1 / 2) |
| 29 | `/mixer/eq/path/%i` (EQ curve points, NSKeyedArchiver) |

`handleUpdateBits:` (0x0168a450) passes each element of the `updateBitsArray` in the notification's `userInfo` to `handleUpdateBitsForElement:`.
It sets `cachedCurrentMixerController` only while processing and clears it afterwards.
`handleUM_TRACKSEL:` (0x0168e0ac) calls `updateActiveGInstSet:` and `updateSelectedTrackInfo`, so **a selection change rebuilds `/sti`**.

## 9. Procedure and reproduction

The analysis procedure (all local; nothing was sent to Logic).

1. Decompile by address with `Tools/ghidra/query.sh Logic.arm64 <output name> 0x… 0x…` ([`XrefDecompile.java`](../../Tools/ghidra/XrefDecompile.java)).
2. For a call shown as `objc_stub::FUN_01bXXXXX`, decompile the stub's address the same way;
   the selector can be read in the form `PTR_s_<selector>_…`.
3. Check string constants against [`logic-remote-wire-keys.tsv`](../protocol/logic-remote-wire-keys.tsv) (MACore's `Bg*`) and
   [`osc-address-strings.tsv`](osc-address-strings.tsv) (address strings in the binaries).
   `/allTrackCount`, `/redoLabel` and a few others are **not listed** in the latter. Their only evidence is the `cf_` label Ghidra assigns (derived from the string's content),
   and the strings themselves have not been verified.

## 10. Unknowns and next steps

| Item | Status | Next step |
|---|---|---|
| Meaning of the values 0–10 of `t` (track kind) | Unresolved. The set of return values was read, but the meaning of the branches is not worked out | Read all the branches and map them to known track kinds (audio, software instrument, folder, and so on). A prerequisite of PLAN-08 |
| The value tables for `p` (pan type), `nc` and `DAT_01d59030` | Not read | Read the contents of the tables |
| Byte order of the 4 bytes of `c` | Not confirmed | Read the colour computation (`FUN_017e5998` and others) |
| Body of the block that the no-argument `sendChannelStripInfo` passes | Not analysed | It decides which strips get the extra messages |
| `gindex` and `instID` being the same value | The same in code (§8); not confirmed on the wire | Cross-check on receipt |
| Direction of `/multiTempo`, unit of `/logicClock/currentTempo` | Not confirmed | Receive experiment |
| Relation of `vL` to dB / MCU fader values | Not confirmed | In the receive experiment, line it up with known dB values (PLAN-02's MCU reads are the comparison) |
| Whether messages that arrive twice carry identical content | Not confirmed | Receive experiment |
| Whether a 0 is dropped during framing or receiving | Not confirmed | Receive experiment |
| What is resent on a song change or reconnect | A song change: §3.3; a connection: §3.4 (both confirmed). What the `tronMessageRouter` call of row 17 does is not analysed | Continue statically; on a real connection, after PLAN-05 |
| A signal that the initial send has finished | **Not found** | Whether the last sends (rows 16 / 17) include a message that marks the end. If not, decide "completeness" another way |

### Rules to apply in the client (logicctl) — a proposal, not implemented

1. Treat only received values as state. **A key that did not arrive is "unknown"**, not 0 / false (as in SA-005 §5).
2. If the same address arrives twice in a row, take the later one. If the contents disagree, record that fact.
3. Since **no end-of-send signal has been found** for the initial send, do not mark a received snapshot `complete: true`. The condition under which completeness may be claimed
   is to be decided by experiment (PLAN-06's receive experiment).
4. The lifetimes of `gindex` / `instID` / track IDs are not confirmed, so do not use them across connections (sessions) (PLAN-08).
5. On receiving `/docOpen`, or when a song change is evident, drop all state of the previous song (tracks, fader values, selection) (§3.3).

This document is not the result of observing a real Logic Remote connection. The receive experiment will be done after PLAN-05 is approved.
