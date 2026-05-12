#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=tools/platform.sh
source "$repo_root/tools/platform.sh"

if ! aln_platform_is_macos; then
  echo "apple-xctest-smoke: this helper only supports macOS" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "apple-xctest-smoke: xcrun is required" >&2
  exit 1
fi

if ! xcrun --find xctest >/dev/null 2>&1; then
  echo "apple-xctest-smoke: xctest is unavailable via xcrun" >&2
  echo "apple-xctest-smoke: activate full Xcode with 'sudo xcode-select -s /Applications/Xcode.app/Contents/Developer'" >&2
  exit 1
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-apple-xctest.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT

(
  cd "$work_root"
  swift package init --type library >/dev/null
)

test_file="$(find "$work_root/Tests" -type f -name '*.swift' | head -n 1)"
if [[ -z "$test_file" ]]; then
  echo "apple-xctest-smoke: failed to locate generated test file" >&2
  exit 1
fi

cat >"$test_file" <<'EOF'
import XCTest
@testable import arlen_apple_xctest

final class ArlenAppleXCTestSmokeTests: XCTestCase {
    func testExample() {
        XCTAssertEqual(2 + 2, 4)
    }
}
EOF

package_file="$work_root/Package.swift"
cat >"$package_file" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "arlen_apple_xctest",
    products: [
        .library(
            name: "arlen_apple_xctest",
            targets: ["arlen_apple_xctest"]
        ),
    ],
    targets: [
        .target(
            name: "arlen_apple_xctest"
        ),
        .testTarget(
            name: "arlen_apple_xctestTests",
            dependencies: ["arlen_apple_xctest"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
EOF

(cd "$work_root" && swift test)

echo "apple-xctest-smoke: passed"
