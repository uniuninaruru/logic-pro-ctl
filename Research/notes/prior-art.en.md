[日本語](prior-art.md) | [English](prior-art.en.md)

# Prior art

Treat every claim here as unverified until reproduced on Logic 12.3.1 /
macOS 27 and recorded under `Research/experiments/`.

## evilsocket — Reverse Engineering the Apple MultiPeer Connectivity Framework (2022-10-20)
- URL: https://www.evilsocket.net/2022/10/20/Reverse-Engineering-the-Apple-MultiPeer-Connectivity-Framework
- PoC: https://github.com/evilsocket/mpcfw (Python; mdns, tcp, stun, "ospf" modules).
  **No license file** — read for reference only, do not copy code into this repo.
- Started from Logic Remote traffic. Claims (all unverified here):
  - TCP server port random per launch, advertised via mDNS; peer ID is a random
    64-bit integer in base36 (matches our instance name `174jnk4ko0l8w` in shape).
  - TCP header: 2-byte signature (Hello/Ack/Accept/Invitation/InviteResponse/
    ClientData), 4-byte sequence+flags, 2-byte payload size, 4-byte CRC32,
    4-byte constant unknown.
  - Payloads are binary plists (`bplist00`), nested; keys
    `MCNearbyServiceInviteIDKey`, `MCNearbyServiceSenderPeerIDKey`,
    `MCNearbyServiceConnectionDataKey`, etc.
  - Session data goes over UDP after an Apple-flavoured STUN/ICE exchange; an
    inner packet format with signature byte 0xC1, channel ID, CRC16/ARC, and
    sender/receiver peer IDs.
  - Authorization is based on peer hostname only.
  - Logic's application message format was **not** documented.

## Alban Diquet — "It Just (Net)Works", HITB KUL 2014
- https://archive.conference.hitb.org/hitbsecconf2014kul/sessions/it-just-networks-the-truth-about-apples-multipeer-connectivity-framework/
- High-level MPC analysis.

## Logic OSC / TouchOSC
- https://hardware.hexler.net/touchosc/manual/setup-logic — TouchOSC as a Logic
  control surface; Logic receives OSC on port 7000.
- https://cycling74.com/forums/controlling-logic-pro-x-through-osc
