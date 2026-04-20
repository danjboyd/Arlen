#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE36_OUTPUT_DIR:-$repo_root/build/release_confidence/phase36}"

mkdir -p "$output_dir"

source "$repo_root/tools/source_gnustep_env.sh"

make -C "$repo_root" arlen >"$output_dir/arlen-build.log" 2>&1

work_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-phase36-confidence-XXXXXX")"
app_root="$work_root/app"
mkdir -p "$app_root/config/environments"
trap 'rm -rf "$work_root"' EXIT

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

(
  cd "$app_root"

  "$repo_root/build/arlen" deploy list --app-root "$app_root" --json \
    >"$output_dir/list_no_config.json"

  "$repo_root/build/arlen" deploy target sample \
    --target production \
    --ssh-host deploy@prod.example.test \
    --write \
    --output config/deploy.plist.example \
    --json >"$output_dir/target_sample_write.json"

  cp config/deploy.plist.example config/deploy.plist
  "$repo_root/build/arlen" deploy list --app-root "$app_root" --json \
    >"$output_dir/list_sample_config.json"

  cat >config/deploy.plist <<EOF
{
  deployment = {
    schema = "phase32-deploy-targets-v1";
    targets = {
      alpha = {
        host = "alpha.example.test";
        releasePath = "$work_root/alpha-release";
        profile = "linux-x86_64-gnustep-clang";
        runtimeStrategy = "system";
        runtimeAction = "none";
        environment = "production";
      };
      beta = {
        host = "beta.example.test";
        releasePath = "$work_root/beta-release";
        profile = "linux-x86_64-gnustep-clang";
        runtimeStrategy = "system";
        runtimeAction = "none";
        environment = "production";
      };
    };
  };
}
EOF
  "$repo_root/build/arlen" deploy list --app-root "$app_root" --json \
    >"$output_dir/list_two_targets.json"

  "$repo_root/build/arlen" deploy dryrun alpha \
    --app-root "$app_root" \
    --allow-missing-certification \
    --json >"$output_dir/dryrun_alpha.json"

  "$repo_root/build/arlen" deploy plan alpha \
    --app-root "$app_root" \
    --allow-missing-certification \
    --json >"$output_dir/plan_alias_alpha.json"

  releases_dir="$work_root/local-releases"
  "$repo_root/build/arlen" deploy push \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --release-id phase36-a \
    --allow-missing-certification \
    --json >"$output_dir/push_phase36_a.json"
  "$repo_root/build/arlen" deploy push \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --release-id phase36-b \
    --allow-missing-certification \
    --json >"$output_dir/push_phase36_b.json"
  "$repo_root/build/arlen" deploy releases \
    --app-root "$app_root" \
    --releases-dir "$releases_dir" \
    --json >"$output_dir/releases_after_pushes.json"

  mock_ssh="$work_root/fail-if-called-ssh.sh"
  mock_ssh_log="$work_root/fail-if-called-ssh.log"
  cat >"$mock_ssh" <<'EOF'
#!/usr/bin/env bash
printf 'ssh-called %s\n' "$*" >> "$ARLEN_PHASE36_MOCK_SSH_LOG"
exit 88
EOF
  chmod +x "$mock_ssh"
  cat >config/deploy.plist <<EOF
{
  deployment = {
    schema = "phase32-deploy-targets-v1";
    targets = {
      production = {
        host = "prod.example.test";
        releasePath = "$work_root/remote-prod";
        profile = "linux-x86_64-gnustep-clang";
        runtimeStrategy = "system";
        runtimeAction = "none";
        environment = "production";
        transport = {
          sshHost = "mock-prod";
          sshCommand = "$mock_ssh";
          sshOptions = ("-oBatchMode=yes");
        };
      };
    };
  };
}
EOF
  set +e
  ARLEN_PHASE36_MOCK_SSH_LOG="$mock_ssh_log" "$repo_root/build/arlen" deploy push production \
    --app-root "$app_root" \
    --release-id uninitialized-guard \
    --allow-missing-certification \
    --json >"$output_dir/uninitialized_push.json"
  uninitialized_rc=$?
  set -e
  printf '%s\n' "$uninitialized_rc" >"$output_dir/uninitialized_push.exit"

  ARLEN_PHASE36_MOCK_SSH_LOG="$mock_ssh_log" "$repo_root/build/arlen" completion candidates deploy-release-ids \
    --app-root "$app_root" \
    --target production >"$output_dir/completion_release_ids_remote_target.txt"
  if [[ -f "$mock_ssh_log" ]]; then
    cp "$mock_ssh_log" "$output_dir/mock_ssh.log"
  else
    : >"$output_dir/mock_ssh.log"
  fi

  "$repo_root/build/arlen" completion bash >"$output_dir/completion.bash"
  "$repo_root/build/arlen" completion powershell >"$output_dir/completion.ps1"
  "$repo_root/build/arlen" completion candidates top-level-commands >"$output_dir/candidates_top_level.txt"
  "$repo_root/build/arlen" completion candidates deploy-subcommands >"$output_dir/candidates_deploy_subcommands.txt"
  "$repo_root/build/arlen" completion candidates deploy-target-subcommands >"$output_dir/candidates_deploy_target_subcommands.txt"
  "$repo_root/build/arlen" completion candidates deploy-options >"$output_dir/candidates_deploy_options.txt"
  "$repo_root/build/arlen" completion candidates deploy-targets >"$output_dir/candidates_deploy_targets.txt"

  printf '{ deployment = { targets = ; }; }\n' >config/deploy.plist
  "$repo_root/build/arlen" completion candidates deploy-targets >"$output_dir/candidates_malformed_targets.txt"
)

make -C "$repo_root" test-integration-filter TEST=DeploymentIntegrationTests/testArlenNewDeploySampleAndCompletionFoundation \
  >"$output_dir/integration_sample_completion.log" 2>&1
make -C "$repo_root" test-integration-filter TEST=DeploymentIntegrationTests/testArlenDeployReleaseAndStatusOperateAgainstRemoteNamedTargetOverSSH \
  >"$output_dir/integration_remote_reuse.log" 2>&1

python3 "$repo_root/tools/ci/generate_phase36_confidence_artifacts.py" \
  --output-dir "$output_dir"

echo "ci: phase36 confidence gate complete"
