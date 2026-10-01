# Logic Pro external surface — architecture map

Only observed facts go in the "Confirmed" columns. Each fact names its source:
a raw run under `Research/raw/<run>/` (gitignored), a committed file under
`Research/static-analysis/`, or the command that produced it.

Runs so far: `20261001-130602` (discover.sh), `20261001-131349-a2`,
`20261001-131833-a2` (discover2.sh). All against the same Logic process
(pid 25338, not relaunched between runs).

## 1. Environment
| Item | Value | Source |
|---|---|---|
| macOS | 27.0 (26A5416b), Darwin 27.0.0, arm64 (T8142) | `sw_vers`, `uname -a` |
| App | /Applications/Logic Pro Creator Studio.app | `ls /Applications` |
| Executable | `Logic Pro Creator Studio` (73 KB stub, arm64 only) | `file`, `lipo -info` |
| Version | 12.3.1 (CFBundleVersion 6682), ProjectName `MALogic_App` | version.plist |
| Bundle ID | `com.apple.mobilelogic` (not `com.apple.logic10`) | Info.plist |
| Signing | Apple Mac OS Application Signing, Team F3LWYJ7GM7, hardened runtime (flags 0x10000) | `codesign -dvv` |
| Sandbox | `com.apple.security.app-sandbox = false` | entitlements |
| Toolchain | Command Line Tools only, Swift 6.4, Python 3.14; no tshark, no Xcode | `xcode-select -p`, `which` |

The main executable is a stub. Logic's code lives in `Contents/Frameworks/`;
the largest are `Logic.framework` (40.7 MB), `MAAudioEngine` (18.3 MB),
`MAPlugInGUI` (10.3 MB), `MAMixer` (5.8 MB), `MACore` (4.6 MB).

## 2. Map

```
                         Logic Pro Creator Studio (pid 25338, not sandboxed)
                                         |
  +---------------+---------------+------+---------+-----------------+-----------------+
  |               |               |                |                 |                 |
TCP *:51463     UDP *:7000     CoreMIDI        Apple Events      NSXPCConnection    AX / CGEvent
_apple-lgremote _osc._udp      virtual src+dst NSAppleScript     "helperTool" via   (not examined)
._tcp (Bonjour) (Bonjour)      (Logic Proの仮想 Enabled=true,    initWithMachService
MultipeerConn.  ControlSurface 出力 / 仮想入力)   no .sdef found   Name: → installer
(MACore)        OSC (Logic.fw) + Control Surface                  helper (hypothesis)
  |               |              plug-ins (16) +
Logic Remote    TouchOSC etc.    Lua MIDI Device
(iPad/iPhone)                    Scripts (98)
```

## 3. Surfaces

### 3.1 TCP 51463 — Logic Remote (`_apple-lgremote._tcp`)
| | |
|---|---|
| Confirmed | Logic listens on `*:51463` IPv4+IPv6 (all interfaces, not loopback-only). Bonjour instance `174jnk4ko0l8w` resolves to this host:51463. TXT: `/hostType=0 /protocolVersion=10 _d=<computer name>`. Reproduced in 2 runs. |
| Confirmed | `MACore` imports `MCSession`, `MCPeerID`, `MCNearbyServiceAdvertiser`, `MCNearbyServiceBrowser` and contains string `apple-lgremote` (static-analysis/ipc-imports.txt). |
| Confirmed | `Logic.framework` contains classes `LgLogicRemoteController`, `LgLogicRemoteMessageRouter`, and 128 `handleUM_*` selectors (static-analysis/handleUM-selectors.txt). |
| Confirmed | 169 OSC-style address strings such as `/transport/pauseplay`, `/mixer/plugins/...`, `/keyCommand/commandsQuery`, `/logicClock/currentTempo` (static-analysis/osc-address-strings.tsv). |
| Confirmed | Port and instance name change per launch: 51463/`174jnk4ko0l8w` → 52476/`08n2x7g7zvtu4` (EXP-A3-001). UDP 7000 unchanged. |
| Unknown | Whether `_apple-lgremote._udp` (declared in Info.plist) is ever advertised — not seen in any run. How per-track volume/mute/pan travel: no `/mixer/volume`-like string was found. |
| Hypothesis | The service is MultipeerConnectivity (MPC): the instance name is a base36 peer ID and `_d` is the display name, which matches the MPC format in the prior art. Logic Remote's application messages are OSC-like addresses carried inside MPC session data. Confidence: medium (static + Bonjour only; no capture yet). |

### 3.2 UDP 7000 — OSC control surfaces (`_osc._udp`)
| | |
|---|---|
| Confirmed | Logic binds UDP `*:7000` (IPv6 socket). Bonjour `_osc._udp` instance `<computer name>` resolves to host:7000, TXT `AppleLogic=LogicProX mfk=1`. |
| Confirmed | `Logic.framework` imports `socket`, `bind`, `NSNetService`; contains `ControlSurfaceOSC`, `Starting OSC ports for device %@: In=%d, out=%d`, `Sending OSC Message %@ = %@ to '%@'`. |
| Unknown | Which OSC addresses Logic accepts on 7000 without a configured device; whether an unknown sender is rejected, ignored, or auto-added as a device. |
| Hypothesis | 7000 is Logic's documented OSC control-surface input (the TouchOSC flow). Commands would need a Controller Assignment (Learn) in Logic to map to mixer parameters. Confidence: medium (public TouchOSC docs + strings). |

