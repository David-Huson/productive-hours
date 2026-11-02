#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/swift-local.sh test --enable-code-coverage
./scripts/swift-local.sh build --product CrashHarness
fixture_bin="$(./scripts/swift-local.sh build --show-bin-path)/CrashHarness"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/productive-hours-crash.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
for scenario in committed uncommitted; do
    set +e
    "$fixture_bin" "$scenario" "$fixture_dir/$scenario.sqlite"
    result=$?
    set -e
    test "$result" -eq 77
    "$fixture_bin" verify "$fixture_dir/$scenario.sqlite"
done
PRODUCTIVE_HOURS_APP_DIR="$PWD/.build/verification/Worktempo.app" ./scripts/build-app.sh
plutil -lint '.build/verification/Worktempo.app/Contents/Info.plist'
codesign --verify --strict '.build/verification/Worktempo.app'
