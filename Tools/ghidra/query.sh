#!/bin/bash
# Ask targeted questions of an already analyzed program (see XrefDecompile.java).
#   Tools/ghidra/query.sh <program, e.g. Logic.arm64> <outName> <query>...
# Output: Research/raw/ghidra/<outName>.c (gitignored)
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROG="$1"; NAME="$2"; shift 2
PROJ="${GHIDRA_PROJECTS:-$HOME/GhidraProjects}/logicctl"
HEADLESS="${GHIDRA_HEADLESS:-$(brew --prefix ghidra)/libexec/support/analyzeHeadless}"
export JAVA_HOME="${JAVA_HOME:-$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home}"
export GHIDRA_HEADLESS_MAXMEM="${GHIDRA_HEADLESS_MAXMEM:-10G}"
OUT="$ROOT/Research/raw/ghidra/$NAME.c"
"$HEADLESS" "$PROJ" logicctl -process "$PROG" -noanalysis -readOnly \
  -scriptPath "$ROOT/Tools/ghidra" -postScript XrefDecompile.java "$OUT" "$@" \
  >"$PROJ/query-$NAME.log" 2>&1 || { tail -20 "$PROJ/query-$NAME.log"; exit 1; }
grep -h "XrefDecompile:" "$PROJ/query-$NAME.log" | tail -1
