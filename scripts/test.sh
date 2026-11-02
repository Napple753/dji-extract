#!/bin/sh
# Run the package tests with only the Command Line Tools installed (no Xcode).
# The CLT ship Swift Testing outside the default search paths, and the default
# build system fails without Xcode, so point at both explicitly. The SwiftUI
# target needs Xcode (macro plugin) and is left out; see typecheck-ui.sh.
set -e
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools/Library/Developer
DJI_EXTRACT_SKIP_UI=1 exec swift test --build-system native \
  -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
  -Xlinker -F -Xlinker "$CLT/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/usr/lib" \
  "$@"
