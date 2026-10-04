#!/bin/bash
# Every offline test in one go; none of them needs Logic:
#   1. the Swift tests (./scripts/test.sh),
#   2. the unit tests of the research scripts (Tools/research-scripts, Tools/ghidra),
#   3. the CLI integration tests against fake daemons (Tests/integration/test_cli_*.py).
# The live spot check on the real Logic, Tests/integration/live_smoke.py, is separate and does need it.
set -eu
cd "$(dirname "$0")/.."

./scripts/test.sh
swift build

for dir in Tools/research-scripts Tools/ghidra; do
  for file in "$dir"/test_*.py; do
    [ -e "$file" ] || continue
    echo "== $file"
    (cd "$dir" && python3 -m unittest "$(basename "${file%.py}")")
  done
done

for file in Tests/integration/test_cli_*.py; do
  echo "== $file"
  python3 "$file" .build/debug/logicctl
done
echo "all offline tests passed"
