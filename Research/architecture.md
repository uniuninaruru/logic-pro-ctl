# Logic Pro external surface — research log

Only observed facts go in the tables. Each row names the raw file
(`Research/raw/<run>/`, not committed) it came from.

## 1. Environment (run 20261001-130602)
| Item | Value | Source |
|---|---|---|
| macOS | 27.0 (26A5416b) | sw_vers.txt |
| Architecture | arm64 | arch.txt |
| App path | /Applications/Logic Pro Creator Studio.app | app_path.txt |
| Executable | Logic Pro Creator Studio | Info.plist CFBundleExecutable |
| Version | 12.3.1 | app_version.txt |
| Bundle ID | com.apple.mobilelogic | app_bundle_id.txt |
| Toolchain | Command Line Tools only, Swift 6.4 | xcode_select.txt, swift_version.txt |

Notes:
- The bundle ID is not `com.apple.logic10`, so Spotlight lookup by that ID fails.
- Command Line Tools lack XCTest, the Swift Testing macro plugin, and `sdef`.

## 2. Network sockets of the running app (pid 25338)
| Proto | Bind | State | Source |
|---|---|---|---|
| UDP (IPv6) | *:7000 | — | lsof_net.txt |
| TCP (IPv4) | *:51463 | LISTEN | lsof_net.txt |
| TCP (IPv6) | *:51463 | LISTEN | lsof_net.txt |

Unknown: which service owns each socket, and whether 51463 changes per launch.

## 3. Bundle
- `*.xpc` inside the bundle (maxdepth 6): none found (xpc_services.txt empty).
- Frameworks (first 60 of frameworks.txt) include `Logic.framework`,
  `LogicAppFramework.framework`, `MALogicCoreInterface.framework`,
  `MAAccessibility.framework`, `MAMixer.framework`, `MAAudioEngine.framework`,
  `MAAudioUnitSupport.framework`, `ChordsKit.framework`, `MAHarmony.framework`.
  Roles not yet examined.

## 4. Candidate control paths
| Path | Observed? | Evidence |
|---|---|---|
| Native IPC / XPC | no bundled .xpc | xpc_services.txt |
| Network (Logic Remote?) | 2 listening sockets, owner unknown | lsof_net.txt |
| MCU / CoreMIDI | not examined | midi_devices.txt |
| Scripter | not examined | — |
| AppleScript | blocked: `sdef` needs Xcode | applescript_dict.txt |
| Accessibility | not examined | — |
| CGEvent | not examined | — |

## 5. Open questions
- Does TCP 51463 change across launches?
- Which Bonjour service type advertises it?
- What is UDP 7000?
- Entitlements (codesign.txt): network server, mach-lookup exceptions?
