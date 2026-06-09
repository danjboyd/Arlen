#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE31_OUTPUT_DIR:-$repo_root/build/release_confidence/phase31}"

mkdir -p "$output_dir"

source "$repo_root/tools/source_gnustep_env.sh"

make -C "$repo_root" arlen >/dev/null
make -C "$repo_root" build-tests >/dev/null

app_parent="$(mktemp -d "${TMPDIR:-/tmp}/arlen-phase31-app-XXXXXX")"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-phase31-work-XXXXXX")"
trap 'rm -rf "$app_parent" "$work_root"' EXIT

new_app_log="$output_dir/new_app.log"
smoke_json="$output_dir/release_smoke.json"
doctor_json="$output_dir/deploy_doctor_base_url.json"
packaged_server_log="$output_dir/packaged_server.log"
jobs_worker_log="$output_dir/jobs_worker_once.log"
exe_doctor_json="$output_dir/exe_manifest_doctor.json"

(
  cd "$app_parent"
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" new Phase31ConfidenceApp --full
) >"$new_app_log" 2>&1
app_root="$app_parent/Phase31ConfidenceApp"
cat >"$app_root/config/environments/production.plist" <<'EOF'
{
  logFormat = "json";
  database = {
    connectionString = "postgresql:///phase31_confidence";
    adapter = "postgresql";
  };
}
EOF

smoke_work_dir="$work_root/smoke"
mkdir -p "$smoke_work_dir"
port="${ARLEN_PHASE31_SMOKE_PORT:-3911}"

"$repo_root/tools/deploy/smoke_release.sh" \
  --app-root "$app_root" \
  --framework-root "$repo_root" \
  --work-dir "$smoke_work_dir" \
  --port "$port" \
  --release-a phase31-a \
  --release-b phase31-b \
  --json >"$smoke_json"

python3 - "$smoke_json" "$output_dir/packaged_release_manifest.json" "$output_dir/packaged_release_env.txt" <<'PY'
import json
import pathlib
import shutil
import sys

smoke_path = pathlib.Path(sys.argv[1])
manifest_copy = pathlib.Path(sys.argv[2])
release_env_copy = pathlib.Path(sys.argv[3])
with smoke_path.open("r", encoding="utf-8") as handle:
    smoke = json.load(handle)
current_release = pathlib.Path(smoke["current_release"])
shutil.copyfile(current_release / "metadata" / "manifest.json", manifest_copy)
shutil.copyfile(current_release / "metadata" / "release.env", release_env_copy)
PY

current_release="$(python3 - "$smoke_json" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)
print(payload["current_release"])
PY
)"
releases_dir="$(python3 - "$smoke_json" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)
print(payload["releases_dir"])
PY
)"

doctor_port="${ARLEN_PHASE31_DOCTOR_PORT:-3913}"

ARLEN_APP_ROOT="$current_release/app" \
ARLEN_FRAMEWORK_ROOT="$current_release/framework" \
"$current_release/framework/bin/propane" \
  --port "$doctor_port" \
  --pid-file "$current_release/app/tmp/phase31-confidence.pid" \
  >"$packaged_server_log" 2>&1 &
server_pid=$!
cleanup_server() {
  kill -TERM "$server_pid" >/dev/null 2>&1 || true
  wait "$server_pid" >/dev/null 2>&1 || true
}
trap 'cleanup_server; rm -rf "$app_parent" "$work_root"' EXIT

python3 - "$doctor_port" <<'PY'
import sys
import time
import urllib.request

port = int(sys.argv[1])
url = f"http://127.0.0.1:{port}/healthz"
for _ in range(60):
    try:
        urllib.request.urlopen(url, timeout=1).read()
        break
    except Exception:
        time.sleep(0.1)
else:
    raise SystemExit("phase31-confidence: packaged propane server failed to become ready")
PY

ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy doctor \
  --app-root "$app_root" \
  --releases-dir "$releases_dir" \
  --base-url "http://127.0.0.1:${doctor_port}" \
  --json >"$doctor_json"

cleanup_server
trap 'rm -rf "$app_parent" "$work_root"' EXIT

set +e
ARLEN_APP_ROOT="$current_release/app" \
ARLEN_FRAMEWORK_ROOT="$current_release/framework" \
"$current_release/framework/bin/jobs-worker" --once >"$jobs_worker_log" 2>&1
jobs_worker_rc=$?
set -e
printf '%s\n' "$jobs_worker_rc" >"$output_dir/jobs_worker_once.exit"

