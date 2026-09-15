#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_BUILD="build/tests"
mkdir -p "$TEST_BUILD"
sources=()
for source in Sources/*.swift; do
    [[ "$source" == "Sources/GaugeApp.swift" ]] || sources+=("$source")
done
swiftc -parse-as-library -module-cache-path "$TEST_BUILD/ModuleCache" \
    "${sources[@]}" Tests/*.swift -o "$TEST_BUILD/ProviderTests"
"$TEST_BUILD/ProviderTests" "$@"
