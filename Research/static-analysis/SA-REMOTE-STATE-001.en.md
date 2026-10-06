[日本語](SA-REMOTE-STATE-001.md) | [English](SA-REMOTE-STATE-001.en.md)

# SA-REMOTE-STATE-001: How Logic sends state to Logic Remote — the initial send and deltas

| Item | Value |
|---|---|
| Date | 2026-10-02 |
| Logic | 12.3.1 (6682), macOS 27.0 |
| Target (arm64) | `Logic.framework` (`LgLogicRemoteController`, arm64-only `2f141e1a…`), the `Bg*` constants of `MACore.framework` (arm64 slice `99a4a9ad…`) |
| Method | **Static analysis only.** Targeted Ghidra 12.1.4 decompilation (`Tools/ghidra/query.sh`). Nothing was sent to Logic and no connection was made |
| Output (local only) | `Research/raw/ghidra/q-p6-state.c`, `q-p6-state2.c`, `q-p6-fader.c`, `q-p6-type.c`, `q-p6-stubs*.c` |
| Related | [SA-005](SA-005-logic-remote-state-push.en.md) (overview of state sending) · [SA-REMOTE-SESSION-001](SA-REMOTE-SESSION-001.en.md) (connection) · [SA-REMOTE-FRAME-001](SA-REMOTE-FRAME-001.en.md) (frames) · [SA-REMOTE-TRACKTYPE-001](SA-REMOTE-TRACKTYPE-001.en.md) (`t` and `c` of `/ati`) |
| Machine-readable | [`Research/protocol/logic-remote-state.schema.json`](../protocol/logic-remote-state.schema.json) |
| Plan | The **static part** of PLAN-06. The receive experiment is PLAN-05, done once on 2026-10-05 (EXP-REMOTE-001; see the note below) |

> **Checked against a reception (2026-10-05, [EXP-REMOTE-001](../experiments/EXP-REMOTE-001-receive-initial-state.en.md)):** The initial send (§3 rows 2 to 16, 5a to 5f) arrived in this order. `/ati` and the counts arrived twice each and the two `/ati` were identical. `/gtFaderData` arrived between the first and second `/ati`, as a keyed archive (format 2); the keys of `g` equal the `gindex` values; zeros are not omitted. Not in the table: 447 `/cs/…` messages right after connecting (the feedback refresh), an early `/docOpen`, and meters flowing while stopped (30 per second each). Tempo is BPM × 10000; `/multiTempo` is `true` for a song with one tempo. `vL` at 0 dB is `0x5A000000`. One reception only; whether values are stable is unconfirmed.

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
| `c` | dictionary `{nc, sc, tnc, tsc}`, each a 4-byte `NSData` | colour computation (four colours) | normal / selected / icon normal / icon selected colours. **The 4 bytes are in the order R, G, B, A** (confirmed; the fourth byte, alpha, is normally 0xFF). How the values are made: [SA-REMOTE-TRACKTYPE-001](SA-REMOTE-TRACKTYPE-001.en.md) §5 |
| `n` | dictionary `{"name": string, "gindex": integer}` | the track name and the strip info's `identifier` | `gindex` is the **same value** as the keys of `g` in `/gtFaderData` (§8; confirmed: same accessor on the same kind of object; not confirmed on the wire) |
| `t` | integer (`char`) | `trackTypeForTrack:seqID:ginst:inSong:` (0x01693e90) | **returns 0–10**. The rules are confirmed; the track kind for each value is **mostly hypothesis** (5 = Master with confidence high, 9 = software instrument with medium). [SA-REMOTE-TRACKTYPE-001](SA-REMOTE-TRACKTYPE-001.en.md) §2 |
| `nc` | integer | when one byte (+0xd4) of the **ginst object (*G* of `t`)** is 1 to 15, the matching entry of the 15-entry table at `0x01d59030` (1, 2, 4, 4, 6, 7, 8, 8, 8, 8, 10, 10, 12, 14, 16). Otherwise, or without *G*, 0 (confirmed in machine code. The earlier "one byte of the song" was a misreading: the decompiler reused a variable name. [SA-REMOTE-TRACKTYPE-001](SA-REMOTE-TRACKTYPE-001.en.md) §9) | number of channels (from the key name and the shape of the values; hypothesis, confidence medium) |
| `p` | integer (`char`) | only when *G* exists and bit 27 of `allowedElementsForStrip:` is set, the result *k* (0 to 5) of `FUN_01a2cc68(G, 0)` indexes 0, -5, -1, -4, -1, -4. Otherwise -1. Without *G*: 0 if `t` is 4, else -1 (confirmed in machine code; same §9) | pan type (from the key name; hypothesis. The meaning of *k* is unresolved) |
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
  | `t` | integer (`char`): `trackTypeForTrack:…` is called for each selected strip and only results of 1 to 4 are merged (the value if they agree, 2 if they differ, 0 if none). The value is 0 to 4 (confirmed; [SA-REMOTE-TRACKTYPE-001](SA-REMOTE-TRACKTYPE-001.en.md) §3. The earlier "byte at +3 of the internal record, a different computation" was a misreading) |
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
| `/logicClock/currentTempo` | integer | `handleUM_CLOCK:` (UDP) | **BPM × 10000** (1200000 at 120 BPM; confirmed by one reception) |
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
| 2 | `r` (`t`) | one of 0, 1, 3, 0x40, 0x80. The key is `_BgTrackFaderDataRecEnableStateKey` (record-enable state). How the value is chosen: **§8.3** (checked in machine code) |
| 32 | `ip` (`t`) | a mask of up to 12 bits. Bit *k* is the internal flag (bit 2 of +0x3a) of channel *k* (confirmed). The key is `_BgTrackInfoIndependentPanKey` (checked with the bind, [anchor table](../protocol/logic-remote-recenable-anchors.tsv)), so a mark of "independent pan" (hypothesis). Not the I (input monitoring) button on screen: in E3 it was 0 on every track although the armed track's I was lit |

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

