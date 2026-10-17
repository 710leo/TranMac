#!/bin/bash
# Build TranMac.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/TranMac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/TranMac" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x TranMac || true
  rm -rf /Applications/TranMac.app
  cp -R "$APP" /Applications/
  sleep 1
  open /Applications/TranMac.app
  echo "installed /Applications/TranMac.app"
fi
