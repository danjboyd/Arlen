#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

venv_dir="${ARLEN_FASTAPI_VENV:-$repo_root/build/venv/fastapi_parity}"
requirements_file="$repo_root/tests/performance/fastapi_reference/requirements.txt"
report_file="${ARLEN_PHASEB_PARITY_REPORT:-$repo_root/build/perf/parity_fastapi_latest.json}"

python3 -m venv "$venv_dir"
source "$venv_dir/bin/activate"

python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install -r "$requirements_file" >/dev/null

make boomhauer >/dev/null

python3 tests/performance/check_parity_fastapi.py \
  --repo-root "$repo_root" \
  --arlen-bin "./build/boomhauer" \
  --fastapi-app-dir "tests/performance/fastapi_reference" \
  --python-bin "python3" \
  --output "$report_file"

echo "phaseb parity: complete report=$report_file"
