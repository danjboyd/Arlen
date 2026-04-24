#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE37_OUTPUT_DIR:-$repo_root/build/release_confidence/phase37}"
output="$output_dir/packaged_deploy_proof.json"
mkdir -p "$output_dir"

required_tests=(
  "testPackagedReleaseShipsDeployHelpersAndPackagedCLIActivates_ARLEN_BUG_016"
  "testPackagedReleaseRuntimeLaunchersPreferPackagedBinary_ARLEN_BUG_018"
  "testArlenDeployStatusRollbackDoctorAndLogsCommandsReportActiveReleaseState"
  "testReleasePackagingDereferencesCompiledRuntimeSymlink_ARLEN_BUG_018"
)

missing=()
for test_name in "${required_tests[@]}"; do
  if ! grep -q "$test_name" "$repo_root/tests/integration/DeploymentIntegrationTests.m"; then
    missing+=("$test_name")
  fi
done

status="pass"
if ((${#missing[@]} > 0)); then
  status="fail"
fi

python3 - "$output" "$status" "${missing[@]}" <<'PY'
import json
import sys
from pathlib import Path

output = Path(sys.argv[1])
status = sys.argv[2]
missing = sys.argv[3:]
payload = {
    "version": "phase37-packaged-deploy-proof-v1",
    "status": status,
    "proof_type": "existing-real-integration-coverage",
    "referenced_lane": "tests/integration/DeploymentIntegrationTests.m",
    "required_tests": [
        "testPackagedReleaseShipsDeployHelpersAndPackagedCLIActivates_ARLEN_BUG_016",
        "testPackagedReleaseRuntimeLaunchersPreferPackagedBinary_ARLEN_BUG_018",
        "testArlenDeployStatusRollbackDoctorAndLogsCommandsReportActiveReleaseState",
        "testReleasePackagingDereferencesCompiledRuntimeSymlink_ARLEN_BUG_018",
    ],
    "missing_tests": missing,
    "run_full_lane": "make test-integration-filter TEST=DeploymentIntegrationTests",
}
output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if [[ "$status" != "pass" ]]; then
  printf 'phase37-packaged-deploy-proof: missing required tests: %s\n' "${missing[*]}" >&2
  exit 1
fi

echo "phase37-packaged-deploy-proof: verified packaged deploy integration proof references"
