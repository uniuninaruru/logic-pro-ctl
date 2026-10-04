#!/bin/bash
# List the constants functions copy into their stack variables (see StackStoreReport.java).
#   Tools/ghidra/stackstores.sh <program, e.g. Logic.arm64> <outName> <function address>...
# Output: Research/raw/ghidra/<outName>.tsv (gitignored)
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROG="$1"; NAME="$2"; shift 2
PROJ="${GHIDRA_PROJECTS:-$HOME/GhidraProjects}/logicctl"
# One headless job at a time per project (Claude and Codex share it): see with-project-lock.py.
LOCK="${GHIDRA_LOCK:-$ROOT/Research/raw/ghidra/logicctl-project.lock}"
HEADLESS="${GHIDRA_HEADLESS:-$(brew --prefix ghidra)/libexec/support/analyzeHeadless}"
export JAVA_HOME="${JAVA_HOME:-$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home}"
export GHIDRA_HEADLESS_MAXMEM="${GHIDRA_HEADLESS_MAXMEM:-10G}"
OUT="$ROOT/Research/raw/ghidra/$NAME.tsv"
python3 "$ROOT/Tools/ghidra/with-project-lock.py" --lock "$LOCK" -- \
  "$HEADLESS" "$PROJ" logicctl -process "$PROG" -noanalysis -readOnly \
  -scriptPath "$ROOT/Tools/ghidra" -postScript StackStoreReport.java "$OUT" "$@" \
  >"$PROJ/stackstores-$NAME.log" 2>&1 || { tail -20 "$PROJ/stackstores-$NAME.log"; exit 1; }
grep -h "StackStoreReport:" "$PROJ/stackstores-$NAME.log" | tail -1
