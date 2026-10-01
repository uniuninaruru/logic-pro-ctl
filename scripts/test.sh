#!/bin/bash
# swift test that also works with Command Line Tools only: CLT ships the
# Swift Testing macro plugin under plugins/testing/, which SwiftPM does not
# put on the plugin path (or Testing.framework on the rpath) by itself.
set -eu
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
PLUGINS="$DEV/usr/lib/swift/host/plugins/testing"
FRAMEWORKS="$DEV/Library/Developer/Frameworks"
if [ -d "$PLUGINS" ] && [ ! -d "$DEV/Platforms" ]; then
  # Command Line Tools: also put Testing.framework on the runtime path.
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$DEV/Library/Developer/usr/lib" "$@"
fi
exec swift test "$@"
