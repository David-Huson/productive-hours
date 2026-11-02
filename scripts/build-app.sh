#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/swift-local.sh build --configuration "${BUILD_CONFIGURATION:-debug}" --product ProductiveHours
bin_dir="$(./scripts/swift-local.sh build --configuration "${BUILD_CONFIGURATION:-debug}" --show-bin-path)"
app_dir="${PRODUCTIVE_HOURS_APP_DIR:-$PWD/.build/Productive Hours.app}"
mkdir -p "$app_dir/Contents/MacOS"
cp "$bin_dir/ProductiveHours" "$app_dir/Contents/MacOS/ProductiveHours"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.productivehours.app</string>
<key>CFBundleName</key><string>Productive Hours</string>
<key>CFBundleExecutable</key><string>ProductiveHours</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>0.1.2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>With your permission, read the active Chrome, Edge or Arc tab hostname to classify productive time. Page content and full URLs are not stored.</string>
</dict></plist>
PLIST
codesign --force --options runtime --entitlements Resources/ProductiveHours.entitlements --sign "${DEVELOPER_ID:--}" "$app_dir"
codesign --verify --strict "$app_dir"
printf '%s\n' "$app_dir"
