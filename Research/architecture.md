# Logic Pro external surface — research log

Status: **not started**. Nothing below has been observed yet; fill each
section from `scripts/discover.sh` output (`Research/raw/<timestamp>/`).
Record only what was observed, with the file it came from.

## 1. Environment
| Item | Value | Source |
|---|---|---|
| macOS | | sw_vers.txt |
| Architecture | | arch.txt |
| Logic Pro version | | app_version.txt |
| Bundle ID | | app_bundle_id.txt |

## 2. Candidate control paths
| Path | Observed? | Evidence | Notes |
|---|---|---|---|
| Native IPC / XPC | | xpc_services.txt, lsof_unix.txt | |
| Logic Remote (network) | | lsof_net.txt, bonjour_logic_remote.txt | |
| MCU / CoreMIDI | | midi_devices.txt | |
| Scripter (MIDI FX) | | | |
| AppleScript | | applescript_dict.txt | |
| Accessibility | | | |
| CGEvent | | | |

## 3. Open questions
- 
