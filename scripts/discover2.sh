#!/bin/bash
# Phase A-2: identify owners of Logic Pro's listening sockets and other control
# surfaces. Read-only: it never connects to Logic, sends Apple events, or
# changes preferences. Run with Logic Pro open. Bash 3.2 compatible (macOS).
#
# Output: Research/raw/<timestamp>-a2/ and a single summary.txt to paste back.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Research/raw/$(date +%Y%m%d-%H%M%S)-a2"
mkdir -p "$OUT/bonjour"
SUM="$OUT/summary.txt"
say() { echo "$*" | tee -a "$SUM"; }

# --- locate app and process -------------------------------------------------
APP="${LOGIC_APP:-}"
if [ -z "$APP" ]; then
  for p in "/Applications/Logic Pro.app" "/Applications/Logic Pro X.app" /Applications/Logic\ Pro*.app; do
    [ -z "$APP" ] && [ -d "$p" ] && APP="$p"
  done
fi
EXE="$(defaults read "$APP/Contents/Info" CFBundleExecutable 2>/dev/null)"
BID="$(defaults read "$APP/Contents/Info" CFBundleIdentifier 2>/dev/null)"
PID="$( [ -n "$EXE" ] && pgrep -x "$EXE" | head -1 )"
say "# Phase A-2 summary ($(date '+%Y-%m-%d %H:%M:%S'))"
say "app=$APP"
say "exe=$EXE bundle_id=$BID pid=${PID:-none}"
if [ -z "${PID:-}" ]; then
  say "ERROR: Logic Pro is not running. Open a project and rerun."
  exit 1
fi
say "process_start=$(ps -o lstart= -p "$PID")"

# --- 1. listening sockets and comparison with earlier runs -----------------
lsof -nP -a -i -p "$PID" >"$OUT/lsof_net.txt" 2>&1
lsof -nP -a -U -p "$PID" >"$OUT/lsof_unix.txt" 2>&1
PORTS="$(awk 'NR>1 {n=($NF=="(LISTEN)")?$(NF-1):$NF; sub(/.*:/,"",n); print n}' "$OUT/lsof_net.txt" | sort -un | tr '\n' ' ')"
say ""
say "## 1. Network sockets"
awk 'NR>1 {print "  " $5, $8, $9, $10}' "$OUT/lsof_net.txt" | sort -u | tee -a "$SUM"
say "ports: $PORTS"
say "unix sockets: $(($(wc -l <"$OUT/lsof_unix.txt") - 1))"
say "earlier runs (ports seen per run, to check whether they change per launch):"
for f in "$ROOT"/Research/raw/*/lsof_net.txt; do
  [ "$f" = "$OUT/lsof_net.txt" ] && continue
  run="$(basename "$(dirname "$f")")"
  p="$(awk 'NR>1 {n=($NF=="(LISTEN)")?$(NF-1):$NF; sub(/.*:/,"",n); print n}' "$f" | sort -un | tr '\n' ' ')"
  say "  $run: ${p:-none}"
done

# --- 2. Bonjour: which advertised service resolves to one of those ports ----
# dns-sd never exits on its own: run it in the background and kill it.
# Redirecting to a file works without a tty; script(1) fails when stdin is
# not a terminal ("tcgetattr/ioctl: Operation not supported on socket").
# browse OUTFILE SECONDS dns-sd-args...
browse() {
  local out="$1" secs="$2"; shift 2
  dns-sd "$@" >"$out" 2>&1 & local bp=$!
  sleep "$secs"; kill "$bp" 2>/dev/null; wait "$bp" 2>/dev/null
}
say ""
say "## 2. Bonjour"
browse "$OUT/bonjour/types.txt" 6 -B _services._dns-sd._udp local.
# Lines look like: "... Add  3  4 .  _tcp.local.  _http"  -> "_http._tcp"
TYPES="$(awk '$2=="Add" {print $NF "." $(NF-1)}' "$OUT/bonjour/types.txt" | sed 's/\.local\.$//; s/\.$//' | sort -u)"
say "service types seen: $(echo "$TYPES" | grep -c .)"
echo "$TYPES" >"$OUT/bonjour/type_list.txt"
HOST="$(scutil --get LocalHostName 2>/dev/null)"
for t in $TYPES; do
  safe="$(echo "$t" | tr -c 'A-Za-z0-9_\n' '_')"
  browse "$OUT/bonjour/B_$safe.txt" 3 -B "$t" local.
  # Instance names may contain spaces: take everything after the 6th field.
  awk '$2=="Add" {s=""; for (i=7;i<=NF;i++) s=s (i>7?" ":"") $i; print s}' "$OUT/bonjour/B_$safe.txt" | sort -u |
  while IFS= read -r inst; do
    [ -z "$inst" ] && continue
    f="$OUT/bonjour/L_${safe}_$(echo "$inst" | tr -c 'A-Za-z0-9\n' '_').txt"
    browse "$f" 3 -L "$inst" "$t" local.
    line="$(grep -m1 "can be reached" "$f" | sed 's/^.*can be reached at //')"
    port="$(echo "$line" | sed -n 's/.*:\([0-9][0-9]*\).*/\1/p')"
    mark=""
    for p in $PORTS; do [ "$port" = "$p" ] && mark="  <== matches Logic port $p"; done
    case "$line" in *"$HOST"*) mark="$mark (this Mac)";; esac
    say "  $t | $inst | ${line:-unresolved}$mark"
  done
