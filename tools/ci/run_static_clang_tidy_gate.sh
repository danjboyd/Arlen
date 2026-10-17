#!/usr/bin/env bash
# Gating clang-tidy lane for first-party src/ and modules/ sources.
#
# Rebuilds the framework, boomhauer and tech-demo-server from a clean build/
# under intercept-build to record compile_commands.json, then runs clang-tidy
# on every first-party translation unit (vendored third_party code excluded)
# with warnings treated as errors. There is no baseline: the lane is clean.
# A clang-tidy crash also fails the lane.
#
# Environment:
#   ARLEN_STATIC_CLANG_TIDY        clang-tidy binary (default: clang-tidy on PATH; CI pins 22.1.8 from PyPI)
#   ARLEN_STATIC_INTERCEPT_BUILD   intercept-build binary (default: intercept-build, then intercept-build-<clang major>)
#   ARLEN_STATIC_CLANG_TIDY_OUTPUT output directory (default: build/static_analysis/clang_tidy)
#   ARLEN_STATIC_JOBS              make and clang-tidy parallelism (default: 4)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
source "$repo_root/tools/ci/lib/static_analysis_tools.sh"

output_dir="${ARLEN_STATIC_CLANG_TIDY_OUTPUT:-$repo_root/build/static_analysis/clang_tidy}"
jobs="${ARLEN_STATIC_JOBS:-4}"

set +u
source "$repo_root/tools/source_gnustep_env.sh"
set -u

if ! clang_tidy="$(aln_static_resolve_llvm_tool clang-tidy "${ARLEN_STATIC_CLANG_TIDY:-}")"; then
  echo "ci: clang-tidy not found; install it with: pip install clang-tidy==22.1.8" >&2
  exit 2
fi
if ! intercept_build="$(aln_static_resolve_llvm_tool intercept-build "${ARLEN_STATIC_INTERCEPT_BUILD:-}")"; then
  echo "ci: intercept-build not found; install the clang-tools package matching your clang" >&2
  exit 2
fi
echo "ci: static clang-tidy lane using $("$clang_tidy" --version | grep -m1 -i version)"

aln_static_clean_build_dir "$repo_root"
mkdir -p "$output_dir/logs"

if ! "$intercept_build" --cdb "$output_dir/compile_commands.json" \
    make -j"$jobs" all boomhauer tech-demo-server >"$output_dir/build.log" 2>&1; then
  tail -n 50 "$output_dir/build.log" >&2
  echo "ci: build failed under intercept-build (see $output_dir/build.log)" >&2
  exit 2
fi

python3 - "$output_dir/compile_commands.json" "$repo_root" >"$output_dir/files.txt" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    db = json.load(handle)
root = os.path.realpath(sys.argv[2]) + os.sep
files = sorted({os.path.normpath(os.path.join(e["directory"], e["file"])) for e in db})
for path in files:
    rel = path[len(root):] if path.startswith(root) else path
    if rel.startswith(("src/", "modules/")) and "third_party" not in rel:
        print(path)
PY
file_count="$(wc -l <"$output_dir/files.txt")"
if [[ "$file_count" -eq 0 ]]; then
  echo "ci: no first-party translation units found in compile_commands.json" >&2
  exit 2
fi

# Excluded checks:
# - misc-no-recursion: crashes clang-tidy on Objective-C block literals.
# - clang-analyzer-*: covered by the scan-build lane at lower cost.
# - the bugprone/cert entries below are style or false-positive heavy on this
#   codebase (parameter ordering, implicit conversions, reserved identifiers,
#   unchecked printf-family returns, strto* conversions).
checks='-*,bugprone-*,cert-*'
checks+=',objc-avoid-nserror-init,objc-dealloc-in-category,objc-missing-hash'
checks+=',objc-nsinvocation-argument-lifetime,objc-super-self'
checks+=',-bugprone-easily-swappable-parameters,-bugprone-narrowing-conversions'
checks+=',-bugprone-branch-clone,-bugprone-assignment-in-if-condition'
checks+=',-bugprone-multi-level-implicit-pointer-conversion,-bugprone-inc-dec-in-conditions'
checks+=',-bugprone-implicit-widening-of-multiplication-result'
checks+=',-bugprone-unchecked-string-to-number-conversion,-bugprone-reserved-identifier'
checks+=',-cert-err33-c,-cert-err34-c,-cert-dcl37-c,-cert-dcl51-cpp'

export ALN_TIDY_BIN="$clang_tidy" ALN_TIDY_CDB="$output_dir" ALN_TIDY_LOGS="$output_dir/logs" ALN_TIDY_CHECKS="$checks"
: >"$output_dir/failures.txt"
xargs -a "$output_dir/files.txt" -P "$jobs" -I{} bash -c '
  log="$ALN_TIDY_LOGS/$(basename "$1").txt"
  if ! "$ALN_TIDY_BIN" -p "$ALN_TIDY_CDB" --quiet -checks="$ALN_TIDY_CHECKS" \
      --warnings-as-errors="*" \
      -header-filter=".*/(src|modules)/.*" -exclude-header-filter=".*third_party.*" \
      "$1" >"$log" 2>&1; then
    echo "FAIL $1"
  fi
' _ {} >>"$output_dir/failures.txt"

if [[ -s "$output_dir/failures.txt" ]]; then
  cat "$output_dir/failures.txt"
  grep -h -E "(warning|error):|Stack dump|PLEASE submit a bug report" "$output_dir"/logs/*.txt | sort -u || true
  echo "ci: static clang-tidy gate failed ($(wc -l <"$output_dir/failures.txt") of $file_count files; logs in $output_dir/logs)" >&2
  exit 1
fi
echo "ci: static clang-tidy gate clean ($file_count files)"
