#!/usr/bin/env bash
# Gating clang static analyzer (scan-build) lane for first-party code.
#
# Rebuilds the framework, boomhauer and tech-demo-server from a clean build/
# with every compile routed through scan-build's analyzer wrapper (via the
# GNUmakefile's ARLEN_CC), then fails if any report is not in the accepted
# baseline. Vendored code under src/Arlen/Support/third_party is excluded.
#
# Environment:
#   ARLEN_STATIC_SCAN_BUILD          scan-build binary (default: scan-build, then scan-build-<clang major>)
#   ARLEN_STATIC_SCAN_BUILD_OUTPUT   report directory (default: build/static_analysis/scan_build)
#   ARLEN_STATIC_SCAN_BUILD_BASELINE baseline JSON (default: tests/fixtures/static_analysis/scan_build_baseline.json)
#   ARLEN_STATIC_JOBS                make parallelism (default: 4)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
source "$repo_root/tools/ci/lib/static_analysis_tools.sh"

output_dir="${ARLEN_STATIC_SCAN_BUILD_OUTPUT:-$repo_root/build/static_analysis/scan_build}"
baseline="${ARLEN_STATIC_SCAN_BUILD_BASELINE:-$repo_root/tests/fixtures/static_analysis/scan_build_baseline.json}"
jobs="${ARLEN_STATIC_JOBS:-4}"

set +u
source "$repo_root/tools/source_gnustep_env.sh"
set -u

python3 ./tools/ci/test_static_scan_build_gate.py

if ! scan_build="$(aln_static_resolve_llvm_tool scan-build "${ARLEN_STATIC_SCAN_BUILD:-}")"; then
  echo "ci: scan-build not found; install the clang-tools package matching your clang" >&2
  exit 2
fi
real_cc="$(command -v clang)"
echo "ci: static scan-build lane using $scan_build with $real_cc ($(clang -dumpversion))"

aln_static_clean_build_dir "$repo_root"
mkdir -p "$output_dir"

# scan-build exports CC as its ccc-analyzer wrapper; hand it to ARLEN_CC so
# every recipe compiles for real and runs the analyzer. scan-build exits with
# make's status, so a broken build fails the lane.
# security.insecureAPI.DeprecatedOrUnsafeBufferHandling flags every memcpy/
# snprintf in favor of C11 Annex K, which glibc does not provide; nullability
# needs annotations the codebase does not use.
"$scan_build" --use-cc="$real_cc" -o "$output_dir" \
  --exclude "$repo_root/src/Arlen/Support/third_party" \
  --exclude "$repo_root/build" \
  -enable-checker core \
  -enable-checker unix \
  -enable-checker security \
  -enable-checker deadcode \
  -enable-checker osx.cocoa \
  -disable-checker security.insecureAPI.DeprecatedOrUnsafeBufferHandling \
  -disable-checker nullability \
  bash -c 'exec make -j"$1" ARLEN_CC="$CC" all boomhauer tech-demo-server' _ "$jobs"

python3 ./tools/ci/static_scan_build_gate.py \
  --reports "$output_dir" \
  --root "$repo_root" \
  --baseline "$baseline"

echo "ci: static scan-build gate complete"