exe_work_root="$work_root/exe-doctor"
exe_app_root="$exe_work_root/app"
exe_releases_dir="$exe_work_root/releases"
exe_release_dir="$exe_releases_dir/exe-rel-1"
mkdir -p \
  "$exe_app_root/config" \
  "$exe_release_dir/app/config" \
  "$exe_release_dir/app/.boomhauer/build" \
  "$exe_release_dir/framework/build" \
  "$exe_release_dir/framework/bin" \
  "$exe_release_dir/framework/tools/deploy" \
  "$exe_release_dir/metadata"

cat >"$exe_app_root/config/app.plist" <<'EOF'
{
  host = "127.0.0.1";
  port = 3000;
  database = {
    connectionString = "postgresql:///phase31_exe_manifest";
    adapter = "postgresql";
  };
}
EOF
cp "$exe_app_root/config/app.plist" "$exe_release_dir/app/config/app.plist"
printf '#!/usr/bin/env bash\nexit 0\n' >"$exe_release_dir/app/.boomhauer/build/boomhauer-app.exe"
printf '#!/usr/bin/env bash\nexit 0\n' >"$exe_release_dir/framework/build/boomhauer.exe"
printf '#!/usr/bin/env bash\nexit 0\n' >"$exe_release_dir/framework/build/arlen.exe"
printf '#!/usr/bin/env bash\nexit 0\n' >"$exe_release_dir/framework/bin/propane"
printf '#!/usr/bin/env bash\nexit 0\n' >"$exe_release_dir/framework/bin/jobs-worker"
printf '#!/usr/bin/env bash\necho ok\n' >"$exe_release_dir/framework/tools/deploy/validate_operability.sh"
chmod 755 \
  "$exe_release_dir/app/.boomhauer/build/boomhauer-app.exe" \
  "$exe_release_dir/framework/build/boomhauer.exe" \
  "$exe_release_dir/framework/build/arlen.exe" \
  "$exe_release_dir/framework/bin/propane" \
  "$exe_release_dir/framework/bin/jobs-worker" \
  "$exe_release_dir/framework/tools/deploy/validate_operability.sh"
cat >"$exe_release_dir/metadata/release.env" <<EOF
ARLEN_APP_ROOT=$exe_release_dir/app
ARLEN_FRAMEWORK_ROOT=$exe_release_dir/framework
EOF

python3 - "$exe_release_dir" <<'PY'
import json
import os
import sys

release_dir = sys.argv[1]
manifest = {
    "version": "phase29-deploy-manifest-v1",
    "release_id": "exe-rel-1",
    "paths": {
        "app_root": os.path.join(release_dir, "app"),
        "framework_root": os.path.join(release_dir, "framework"),
        "runtime_binary": os.path.join(release_dir, "app", ".boomhauer", "build", "boomhauer-app"),
        "boomhauer": os.path.join(release_dir, "framework", "build", "boomhauer"),
        "propane": os.path.join(release_dir, "framework", "bin", "propane"),
        "jobs_worker": os.path.join(release_dir, "framework", "bin", "jobs-worker"),
        "arlen": os.path.join(release_dir, "framework", "build", "arlen"),
        "operability_probe_helper": os.path.join(release_dir, "framework", "tools", "deploy", "validate_operability.sh"),
        "release_env": os.path.join(release_dir, "metadata", "release.env"),
    },
    "health_contract": {
        "health_path": "/healthz",
        "readiness_path": "/readyz",
        "expected_ok_body": "ok",
    },
    "migration_inventory": {
        "count": 0,
        "files": [],
    },
}
with open(os.path.join(release_dir, "metadata", "manifest.json"), "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

ln -sfn "$exe_release_dir" "$exe_releases_dir/current"
ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy doctor \
  --app-root "$exe_app_root" \
  --releases-dir "$exe_releases_dir" \
  --json >"$exe_doctor_json"

python3 "$repo_root/tools/ci/generate_phase31_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --release-smoke "$smoke_json" \
  --packaged-manifest "$output_dir/packaged_release_manifest.json" \
  --packaged-release-env "$output_dir/packaged_release_env.txt" \
  --deploy-doctor "$doctor_json" \
  --packaged-server-log "$packaged_server_log" \
  --jobs-worker-log "$jobs_worker_log" \
  --jobs-worker-exit "$output_dir/jobs_worker_once.exit" \
  --exe-manifest-doctor "$exe_doctor_json"

echo "ci: phase31 confidence gate complete"
