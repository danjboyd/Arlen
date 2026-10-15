#!/usr/bin/env bash
# Builds and runs an app's XCTest bundle (tests/**/*.m) in process.
# Usage: tools/run_app_tests.sh <app-root> [--only Class[/method]]... [--skip Class[/method]]...
# Used by `arlen test --app`; see docs/TESTING_WORKFLOW.md.
set -euo pipefail

framework_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_root="${1:-}"
if [[ -z "$app_root" || ! -f "$app_root/config/app.plist" ]]; then
  echo "run_app_tests: expected an app root containing config/app.plist (got '${app_root}')" >&2
  exit 2
fi
app_root="$(cd "$app_root" && pwd -P)"
shift

filters=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      [[ $# -ge 2 ]] || { echo "run_app_tests: --only needs Class[/method]" >&2; exit 2; }
      filters+=("-only-testing:AppTests/$2")
      shift 2
      ;;
    --skip)
      [[ $# -ge 2 ]] || { echo "run_app_tests: --skip needs Class[/method]" >&2; exit 2; }
      filters+=("-skip-testing:AppTests/$2")
      shift 2
      ;;
    *)
      echo "run_app_tests: unknown option $1" >&2
      exit 2
      ;;
  esac
done

# macOS: build with the Apple toolchain and run under Xcode's xctest, which
# takes a comma-separated -XCTest Class[/method] list and has no skip option.
if [[ "$(uname -s)" == "Darwin" ]]; then
  apple_selectors=""
  for filter in ${filters[@]+"${filters[@]}"}; do
    case "$filter" in
      -skip-testing:*)
        echo "run_app_tests: --skip is not supported on macOS (Xcode's xctest has no skip filter)" >&2
        exit 2
        ;;
    esac
    apple_selectors="${apple_selectors:+$apple_selectors,}${filter#-only-testing:AppTests/}"
  done
  bundle="$("$framework_root/tools/build_apple_app.sh" --app-root "$app_root" --framework-root "$framework_root" \
    --build-tests --print-path)"
  export ARLEN_APP_ROOT="$app_root"
  export ARLEN_FRAMEWORK_ROOT="$framework_root"
  cd "$app_root"
  apple_args=()
  if [[ -n "$apple_selectors" ]]; then
    apple_args=(-XCTest "$apple_selectors")
  fi
  # Add the GNUstep runner's per-class summary lines ("HomeTests: 1 tests
  # PASSED", "MissingTests: 1/1 tests FAILED") after each class suite.
  set +e
  xcrun xctest ${apple_args[@]+"${apple_args[@]}"} "$bundle" 2>&1 | awk '
    { print }
    /^Test Suite .* (passed|failed) at / {
      suite = $0
      sub(/^Test Suite \047/, "", suite)
      sub(/\047 (passed|failed) at .*/, "", suite)
      next
    }
    /^[ \t]*Executed [0-9]+ tests?, with [0-9]+ failures?/ {
      if (suite != "" && suite !~ /\.xctest$/ && suite != "All tests" && suite != "Selected tests") {
        total = $2
        failed = $5
        if (failed == 0) {
          printf "%s: %d tests PASSED\n", suite, total
        } else {
          printf "%s: %d/%d tests FAILED\n", suite, failed, total
        }
      }
      suite = ""
    }'
  exit "${PIPESTATUS[0]}"
fi

(cd "$app_root" && ARLEN_FRAMEWORK_ROOT="$framework_root" "$framework_root/bin/boomhauer" --build-tests)

# shellcheck source=tools/source_gnustep_env.sh
source "$framework_root/tools/source_gnustep_env.sh" >/dev/null

# Prefer the framework's vendored runner (Apple-style -only-testing filters),
# building or refreshing it as needed; fall back to the toolchain's xctest.
runner="$framework_root/vendor/tools-xctest/obj/xctest"
runner_lib_dir=""
if [[ -f "$framework_root/vendor/tools-xctest/GNUmakefile" ]]; then
  make -C "$framework_root" vendored-xctest >/dev/null
fi
if [[ -x "$runner" ]]; then
  runner_lib_dir="$framework_root/vendor/tools-xctest/XCTest/obj"
else
  runner="$(command -v xctest || true)"
  if [[ -z "$runner" ]]; then
    echo "run_app_tests: no xctest runner found (vendored or on PATH)" >&2
    exit 1
  fi
fi

# Isolated GNUstep defaults so tests never touch the user's domain or its lock.
test_home="$app_root/.boomhauer/test-home"
mkdir -p "$test_home/GNUstep/Defaults/.lck"
export HOME="$test_home"
export GNUSTEP_USER_DIR="$test_home/GNUstep"
export GNUSTEP_USER_ROOT="$test_home/GNUstep"
export GNUSTEP_USER_DEFAULTS_DIR="$test_home/GNUstep/Defaults"
if [[ -n "$runner_lib_dir" ]]; then
  export LD_LIBRARY_PATH="$runner_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export ARLEN_APP_ROOT="$app_root"
cd "$app_root"
exec "$runner" ${filters[@]+"${filters[@]}"} "$app_root/.boomhauer/build/tests/AppTests.xctest"
