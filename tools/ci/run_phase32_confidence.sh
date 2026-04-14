#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE32_OUTPUT_DIR:-$repo_root/build/release_confidence/phase32}"

mkdir -p "$output_dir"

source "$repo_root/tools/source_gnustep_env.sh"

make -C "$repo_root" arlen >/dev/null
make -C "$repo_root" build-tests >/dev/null

app_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-phase32-app-XXXXXX")"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-phase32-work-XXXXXX")"
trap 'rm -rf "$app_root" "$work_root"' EXIT

mkdir -p "$app_root/config/environments"
cat >"$app_root/config/app.plist" <<'EOF'
{
  host = "127.0.0.1";
  port = 3000;
}
EOF
cat >"$app_root/config/environments/production.plist" <<'EOF'
{
  logFormat = "json";
}
EOF
cat >"$app_root/app_lite.m" <<'EOF'
#import <Foundation/Foundation.h>
int main(int argc, const char *argv[]) { (void)argc; (void)argv; return 0; }
EOF

releases_dir="$work_root/releases"
push_supported_json="$output_dir/push_supported.json"
release_supported_json="$output_dir/release_supported.json"
push_experimental_json="$output_dir/push_experimental.json"
release_experimental_json="$output_dir/release_experimental.json"
doctor_experimental_fail_json="$output_dir/doctor_experimental_fail.json"
doctor_experimental_pass_json="$output_dir/doctor_experimental_pass.json"
status_experimental_json="$output_dir/status_experimental.json"
rollback_json="$output_dir/rollback.json"
unsupported_release_json="$output_dir/unsupported_release.json"
release_env_txt="$output_dir/release_env.txt"

(
  cd "$app_root"
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy push \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --release-id phase32-a \
    --allow-missing-certification \
    --json >"$push_supported_json"

  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy release \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --release-id phase32-a \
    --allow-missing-certification \
    --skip-migrate \
    --json >"$release_supported_json"

  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy push \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --release-id phase32-b \
    --target-profile windows-x86_64-gnustep-clang64 \
    --runtime-strategy managed \
    --allow-remote-rebuild \
    --allow-missing-certification \
    --json >"$push_experimental_json"

  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy release \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --release-id phase32-b \
    --allow-remote-rebuild \
    --remote-build-check-command /bin/true \
    --allow-missing-certification \
    --skip-migrate \
    --json >"$release_experimental_json"

  set +e
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy doctor \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --json >"$doctor_experimental_fail_json"
  doctor_fail_rc=$?
  set -e
  printf '%s\n' "$doctor_fail_rc" >"$output_dir/doctor_experimental_fail.exit"

  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy doctor \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --remote-build-check-command /bin/true \
    --json >"$doctor_experimental_pass_json"

  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy status \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --json >"$status_experimental_json"

  cp "$releases_dir/phase32-b/metadata/release.env" "$release_env_txt"

  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy rollback \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --runtime-action none \
    --json >"$rollback_json"

  set +e
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy release \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --release-id phase32-c \
    --target-profile macos-arm64-apple-foundation \
    --allow-remote-rebuild \
    --allow-missing-certification \
    --skip-migrate \
    --json >"$unsupported_release_json"
  unsupported_rc=$?
  set -e
  printf '%s\n' "$unsupported_rc" >"$output_dir/unsupported_release.exit"
)

python3 "$repo_root/tools/ci/generate_phase32_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --push-supported "$push_supported_json" \
  --release-supported "$release_supported_json" \
  --push-experimental "$push_experimental_json" \
  --release-experimental "$release_experimental_json" \
  --doctor-experimental-fail "$doctor_experimental_fail_json" \
  --doctor-experimental-pass "$doctor_experimental_pass_json" \
  --status-experimental "$status_experimental_json" \
  --rollback "$rollback_json" \
  --unsupported-release "$unsupported_release_json" \
  --release-env "$release_env_txt"

echo "ci: phase32 confidence gate complete"
