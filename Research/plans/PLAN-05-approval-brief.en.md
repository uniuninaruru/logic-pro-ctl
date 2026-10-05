[日本語](PLAN-05-approval-brief.md) | [English](PLAN-05-approval-brief.en.md)

# PLAN-05 approval brief — one independent peer, receive-only, to check how Logic Remote state arrives

| Item | Value |
|---|---|
| Status | **A proposal. Nothing has been run. No connection is made until it is approved** |
| Date | 2026-10-05 |
| Purpose | Check the predictions from static analysis (the order of the connection, the frames, the initial send, the song change) with one short receive |
| Scope | Connect **one research peer** to the Logic on this Mac (the dedicated project `LogicCLI-Test.logicx`) and **only receive** |
| Evidence | [SA-REMOTE-SESSION-001](../static-analysis/SA-REMOTE-SESSION-001.en.md) · [SA-REMOTE-FRAME-001](../static-analysis/SA-REMOTE-FRAME-001.en.md) · [SA-REMOTE-STATE-001](../static-analysis/SA-REMOTE-STATE-001.en.md) |

What needs approval is **the stages up to "E1" and "E2" below**. E0 only checks that the advertisement is visible, without connecting; approval for it is requested at the same time. E3 and later are discussed again after the result of E2.

## 1. What may and may not be done

| May be done (after approval) | Will not be done |
|---|---|
| Look for the `apple-lgremote` advertisement with Apple's MultipeerConnectivity (E0) | **Using the name of an existing Logic Remote device** to avoid the confirmation dialog (impersonation) |
| Send an invitation under its own name, with the user pressing "Connect" in Logic's dialog (E1) | Changing Logic's binary, its signature or SIP, using `sudo`, or injecting into the process |
| Send `/protocolVersion` and `/jsonSupport`, then **receive and record** what Logic sends (E1, E2) | Any edit command (play and stop included), `/keyCommand/actionNum`, `/cs/`, `/fader`, or anything else that changes Logic's state |
| Record the receive for a few tens of seconds with one song of the dedicated project open (E2) | Running the experiment with a production project open |
| Keep the raw received data in `Research/raw/` (not tracked by Git) and commit only the organised results | Committing raw traffic, or publishing anything with personal data |

## 2. Side effects to know in advance

1. **Logic shows a confirmation dialog.** When a peer with an unknown name invites it, Logic asks whether to connect (`shouldConnectToPeerID:ofType:`; SA-REMOTE-SESSION-001 §3.2). **A person has to press "Connect".** It cannot proceed unattended.
2. **Logic may register the device.** After "Connect", Logic remembers the name as a Logic Remote device (a new registration; §3.2 there). It stays in Logic's settings and how to delete it is not confirmed. **This is a lasting change to Logic's settings** and may reach beyond the dedicated project.
3. **macOS asks for "Local Network" permission.** The research peer is a small app using Bonjour and MultipeerConnectivity. macOS asks the first time.
4. **The connection is set up without encryption** (§3.1 there). The traffic is inside this Mac, but whether it can leave for the network is not confirmed.
5. Logic keeps sending state while connected. Do not switch songs or change record-arm (do not operate Logic during E2).

## 3. Stages

| Stage | What | What is sent | What is recorded | Stop when |
|---|---|---|---|---|
| **E0** | Look for `apple-lgremote` with `MCNearbyServiceBrowser`. **No invitation** | nothing | the name of the peer found and its `discoveryInfo` (`/hostType`, `/protocolVersion`) | nothing is found → end here |
| **E1** | Invite under its own name; the user presses "Connect" in Logic's dialog. Once connected, send `/protocolVersion = 10` and `/jsonSupport` | only those two | the order and times of the connection state changes, the first messages received | no dialog / refused → end. An unexpected dialog → stop |
| **E2** | Stay connected and receive the initial send for at most 60 seconds. **Send nothing** | nothing | every received frame (time, format tag, whether MAZP, the decompressed content) | 60 s, or the user's signal, or a disconnect |
| E3 (later) | Receive the deltas for a song switch and for muting one track | to be decided | the deltas | discussed again after seeing E2 |

