#!/bin/bash
# Phase A: external surface discovery for Logic Pro (read-only).
# Run on the Mac with Logic Pro open. Output goes to Research/raw/<timestamp>/.
set -u
APP="${LOGIC_APP:-/Applications/Logic Pro.app}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/Research/raw/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
run() { local name="$1"; shift; echo "== $name"; "$@" >"$OUT/$name.txt" 2>&1 || echo "  (exit $?)"; }

# 1. Environment
run sw_vers sw_vers
run uname uname -a
run arch arch
run app_version defaults read "$APP/Contents/Info" CFBundleShortVersionString
run app_bundle_id defaults read "$APP/Contents/Info" CFBundleIdentifier
run app_info_plist plutil -p "$APP/Contents/Info.plist"
run codesign codesign -dvvv --entitlements :- "$APP"

# 2. Bundle contents
run frameworks ls -1 "$APP/Contents/Frameworks"
run plugins ls -1R "$APP/Contents/PlugIns"
run xpc_services find "$APP" -name "*.xpc" -maxdepth 6
run helpers find "$APP/Contents" -maxdepth 3 -type f -perm -111
run main_binary_libs otool -L "$APP/Contents/MacOS/Logic Pro X"
run applescript_dict sdef "$APP"

# 3. Running process surface (Logic Pro must be running)
PID="$(pgrep -x 'Logic Pro X' || pgrep -f 'Logic Pro' | head -1)"
echo "pid=${PID:-none}" >"$OUT/pid.txt"
if [ -n "${PID:-}" ]; then
  run lsof_all lsof -nP -p "$PID"
  run lsof_net lsof -nP -i -a -p "$PID"
  run lsof_unix lsof -nP -U -a -p "$PID"
fi
run processes ps axo pid,ppid,user,comm | grep -i -E 'logic|mainstage|coreaudio|midi' 
run bonjour_logic_remote timeout 5 dns-sd -B _logicremote._tcp
run launchctl_logic launchctl list | grep -i logic

# 4. MIDI / control surfaces
run midi_devices system_profiler SPMIDIDataType
run control_surface_prefs find "$HOME/Library/Preferences" -iname "*logic*"

echo "done: $OUT"
