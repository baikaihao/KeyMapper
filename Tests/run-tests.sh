#!/bin/bash
set -euo pipefail

# Compile the production recorder/models/state/store without starting a global event tap.
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/keymapper-modifier-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Sources" "$test_dir/Tests"
cp "$repo_dir/Engine/MyEngine.swift" "$repo_dir/Views/RadialWheel.swift" "$repo_dir/Views/KeyLogic.swift" "$repo_dir/Models/MyMap.swift" "$repo_dir/Models/ModifierMapping.swift" \
   "$repo_dir/Engine/ModifierRemappingState.swift" "$repo_dir/Services/MappingStore.swift" "$test_dir/Sources/"
cp "$repo_dir/Tests/ModifierMappingTests.swift" "$test_dir/Tests/"
cat > "$test_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "KeyMapperCoreTests",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "KeyMapperCore", path: "Sources", swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "KeyMapperCoreTests", dependencies: ["KeyMapperCore"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
SWIFT
swift test --package-path "$test_dir"
