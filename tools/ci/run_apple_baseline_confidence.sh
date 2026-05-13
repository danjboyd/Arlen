#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE30_OUTPUT_DIR:-$repo_root/build/release_confidence/phase30}"

mkdir -p "$output_dir"

doctor_json="$output_dir/doctor.json"
toolchain_json="$output_dir/toolchain.json"
build_log="$output_dir/build_apple.log"
xctest_log="$output_dir/apple_xctest_smoke.log"
runtime_log="$output_dir/apple_runtime_smoke.log"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "phase30-confidence: this lane only supports macOS" >&2
  exit 1
fi

"$repo_root/bin/arlen" doctor --json >"$doctor_json"

python3 - "$toolchain_json" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

output_path = Path(sys.argv[1])

def run(*argv):
    return subprocess.check_output(argv, text=True).strip()

payload = {
    "active_developer_dir": run("xcode-select", "-p"),
    "xcode_version": run("xcodebuild", "-version"),
    "sdk_path": run("xcrun", "--show-sdk-path"),
    "clang_path": run("xcrun", "--find", "clang"),
    "xctest_path": run("xcrun", "--find", "xctest"),
    "swift_version": run("swift", "--version"),
}

try:
    payload["brew_prefix"] = run("brew", "--prefix")
    payload["openssl_prefix"] = run("brew", "--prefix", "openssl@3")
except Exception:
    payload["brew_prefix"] = ""
    payload["openssl_prefix"] = ""

output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

"$repo_root/tools/apple_xctest_smoke.sh" >"$xctest_log" 2>&1
"$repo_root/bin/build-apple" --with-boomhauer >"$build_log" 2>&1
"$repo_root/bin/test" --smoke-only >"$runtime_log" 2>&1

python3 "$repo_root/tools/ci/generate_phase30_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --doctor "$doctor_json" \
  --toolchain "$toolchain_json" \
  --build-log "$build_log" \
  --xctest-log "$xctest_log" \
  --runtime-log "$runtime_log" \
  --repo-root "$repo_root"
