#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep compiler/package caches inside the project in restricted workspaces.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
command="${1:?Expected a SwiftPM command such as build, test or run}"
shift
toolchain_bin="$(dirname "$(xcrun --find swiftc)")"
exec swift "$command" --cache-path "$PWD/.build/cache" --disable-sandbox -Xswiftc -plugin-path -Xswiftc "$toolchain_bin/../lib/swift/host/plugins/testing" "$@"