E1 and E2 run in **one connection**. Close the connection afterwards (quit the peer).

## 4. Predictions checked in E2

Each hypothesis of the static analysis is compared with what is received. **If one is wrong, record it as it is** (do not rewrite the documents to fit).

| # | Prediction (evidence) | How to read a pass |
|---|---|---|
| P1 | After E1 connects, `/protocolVersion` arrives from Logic as **10** right away (SESSION §4) | `/protocolVersion = 10` and `/jsonSupport` are among the first messages |
| P2 | Logic starts the initial send after waiting for the version (STATE §3.4) | `/mixer/hideRecordButtons` and the others arrive after `/protocolVersion` is sent |
| P3 | The order of the initial send is that of the table in STATE §3 (`/hostType`, `/ati`, `/allTrackCount`, …) | The order received matches the table. Differences are recorded row by row |
| P4 | `/ati` is 13 parallel arrays of equal length (STATE §4) | Passes the check against the [schema](../protocol/logic-remote-state.schema.json) |
| P5 | `/ati` and `/allTrackCount` / `/trackCount` arrive **twice** (STATE §3.2) | Two copies with the same content |
| P6 | The argument of `/sti` is an NSKeyedArchive compressed as MAZP (STATE §5) | It decompresses to a dictionary |
| P7 | The keys of `g` in `/gtFaderData` equal the `gindex` values of `/ati` (STATE §8) | The sets match |
| P8 | The direction of `/multiTempo` (STATE §6) and the unit of `/logicClock/currentTempo` | Read against the known tempo (120 in the project) |
| P9 | How `vL` relates to the MCU's dB display (STATE §8.1) | Read against a known dB value (such as 0 dB) |
| P10 | A value of 0 is omitted only in the initial pass for key commands (STATE §7) | `s`, `m` and `vL` in `/gtFaderData` are present even when 0 |
| P11 | The initial send has no end marker (STATE §10) | Check whether the last message ends in a fixed shape |
| P12 | `/ati`'s `t`: Master = 5 (confidence high), Piano, Bass, Synth = 9 (medium), Audio and Trk05 to Trk10 = 1 (low; 4 if not), St Out = 6 or 10 (low) ([SA-REMOTE-TRACKTYPE-001](../static-analysis/SA-REMOTE-TRACKTYPE-001.en.md) §7) | Lined up against the 12 strips of the dedicated project. A value that is off is recorded as it is |
| P13 | Each of the 4 colours of `c` is 4 bytes in the order R, G, B, A; the fourth is almost always `0xff`. `tnc` and `tsc` of a colour-number-0 track are `8cc0ffff` (computed; same note, §5 and §7) | Compare the received `NSData` of `c`; check the colour number separately in `/colorIndexMap` |

The first thing to check is whether each received frame decodes with [`RemoteFrameParser`](../../Sources/LogicCore/Backends/Remote/RemoteFrame.swift). If it does not, that fact is the first finding.

## 5. Outlook for the implementation (work after approval)

- The research peer is a small macOS app (Swift) under `Tools/`. It does not go into the product's `Sources/`. It only receives, and saves to `Research/raw/remote-recv/<date-time>/`.
- The main chore: put `NSLocalNetworkUsageDescription` and the Bonjour service names (`_apple-lgremote._tcp` / `._udp`) in the Info.plist. A developer signature of its own should do for code signing (the signatures of Logic and of other apps are not changed).
- The invitation `context` carries a device kind (one of 0 to 4; mind the signed comparison noted in SESSION §3.2) as a binary plist.
- Time: under a day to implement, as estimated. The experiment itself takes minutes.

## 6. What needs your approval

1. May **E0** (look for the advertisement without connecting) be done?
2. May **E1 and E2** (connect under its own name, press "Connect" in the dialog, and receive) be done?
   - Who presses the dialog: you yourself, or I under an **explicitly permitted operation**?
   - Is the side effect "Logic registers a device" (§2-2) acceptable? Whether the registered name can be deleted from Logic's screen afterwards is checked in E1.
3. May Logic be limited to the dedicated project during the experiment (other projects closed)?

**Nothing beyond the approved scope (sending edit commands, E3 and later, a production project) will be done.**
