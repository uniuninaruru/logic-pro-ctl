#!/bin/bash
# Re-export the existing Logic 12.3.1 Ghidra analysis with corrected AE types.
# This does not import, attach to, launch, or modify the installed Logic app.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="${1:?usage: bash Tools/ghidra/appleevents.sh /path/to/Logic.app [output-directory]}"
PROJ="${GHIDRA_PROJECTS:-$HOME/GhidraProjects}/logicctl"
LOCK="${GHIDRA_LOCK:-$ROOT/Research/raw/ghidra/logicctl-project.lock}"
OUT="${2:-$ROOT/Research/raw/$(date -u +%Y%m%dT%H%M%SZ)-ghidra-appleevents}"
BIN="$APP/Contents/Frameworks/Logic.framework/Versions/A/Logic"
ANALYZED="$PROJ/bin/Logic.arm64"
EXPECTED="2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998"
if [ ! -f "$BIN" ] || [ ! -f "$ANALYZED" ]; then
  echo "Installed Logic binary or existing analyzed copy not found." >&2
  exit 1
fi
# The Java post-script's addresses are exact to this binary, not relocatable APIs.
for FILE in "$BIN" "$ANALYZED"; do
  ACTUAL="$(shasum -a 256 "$FILE" | awk '{print $1}')"
  if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "Binary hash mismatch; re-identify anchors before running this version-specific report: $FILE" >&2
    exit 1
  fi
done
HEADLESS="${GHIDRA_HEADLESS:-$(brew --prefix ghidra)/libexec/support/analyzeHeadless}"
export JAVA_HOME="${JAVA_HOME:-$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home}"
export GHIDRA_HEADLESS_MAXMEM="${GHIDRA_HEADLESS_MAXMEM:-10G}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
python3 "$ROOT/Tools/ghidra/with-project-lock.py" --lock "$LOCK" -- \
  "$HEADLESS" "$PROJ" logicctl -process Logic.arm64 -noanalysis -readOnly \
  -scriptPath "$ROOT/Tools/ghidra" -postScript AppleEventHandlerReport.java "$OUT" \
  >"$OUT/headless.log" 2>&1 || { tail -30 "$OUT/headless.log" >&2; exit 1; }
if ! rg -q 'AppleEventHandlerReport: exported' "$OUT/headless.log"; then
  tail -30 "$OUT/headless.log" >&2
  exit 1
fi
echo "Ghidra AppleEvent report: $OUT"
