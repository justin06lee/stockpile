#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="Stockpile.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/StockpileApp "$APP/Contents/MacOS/StockpileApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/stockpile.icns "$APP/Contents/Resources/stockpile.icns"
cp Resources/stockpile_taskbar.png "$APP/Contents/Resources/stockpile_taskbar.png"

# Ad-hoc sign for local use (no sandbox entitlements = full disk access prompts).
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run: open $APP   (grant access if macOS prompts)"
