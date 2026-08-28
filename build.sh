#!/bin/bash
# Build ClaudeSwitch.app and (with --install) copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ClaudeSwitch.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/ClaudeSwitch"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/*.png Resources/*.icns "$APP/Contents/Resources/" 2>/dev/null || true
codesign --force -s - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    pkill -x ClaudeSwitch 2>/dev/null || true
    rm -rf ~/Applications/ClaudeSwitch.app
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/ClaudeSwitch.app"
fi
