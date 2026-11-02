#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_ID:?Set DEVELOPER_ID to your Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a configured notarytool keychain profile}"
./scripts/swift-local.sh test
export BUILD_CONFIGURATION=release
export PRODUCTIVE_HOURS_APP_DIR="$PWD/.build/release-artifacts/Productive Hours.app"
./scripts/build-app.sh
archive="$PWD/.build/release-artifacts/ProductiveHours.zip"
ditto -c -k --sequesterRsrc --keepParent "$PRODUCTIVE_HOURS_APP_DIR" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$PRODUCTIVE_HOURS_APP_DIR"
xcrun stapler validate "$PRODUCTIVE_HOURS_APP_DIR"
spctl --assess --type execute --verbose "$PRODUCTIVE_HOURS_APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$PRODUCTIVE_HOURS_APP_DIR" "$archive"
printf '%s\n' "$archive"
