#!/bin/bash
# Run one stage of the research peer and wait for it to end.
#   Tools/remote-research-peer/run.sh e0 [--seconds N]
#   Tools/remote-research-peer/run.sh e1 [--seconds N] [--target "<Logic's advertised name>"]
# Output: Research/raw/remote-recv/<time>-<stage>/ (not tracked by Git): events.jsonl, decoded.jsonl, frames/*.bin, summary.json
# End a run early with: touch <that directory>/STOP
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE="${1:?stage e0 or e1}"; shift
case "$STAGE" in e0|e1) ;; *) echo "stage must be e0 or e1" >&2; exit 64;; esac
APP="$ROOT/.build/remote-research-peer/LogicctlResearchPeer.app"
[ -d "$APP" ] || "$ROOT/Tools/remote-research-peer/build.sh" >/dev/null
OUT="$ROOT/Research/raw/remote-recv/$(date +%Y%m%d-%H%M%S)-$STAGE"
mkdir -p "$OUT"
echo "output: $OUT"
open -n -W -a "$APP" --args --stage "$STAGE" --out "$OUT" "$@" || true
echo "--- summary"
cat "$OUT/summary.json" 2>/dev/null || echo "(no summary: the peer did not finish; see $OUT/events.jsonl)"
