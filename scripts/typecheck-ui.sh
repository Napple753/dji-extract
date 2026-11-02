#!/bin/sh
# Type-check the SwiftUI target with only the Command Line Tools installed.
# The CLT lack SwiftUI's macro plugin, so a scratch copy of the package replaces
# @State with a plain property wrapper. Not a substitute for an Xcode build.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$ROOT/Package.swift" "$ROOT/Sources" "$ROOT/Tests" "$WORK/"
sed -i '' 's/@State /@StateShim /g' "$WORK"/Sources/DJIExtractUI/*.swift
cat > "$WORK/Sources/DJIExtractUI/_StateShim.swift" <<'SWIFT'
import SwiftUI
@propertyWrapper struct StateShim<Value>: DynamicProperty, @unchecked Sendable {
    final class Box { var value: Value; init(_ v: Value) { value = v } }
    private let box: Box
    init(wrappedValue: Value) { box = Box(wrappedValue) }
    var wrappedValue: Value { get { box.value } nonmutating set { box.value = newValue } }
    var projectedValue: Binding<Value> { Binding(get: { box.value }, set: { box.value = $0 }) }
}
SWIFT
cd "$WORK"
swift build --build-system native --target DJIExtractUI 2>&1 | grep -v 'deprecated and will be removed'
