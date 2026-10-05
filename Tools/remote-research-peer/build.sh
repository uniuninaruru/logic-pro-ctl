#!/bin/bash
# Build the research peer as a small app bundle (an ad-hoc signature of its own; nothing of Logic is touched).
#   Tools/remote-research-peer/build.sh   ->  .build/remote-research-peer/LogicctlResearchPeer.app
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/.build/remote-research-peer/LogicctlResearchPeer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -suppress-warnings -o "$APP/Contents/MacOS/peer" \
  "$ROOT/Tools/remote-research-peer/main.swift" "$ROOT/Sources/LogicCore/Backends/Remote/RemoteFrame.swift" \
  -framework MultipeerConnectivity -framework AppKit 2>&1 | grep -v "^$" || true
[ -x "$APP/Contents/MacOS/peer" ] || { echo "build failed" >&2; exit 1; }
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.logicctl.research-peer</string>
  <key>CFBundleName</key><string>LogicctlResearchPeer</string>
  <key>CFBundleExecutable</key><string>peer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Receive-only research peer that listens to the Logic Remote advertisement on this Mac (logicctl PLAN-05). / このMac上のLogic Remoteの広告を受信だけする研究用ピアです。</string>
  <key>NSBonjourServices</key><array><string>_apple-lgremote._tcp</string><string>_apple-lgremote._udp</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "$APP"
