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
# These are wrapper-owned: overriding them would detach provenance and summary
# from the app's actual output directory or stage.
for ARG in "$@"; do
  case "$ARG" in --out|--out=*|--stage|--stage=*) echo "run.sh manages --out and --stage; overrides are not allowed" >&2; exit 64;; esac
done
APP="$ROOT/.build/remote-research-peer/LogicctlResearchPeer.app"
OUT="$ROOT/Research/raw/remote-recv/$(date +%Y%m%d-%H%M%S)-$STAGE"
mkdir -p "$OUT"
echo "output: $OUT"
# Always rebuild our own research app. Compare its two Swift inputs and builder
# before and after compilation, then record the signed executable's hash.
python3 - "$ROOT" "$OUT" <<'PY'
import hashlib, json, pathlib, sys
root, out = map(pathlib.Path, sys.argv[1:])
paths = ["Tools/remote-research-peer/main.swift", "Sources/LogicCore/Backends/Remote/RemoteFrame.swift",
         "Tools/remote-research-peer/build.sh"]
inputs = [{"path": p, "bytes": (root / p).stat().st_size,
           "sha256": hashlib.sha256((root / p).read_bytes()).hexdigest()} for p in paths]
(out / "build-inputs-before.json").write_text(json.dumps(inputs, indent=2) + "\n")
PY
"$ROOT/Tools/remote-research-peer/build.sh" >/dev/null
python3 - "$ROOT" "$APP" "$OUT" <<'PY'
import datetime, hashlib, json, pathlib, subprocess, sys
root, app, out = map(pathlib.Path, sys.argv[1:])
inputs = json.loads((out / "build-inputs-before.json").read_text())
for item in inputs:
    data = (root / item["path"]).read_bytes()
    if len(data) != item["bytes"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
        raise SystemExit("build input changed; refusing to launch: " + item["path"])
def artifact(path):
    data = path.read_bytes()
    return {"path": str(path), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
result = {"built_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
          "fresh_build": True, "inputs_match_before_after_build": True, "inputs": inputs,
          "executable": artifact(app / "Contents/MacOS/peer"),
          "info_plist": artifact(app / "Contents/Info.plist"),
          "runner": artifact(root / "Tools/remote-research-peer/run.sh"),
          "swift_version": subprocess.check_output(["swiftc", "--version"], text=True).strip()}
(out / "build-provenance.json").write_text(json.dumps(result, indent=2) + "\n")
print("executable sha256: " + result["executable"]["sha256"])
PY
LAUNCH_STATUS=0
open -n -W -a "$APP" --args --stage "$STAGE" --out "$OUT" "$@" || LAUNCH_STATUS=$?
echo "--- summary"
cat "$OUT/summary.json" 2>/dev/null || echo "(no summary: the peer did not finish; see $OUT/events.jsonl)"
# open -W waits for termination; its status is not the peer's exit code.
python3 - "$OUT/summary.json" <<'PY'
import json, pathlib, sys
try:
    summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
    code = summary["exit_code"]
    if type(code) is not int or not 0 <= code <= 255:
        raise ValueError("invalid exit_code")
except (OSError, ValueError, KeyError, TypeError) as error:
    print("missing or invalid peer summary: " + str(error), file=sys.stderr)
    raise SystemExit(2)
raise SystemExit(code)
PY
exit "$LAUNCH_STATUS"
