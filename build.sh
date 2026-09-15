#!/bin/bash
# Build Gauge.app and (with --install) copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Gauge.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BUILD_ARCH="$(uname -m)"
swiftc -O -parse-as-library -target "${BUILD_ARCH}-apple-macosx14.0" Sources/*.swift -o "$APP/Contents/MacOS/Gauge"
swift tools/icon.swift build/GaugeIcon.iconset
iconutil -c icns build/GaugeIcon.iconset -o "$APP/Contents/Resources/GaugeIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    pkill -x Gauge 2>/dev/null || true
    rm -rf ~/Applications/Gauge.app
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/Gauge.app"
fi