done

# --- 3. Entitlements and scripting flags ------------------------------------
say ""
say "## 3. Entitlements (keys only)"
codesign -d --entitlements :- "$APP" >"$OUT/entitlements.plist" 2>/dev/null
grep -o '<key>[^<]*</key>' "$OUT/entitlements.plist" | sed 's/<\/*key>//g; s/^/  /' | tee -a "$SUM"
grep -A12 -E 'mach-lookup|temporary-exception|application-groups' "$OUT/entitlements.plist" >"$OUT/entitlements_exceptions.txt"
say "Info.plist scripting/remote keys:"
plutil -p "$APP/Contents/Info.plist" | grep -i -E 'NSAppleScript|OSAScripting|NSBonjour|NSLocalNetwork|LSUIElement|NSAppleEvents' | sed 's/^/  /' | tee -a "$SUM"

# --- 4. Which binaries link Network/Multipeer frameworks --------------------
# Public reporting (evilsocket, 2022) says Logic Remote uses MultipeerConnectivity.
say ""
say "## 4. Linked networking frameworks"
MAIN="$APP/Contents/MacOS/$EXE"
find "$APP/Contents/Frameworks" -maxdepth 4 -type f -perm -111 2>/dev/null >"$OUT/fw_binaries.txt"
echo "$MAIN" >>"$OUT/fw_binaries.txt"
: >"$OUT/linkage.txt"
while IFS= read -r b; do
  libs="$(otool -L "$b" 2>/dev/null | grep -E 'MultipeerConnectivity|/Network.framework|CoreMIDI|ApplicationServices|OSAKit|Carbon' | awk '{print $1}' | sed 's|.*/||' | tr '\n' ' ')"
  [ -n "$libs" ] && echo "$(basename "$b"): $libs" >>"$OUT/linkage.txt"
done <"$OUT/fw_binaries.txt"
grep -E 'MultipeerConnectivity' "$OUT/linkage.txt" | sed 's/^/  /' | tee -a "$SUM"
say "  (binaries linking CoreMIDI: $(grep -c CoreMIDI "$OUT/linkage.txt"))"

# --- 5. Strings hinting at service types / control-surface protocols --------
say ""
say "## 5. Strings (Bonjour service types, MCU, Scripter, OSC)"
: >"$OUT/strings_hits.txt"
while IFS= read -r b; do
  strings -a "$b" 2>/dev/null | grep -E '^_[a-z0-9-]+\._(tcp|udp)$|^[a-z0-9-]{1,15}$' | grep -E '\._(tcp|udp)$|^logic|remote' |
    sed "s|^|$(basename "$b"): |" >>"$OUT/strings_hits.txt"
  strings -a "$b" 2>/dev/null | grep -i -E 'MCNearbyService|MCSession|serviceType|Mackie Control|LogicRemote|Logic Remote|OSC ' | head -20 |
    sed "s|^|$(basename "$b"): |" >>"$OUT/strings_hits.txt"
done <"$OUT/fw_binaries.txt"
sort -u "$OUT/strings_hits.txt" | head -80 | sed 's/^/  /' | tee -a "$SUM"

# --- 6. Bundled helpers / plug-ins and running children ---------------------
say ""
say "## 6. Bundle helpers, plug-ins, child processes"
find "$APP/Contents" -maxdepth 4 \( -name "*.xpc" -o -name "*.appex" -o -name "*.app" -o -name "*.bundle" \) 2>/dev/null |
  sed "s|$APP/||" | sort | head -60 | sed 's/^/  /' | tee -a "$SUM"
ps -axo pid,ppid,comm | awk -v p="$PID" '$2==p' | sed 's/^/  child: /' | tee -a "$SUM"
ls "$HOME/Library/Containers" 2>/dev/null | grep -i -E 'logic' | sed 's/^/  container: /' | tee -a "$SUM"

# --- 7. MIDI endpoints (for the MCU / Scripter paths) ----------------------
say ""
say "## 7. MIDI"
# system_profiler SPMIDIDataType prints nothing on macOS 27; ask CoreMIDI directly.
swift "$ROOT/Tools/research-scripts/midi-endpoints.swift" >"$OUT/midi.txt" 2>&1
sed 's/^/  /' "$OUT/midi.txt" | tee -a "$SUM"

say ""
say "done: $OUT"
echo "Paste the contents of: $SUM"
