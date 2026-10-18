#!/usr/bin/env bash
# Nightly lane (issue 271): run the integration suite against an ASAN+UBSan
# build. Not a merge gate; see docs/CI_ALIGNMENT.md.
#
# - The framework, tools and test bundles build with clang's shared sanitizer
#   runtime (-shared-libsan), and the xctest runner preloads that same runtime,
#   so instrumented child processes (build/boomhauer, the tech-demo servers)
#   and the runner agree on one runtime.
# - Reports from every process go to build/sanitizers/integration_nightly/
#   through log_path. A report that touches Arlen code fails the lane. A report
#   raised inside a /usr/bin tool that inherited the preload (make, dd) does not.
# - Tests that build app roots through bin/boomhauer/bin/arlen are skipped
#   (tests/fixtures/sanitizers/integration_nightly_skips.txt): boomhauer runs
#   `make clean` on a sanitizer-instrumented framework, wiping build/ mid-run.
#   The lane fails if the skip list is stale, or if the instrumented framework
#   archive was replaced during the run.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_INTEGRATION_SANITIZER_OUTPUT_DIR:-$repo_root/build/sanitizers/integration_nightly}"
jobs="${ARLEN_INTEGRATION_SANITIZER_JOBS:-4}"

set +u
source "$repo_root/tools/source_gnustep_env.sh"
set -u

python3 -I ./tools/ci/classify_sanitizer_integration_skips.py --check

resource_dir="$(clang -print-resource-dir)"
asan_runtime=""
for candidate in "$resource_dir/lib/linux/libclang_rt.asan-x86_64.so" \
                 "$resource_dir/lib/x86_64-unknown-linux-gnu/libclang_rt.asan.so"; do
  if [[ -f "$candidate" ]]; then
    asan_runtime="$candidate"
    break
  fi
done
if [[ -z "$asan_runtime" ]]; then
  echo "integration sanitizers: clang's shared ASan runtime is missing under $resource_dir" >&2
  exit 1
fi
runtime_dir="$(dirname "$asan_runtime")"

make clean
rm -rf "$output_dir"
mkdir -p "$output_dir/reports"
# make clean empties build/, so the output directory is created afterwards.

export EXTRA_OBJC_FLAGS="-fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -shared-libsan -Wl,-rpath,$runtime_dir -Wno-unused-command-line-argument"
export ASAN_OPTIONS="detect_leaks=0:halt_on_error=1:strict_string_checks=1:abort_on_error=0:log_path=$output_dir/reports/asan"
export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1:log_path=$output_dir/reports/ubsan"

# Instrumented build tools (eocc) report into the same directory.
make -j"$jobs" build-tests boomhauer vendored-xctest

framework_lib="$repo_root/build/lib/libArlenFramework.a"
# grep -c reads all of nm's output; grep -q would SIGPIPE nm under pipefail.
if [[ "$(nm -A "$framework_lib" 2>/dev/null | grep -c '__asan_' || true)" == "0" ]]; then
  echo "integration sanitizers: $framework_lib is not instrumented" >&2
  exit 1
fi
framework_fingerprint="$(stat -c '%i %Y %s' "$framework_lib")"

vendored_xctest="$repo_root/vendor/tools-xctest/obj/xctest"
wrapper="$output_dir/xctest_with_skips.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'exec %q "$@"' "$vendored_xctest"
  while IFS= read -r arg; do
    printf ' %q' "$arg"
  done < <(python3 -I ./tools/ci/classify_sanitizer_integration_skips.py --print-args)
  printf '\n'
} >"$wrapper"
chmod +x "$wrapper"

set +e
make test-integration \
  ARLEN_XCTEST="$wrapper" \
  XCTEST_LD_PRELOAD="$asan_runtime" 2>&1 | tee "$output_dir/test-integration.log"
suite_status=${PIPESTATUS[0]}
set -e

lane_status=0
if [[ "$(stat -c '%i %Y %s' "$framework_lib" 2>/dev/null || true)" != "$framework_fingerprint" ]]; then
  echo "integration sanitizers: build/lib/libArlenFramework.a was replaced during the run;" \
       "a test that rebuilds the framework (bin/boomhauer) is missing from the skip list" >&2
  lane_status=1
fi

if ! python3 -I ./tools/ci/summarize_sanitizer_reports.py \
     --repo-root "$repo_root" \
     --reports-dir "$output_dir/reports" \
     --test-log "$output_dir/test-integration.log" \
     --output "$output_dir/summary.json"; then
  lane_status=1
fi

if [[ "$suite_status" -ne 0 ]]; then
  echo "integration sanitizers: the integration suite failed (exit $suite_status)" >&2
  lane_status=1
fi

if [[ "$lane_status" -eq 0 ]]; then
  echo "ci: integration sanitizer nightly lane complete"
fi
exit "$lane_status"
