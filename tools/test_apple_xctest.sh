#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=tools/platform.sh
source "$script_dir/platform.sh"

if ! aln_platform_is_macos; then
  echo "test-apple-xctest: this helper only supports macOS" >&2
  exit 1
fi

suite="unit"
filter=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite)
      suite="$2"
      shift 2
      ;;
    --filter)
      filter="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: test_apple_xctest.sh [--suite unit] [--filter Class/testMethod]

Builds and runs Apple XCTest bundles for the supported Arlen Objective-C suites.
USAGE
      exit 0
      ;;
    *)
      echo "test-apple-xctest: unknown option $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find xctest >/dev/null 2>&1; then
  echo "test-apple-xctest: xctest is unavailable via xcrun" >&2
  exit 1
fi

bundle_path="$("$repo_root/tools/build_apple_xctest.sh" --suite "$suite" --print-bundle-path)"

cd "$repo_root"
export ARLEN_FRAMEWORK_ROOT="$repo_root"

if [[ -n "$filter" ]]; then
  exec xcrun xctest -XCTest "$filter" "$bundle_path"
fi

exec xcrun xctest "$bundle_path"
