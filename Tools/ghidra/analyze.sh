#!/bin/bash
# Imports one Logic binary (arm64 slice) into a headless Ghidra project,
# analyzes it, and exports functions + decompiled C via ExportDecompiled.java.
# Read-only for Logic: works on a thinned copy, never on the app bundle.
#
#   Tools/ghidra/analyze.sh <path-to-binary> [nameRegex]
#
# Project: $GHIDRA_PROJECTS (default ~/GhidraProjects)/logicctl
# Output:  Research/raw/ghidra/ (gitignored)/<binary>.{functions.tsv,decompiled.c}
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$1"
FILTER="${2:-.*}"
PROJ="${GHIDRA_PROJECTS:-$HOME/GhidraProjects}/logicctl"
HEADLESS="${GHIDRA_HEADLESS:-$(brew --prefix ghidra)/libexec/support/analyzeHeadless}"
export JAVA_HOME="${JAVA_HOME:-$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home}"
# Decompiled Apple code stays local (gitignored); commit notes only.
OUT="$ROOT/Research/raw/ghidra"

mkdir -p "$PROJ/bin" "$OUT"
name="$(basename "$BIN" | tr ' ' '_')"
thin="$PROJ/bin/$name.arm64"
if lipo -info "$BIN" 2>/dev/null | grep -q "Non-fat"; then
  cp "$BIN" "$thin"
else
  lipo -thin arm64 "$BIN" -output "$thin"
fi

if [ -d "$PROJ/logicctl.rep/idata" ] && "$HEADLESS" "$PROJ" logicctl -process "$name.arm64" -noanalysis \
     -readOnly -scriptPath "$ROOT/Tools/ghidra" -postScript ExportDecompiled.java "$OUT" "$FILTER" \
     >"$PROJ/$name.export.log" 2>&1 && grep -q "ExportDecompiled:" "$PROJ/$name.export.log"; then
  echo "reused existing analysis of $name"
else
  "$HEADLESS" "$PROJ" logicctl -import "$thin" -overwrite \
    -scriptPath "$ROOT/Tools/ghidra" -postScript ExportDecompiled.java "$OUT" "$FILTER" \
    >"$PROJ/$name.import.log" 2>&1
fi
grep -h "ExportDecompiled:" "$PROJ/$name".*.log | tail -1