### 8.3 `r` (record-enable state) read in machine code (added 2026-10-07)

The key of `r` is `_BgTrackFaderDataRecEnableStateKey` (MACore; checked with the `dyld_info` bind). The value is decided by the return value *s* of `FUN_006ecc1c(song, high 16 bits of the trackID, track, &flag)`. Evidence: the [anchor table](../protocol/logic-remote-recenable-anchors.tsv) (171 rows, including the binds of the §8.1 keys and the mixer window path below; checked against the bytes of the image and `llvm-objdump`, not Ghidra).

| *s* | `r` | Anchor |
|---|---|---|
| −1 | 0x40 (64) | `R-map` (`cmn w0, #0x1` → `mov w26, #0x40`) |
| 0 | 0x80 if flag is set, otherwise 0 | `R-map` (`ldrb w8, [sp, #0x7]` → `csel`) |
| 1 | 1 | `R-map` |
| 2 or 3 | 3 | `R-map` (`sub w8, w0, #0x2`, `cmp w8, #0x2`, `b.hs`) |
| anything else | 0 | `R-map` |

- `r` is put in only when `changedMask` is 0 (the initial send) or has bit 2, and only when the track could be looked up from the trackID (otherwise the key is absent; `R-gate`, `R-lookup`; matches §7).
- Inside `FUN_006ecc1c` (as far as it was read):
  - It first calls `FUN_006e7fd8`; false gives −1 (`REC-cap`).
  - A track with children calls itself for each child; children that disagree give 3 (`REC-children`, `REC-three`).
  - Otherwise it looks at *k* = `FUN_00326348(song, track+0x20)` (`REC-state`). *k* = 1 gives 1. *k* = 2 gives 1 when the global byte `0x261e118` is 0; when it is set, it returns 0 and sets flag (`r` 0x80; `REC-two`). Anything else gives 3 if `FUN_006ee498(…)` is true, else 0. The path for a negative *k* is not read.
  - `0x261e118` is the same address as the condition that adds 0x80 to `m` in §8.1.
- The saved decompilation listed "0, 1, 3, 0x40, 0x80", but which return value becomes which was first confirmed in machine code.

**The same decision in the mixer window** (added 2026-10-07, checked in machine code; anchors `MIX-*`, `AUTO-*`): `MAMixerModelAdapter recordStateOfStrip:` uses the same *k* = `FUN_00326348(song, identifier)` and passes this to `mixerRecordStateFor:`:

| *k* | Mixer window value | Remote `r` |
|---|---|---|
| 1 | 1 | 1 |
| 2 | 3 when `0x261e118` is 0, 2 when set | 1 when 0, 0x80 when set |
| anything else (0 and so on) | 0, plus 4 if `FUN_006ee498(song, k, &identifier, 0, 0)` is true | 3 if `FUN_006ee498` is true, else 0 |

