#!/bin/bash
# Phase A: external surface discovery for Logic Pro (read-only).
# Run on the Mac with Logic Pro open. Output goes to Research/raw/<timestamp>/.
set -u
OUT="$(cd "$(dirname "$0")/.." && pwd)/Research/raw/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

# run NAME CMD...   — saves stdout+stderr; on failure prints the first error line.
run() {
  local name="$1"; shift
  echo "== $name"
  "$@" >"$OUT/$name.txt" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then echo "  (exit $rc) $(head -1 "$OUT/$name.txt")"; fi
}
# runsh NAME 'shell pipeline'   — for commands that need pipes.
runsh() { local name="$1"; shift; run "$name" /bin/sh -c "$1"; }

# 0. Locate the app: $LOGIC_APP, then Spotlight, then common paths.
APP="${LOGIC_APP:-}"
if [ -z "$APP" ]; then
  APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.logic10'" 2>/dev/null | head -1)"
fi
for p in "/Applications/Logic Pro.app" "/Applications/Logic Pro X.app"; do
  [ -z "$APP" ] && [ -d "$p" ] && APP="$p"
done
runsh app_candidates 'ls -d /Applications/*[Ll]ogic*.app; mdfind "kMDItemContentType == com.apple.application-bundle && kMDItemDisplayName == *Logic*"'
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "Logic Pro.app not found. See $OUT/app_candidates.txt and rerun with LOGIC_APP=/path/to/app" >&2
  APP=""
fi
echo "$APP" >"$OUT/app_path.txt"
EXE="$(defaults read "$APP/Contents/Info" CFBundleExecutable 2>/dev/null)"
echo "app=$APP exe=${EXE:-?}"

# 1. Environment
run sw_vers sw_vers
run uname uname -a
run arch arch
run xcode_select xcode-select -p
run swift_version swift --version
if [ -n "$APP" ]; then
  run app_version defaults read "$APP/Contents/Info" CFBundleShortVersionString
  run app_bundle_id defaults read "$APP/Contents/Info" CFBundleIdentifier
  run app_info_plist plutil -p "$APP/Contents/Info.plist"
  run codesign codesign -dvvv --entitlements :- "$APP"

  # 2. Bundle contents
  run frameworks ls -1 "$APP/Contents/Frameworks"
  run plugins ls -1R "$APP/Contents/PlugIns"
  run xpc_services find "$APP" -maxdepth 6 -name "*.xpc"
  run helpers find "$APP/Contents" -maxdepth 3 -type f -perm -111
  run main_binary_libs otool -L "$APP/Contents/MacOS/$EXE"
  # sdef needs full Xcode; Command Line Tools alone fail here.
  run applescript_dict sdef "$APP"
else
  echo "  skipped app bundle steps (no app path)"
fi

# 3. Running process surface (Logic Pro must be running)
PID="$( [ -n "$EXE" ] && pgrep -x "$EXE" | head -1 )"
echo "pid=${PID:-none}" | tee "$OUT/pid.txt"
if [ -n "${PID:-}" ]; then
  run lsof_all lsof -nP -p "$PID"
  run lsof_net lsof -nP -a -i -p "$PID"
  run lsof_unix lsof -nP -a -U -p "$PID"
  runsh child_processes "ps -axo pid,ppid,user,comm | awk -v p=$PID '\$2==p'"
else
  echo "  Logic Pro is not running: skipped lsof"
fi
runsh processes "ps -axo pid,ppid,user,comm | grep -i -E 'logic|mainstage|coreaudio|midi' | grep -v grep"
# macOS has no timeout(1): browse Bonjour for 5 s, then stop.
runsh bonjour_logic_remote 'dns-sd -B _logicremote._tcp & p=$!; sleep 5; kill $p'
runsh bonjour_all_types 'dns-sd -B _services._dns-sd._udp & p=$!; sleep 5; kill $p'
runsh launchctl_logic "launchctl list | grep -i logic"

# 4. MIDI / control surfaces
run midi_devices system_profiler SPMIDIDataType
run logic_prefs find "$HOME/Library/Preferences" -maxdepth 1 -iname "*logic*"

echo "done: $OUT"
