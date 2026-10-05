#!/bin/bash
# Test the research app's shared lifecycle code offline; no native peer or app loop is compiled.
#   Tools/remote-research-peer/test.sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PEER_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/logicctl-peer-offline.XXXXXX")"
trap 'rm -rf "$PEER_TEST_DIR"' EXIT
swiftc -D RESEARCH_PEER_OFFLINE_TEST \
  "$ROOT/Tools/remote-research-peer/main.swift" \
  "$ROOT/Sources/LogicCore/Backends/Remote/RemoteFrame.swift" \
  "$ROOT/Tools/remote-research-peer/OfflineTests.swift" \
  -o "$PEER_TEST_DIR/lifecycle-tests"
"$PEER_TEST_DIR/lifecycle-tests"