### 3.3 CoreMIDI
| | |
|---|---|
| Confirmed | Logic publishes one virtual source `Logic Proの仮想出力` and one destination `Logic Proの仮想入力` (Tools/research-scripts/midi-endpoints.swift). No other endpoints present on this Mac. |
| Confirmed | 16 Control Surface plug-ins in `Contents/PlugIns/MIDI Device Plug-ins/` (Logic Control = MCU, HUI, Logic Remote, TouchOSC, …). `~/Library/Preferences/com.apple.logic.pro.cs` is an IFF-like file (byte-reversed chunk IDs, `MROF`=`FORM`) listing these modules plus `Lua`. |
| Confirmed | 98 Lua 5.2 MIDI Device Scripts (`MACore.framework/Resources/MIDI Device Scripts/*/*.device/config.lua`) defining `controller_info()` with `items` (name, objectType, midiType, MIDI bytes) and `supports_feedback`. Strings show Logic can "Export Assignments To Lua Script". |
| Confirmed | Logic scans every new CoreMIDI port with Mackie device queries. A probe that creates its own virtual source+destination and answers as model 0x14 is installed as a Logic Control surface automatically, with no GUI setup (EXP-MCU). Mute (note 0x10) and fader (pitchbend + touch) writes work and are confirmed by LED/fader echo and LCD text. |
| Unknown | Whether Logic loads user Lua scripts from a user directory; whether a script can bind items to mixer parameters with feedback. |

### 3.4 Apple Events / AppleScript
| | |
|---|---|
| Confirmed | `NSAppleScriptEnabled = true`; `Logic.framework` imports `AEInstallEventHandler`. No `.sdef`, `.scriptSuite` or `.appintents` metadata found in the bundle. |
| Unknown | Which events are handled beyond the standard suite. Not tested (sending an event would trigger a TCC Automation prompt). |

### 3.5 XPC / Mach / distributed notifications
| | |
|---|---|
| Confirmed | No `.xpc` service inside the app except `MAContentDownloading.framework/XPCServices/com.apple.musicapps.MAContentInstallation.xpc`. No framework imports `xpc_connection_create*` or Network.framework `nw_*`. |
| Confirmed | `Logic.framework` uses `NSXPCConnection` with property `_helperToolConnection` and `initWithMachServiceName:options:`; strings include `com.apple.ServiceManagement.blesshelper`; bundle ships `Contents/Library/LaunchServices/com.apple.musicapps.InstallerHelperTool`. |
| Confirmed | `NSDistributedNotificationCenter` imported by Logic, MADSP, MAKeymap, MAToolKit, MAToolKitHighLevel. |
| Hypothesis | The only XPC client in Logic.framework talks to the privileged installer helper, not to a control service. Confidence: medium (strings, not disassembly). |
| Unknown | Names of the distributed notifications posted/observed. |
| Note | No internal XPC control service has been found. Per project rules we do not design against one. |

### 3.6 Process and local IPC
| | |
|---|---|
| Confirmed | Logic has no child processes. 5 connected unix-domain socket pairs (anonymous, `lsof -U`). Related system processes: `coreaudiod`, `MIDIServer`, `AUHostingServiceXPC_arrow`, 2× `AudioComponentRegistrar`. |
| Unknown | Peers of the 5 unix sockets. |

### 3.7 Accessibility / CGEvent
- Transport is exposed as AX checkboxes 再生/録音 and button 停止; channel strip has AXSlider ボリュームフェーダー / パン and AXSwitch ミュート.
- AXPress on the inspector strip ミュート AXSwitch toggles mute; AXPress on the track-header ミュート AXCheckBox had no effect (EXP-MCU-003).
- This shell's process is not AX-trusted (`AXIsProcessTrusted() == false`); an AX backend needs the user to grant Accessibility to the host app.

## 4. Candidate control paths, ranked by current evidence
| Rank | Path | Read state? | Write? | Status |
|---|---|---|---|---|
| 1 | Logic Remote (MPC on TCP 51463) | likely (Remote shows mixer state) | likely | Prior art exists for MPC transport (2022, protocolVersion unknown then). App layer undocumented. Needs a capture with a real Logic Remote. |
| 2 | MCU over virtual MIDI (Logic Control plug-in) | **yes, verified**: fader echo, LED, LCD (names, dB) | **yes, verified** for mute and volume on track 1 | Auto-installed via handshake, no GUI setup (EXP-MCU-001…009). Chosen v0.1 backend. |
| 3 | OSC on UDP 7000 | feedback via assignments only | via assignments | Requires Controller Assignments per parameter. |
| 4 | Lua MIDI Device Script | unknown | via assignments | Needs user-script location confirmed. |
| 5 | Accessibility | yes (UI values) | yes | Fragile; last resort for things nothing else exposes. |
| 6 | CGEvent / key commands | no | yes | Write-only; violates verify-after-write alone. |
| — | Native XPC | — | — | No control service observed. |

## 5. Prior art
See `Research/notes/prior-art.md`.

## 6. Open questions / next experiments
1. ~~EXP-A3-001~~ done: TCP port changes per launch; resolve via Bonjour.
2. **EXP-A3-002**: capture loopback/Wi-Fi traffic while a real Logic Remote device connects, to confirm the MPC framing and protocolVersion 10. Needs an iPad/iPhone with Logic Remote, and `tcpdump` (requires sudo or BPF access — ask first).
3. ~~EXP-A3-003~~ done as EXP-MCU-001…009. Next: validate on tracks 2–4, solo, pan, banking past 8 tracks, transport.
4. **EXP-A3-004**: list distributed notifications Logic posts during play/stop (`NSDistributedNotificationCenter` observer, read-only).
5. Find where Logic reads user Lua MIDI Device Scripts.
