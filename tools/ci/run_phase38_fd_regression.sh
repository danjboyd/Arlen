#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE38_OUTPUT_DIR:-$repo_root/build/release_confidence/phase38/fd_regression}"
phase10m_dir="$output_dir/phase10m_soak"
thresholds="${ARLEN_PHASE38_THRESHOLDS:-$repo_root/tests/fixtures/performance/phase38_fd_regression_thresholds.json}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

mkdir -p "$output_dir"
make boomhauer >/dev/null

python3 ./tools/ci/generate_phase10m_soak_artifacts.py \
  --repo-root "$repo_root" \
  --binary "$repo_root/build/boomhauer" \
  --thresholds "$thresholds" \
  --output-dir "$phase10m_dir"

python3 - "$repo_root" "$output_dir" "$phase10m_dir" <<'PY'
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

repo_root = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
phase10m_dir = Path(sys.argv[3])
summary_path = phase10m_dir / "soak_results.json"
payload = json.loads(summary_path.read_text(encoding="utf-8"))
phase38_violations = []
for item in payload.get("results", []):
    mode = item.get("mode", "unknown")
    deltas = item.get("deltas", {})
    file_body_failures = int(item.get("file_body_failures", 0))
    if file_body_failures > 0:
        phase38_violations.append(
            f"mode {mode}: file body failures {file_body_failures} exceed 0"
        )
    if int(deltas.get("dev_null_fd_count", 0)) > 4:
        phase38_violations.append(
            f"mode {mode}: /dev/null fd delta {deltas.get('dev_null_fd_count')} > 4"
        )
    if int(deltas.get("fd_count", 0)) > 96:
        phase38_violations.append(
            f"mode {mode}: fd delta {deltas.get('fd_count')} > 96"
        )
    if int(deltas.get("regular_file_fd_count", 0)) > 96:
        phase38_violations.append(
            f"mode {mode}: regular file fd delta {deltas.get('regular_file_fd_count')} > 96"
        )
    if int(deltas.get("socket_fd_count", 0)) > 96:
        phase38_violations.append(
            f"mode {mode}: socket fd delta {deltas.get('socket_fd_count')} > 96"
        )

status = "fail" if phase38_violations else "pass"
result = {
    "schema": "arlen-phase38-fd-regression-v1",
    "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "git_commit": subprocess.check_output(
        ["git", "-C", str(repo_root), "rev-parse", "HEAD"], text=True
    ).strip(),
    "phase10m_summary": str(summary_path.relative_to(output_dir)),
    "status": status,
    "modes": [item.get("mode") for item in payload.get("results", [])],
    "violations": phase38_violations,
    "phase10m_violations": payload.get("violations", []),
    "notes": [
        "Phase 38 FD regression is an Arlen-only tripwire.",
        "Downstream staging remains the authoritative reproduction route for ARLEN-BUG-024.",
        "The gate fails on file-body failures or FD target drift above Phase 38 thresholds.",
        "General keep-alive health request failures remain visible in the Phase 10M artifact but are not the Phase 38 pass/fail signal.",
    ],
}
(output_dir / "phase38_fd_regression_summary.json").write_text(
    json.dumps(result, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
if phase38_violations:
    raise SystemExit(2)
PY

echo "ci: phase38 FD regression artifacts written to $output_dir"