- `FUN_006ee498` returns 0 at once when its second argument is not 0 (`AUTO-entry`, `AUTO-zero`). So the "4" (3 on the Remote) comes only when *k* is neither 1 nor 2: a different kind from an explicit record-enable (*k* = 1, 2), which fits H2.
- `0x261e118` is read by 28 functions (Ghidra's reference list), including the mixer's `muteStateOfStrip:` and `soloStateOfStrip:` and the Drummer mute button update. **Hypothesis: the on-screen blink phase** (confidence: low; it is tempting to tie it to the blinking R and mute buttons, but the writer was not read). If so, the `r` of a *k* = 2 track can alternate between 1 and 0x80 with the blink.

Checked against receptions (3 receptions; the values were read with `remote_state.py replay`; for E3 the Swift reference test `theE3RecordingFollowsOneSelectionChange` gives the same):

| Reception | `r` | Strips |
|---|---|---|
| [EXP-REMOTE-001](../experiments/EXP-REMOTE-001-receive-initial-state.en.md) | 64 | 7 audio tracks, Stereo Out, Master (on the 2026-10-07 screen, the headers of Trk08 and Audio, the two visible, had no R button) |
| same | 0 | 3 software instrument tracks (the selected track then was the audio track Trk08, which stayed 64) |
| [EXP-REMOTE-003](../experiments/EXP-REMOTE-003-reconnect-selection-baseline.en.md) | 3 | the selected Amped Up (has children; `/ati` `t` 7). The rest has the same shape as EXP-REMOTE-001 |
| PLAN-05 E3 (2026-10-07) | 3 → 0, 0 → 3 | moving the selection from Ballad to Piano moved the 3 from Ballad to Piano (in a frame after the `/sti`). On screen, the automatic record-enable (R lit red) moved the same way |

| Hypothesis | Confidence | Basis and limits |
|---|---|---|
| H1: *s* = −1 (`r` 64) means "this track cannot be record-enabled" | Medium | 64 on the 7 audio tracks and 2 outputs in all 3 receptions. Only Trk08 and Audio were checked on screen to have no R button. The body of `FUN_006e7fd8` is not read |
| H2: the 3 that comes through `FUN_006ee498` is "the automatic record-enable that follows the selection" | Medium to low | Only the selected track had 3, and it moved with the selection (E3). Amped Up was 3 while selected (EXP-REMOTE-003) and 0 when not selected (E3), so it is tied to the selection. Whether a track with children gets its 3 through H2's path or through the disagreeing-children path cannot be told apart |
| H3: an explicit record-enable (pressing R, e.g. the MCU REC button) is *k* = 1 and gives `r` 1 | Low | Not seen in a reception yet. Testing it needs an experiment that record-enables a non-selected track over MCU while receiving |

What it means for the product: `r` is not a Boolean. Keep it **as the raw value**, with 64 meaning "cannot", 0 "not enabled", and 1 and 3 as (candidate) different kinds of record-enable (the same treatment as `e3-record` in `logic-remote-e3-observations.tsv`).

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
| Meaning of the values 0–10 of `t` (track kind) | The rules are confirmed (SA-REMOTE-TRACKTYPE-001 §2). Meaning: 5 = Master (high), 9 = software instrument (medium); the rest is hypothesis (low) or unresolved | Line up with the dedicated project's strips by receiving (E2). Folders and stacks are E3 or later |
| The value tables for `p` (pan type), `nc` and `DAT_01d59030` | **Resolved**: the table and constants were read and the source was confirmed to be *G* (SA-REMOTE-TRACKTYPE-001 §9). The meaning of the result *k* of `FUN_01a2cc68` is unresolved | Line up `nc` and `p` with the strips by receiving (E2) |
| Byte order of the 4 bytes of `c` | **Resolved**: R, G, B, A (SA-REMOTE-TRACKTYPE-001 §5). The values of `nc` and `sc` for colour numbers of 1 or more cannot be derived statically because the palette depends on run-time configuration | Check by receiving that `tnc` and `tsc` of a colour-number-0 track are `8cc0ffff` |
| Body of the block that the no-argument `sendChannelStripInfo` passes | Not analysed | It decides which strips get the extra messages |
| `gindex` and `instID` being the same value | The same in code (§8); not confirmed on the wire | Cross-check on receipt |
| Direction of `/multiTempo`, unit of `/logicClock/currentTempo` | **Seen once**: `true` for a song with one tempo (the code reading "1 = all the same"); tempo is BPM × 10000 | A song with a tempo change (E3 or later) |
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
