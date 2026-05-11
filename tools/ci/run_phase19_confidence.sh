#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
final_output_dir="${ARLEN_PHASE19_OUTPUT_DIR:-$repo_root/build/release_confidence/phase19}"
work_dir="${ARLEN_PHASE19_WORK_DIR:-$repo_root/.phase19-confidence-work}"
output_dir="$work_dir"
app_root="${ARLEN_PHASE19_APP_ROOT:-$repo_root/examples/multi_module_demo_initial}"
gnustep_sh="/usr/GNUstep/System/Library/Makefiles/GNUstep.sh"
overall_status=0

shell_quote() {
  local value="${1:-}"
  printf "'%s'" "${value//\'/\'\"\'\"\'}"
}

quoted_repo_root="$(shell_quote "$repo_root")"
quoted_app_root="$(shell_quote "$app_root")"
quoted_gnustep_sh="$(shell_quote "$gnustep_sh")"
quoted_app_state_root="$(shell_quote "$app_root/.boomhauer")"

mkdir -p "${HOME}/GNUstep/Defaults/.lck"
rm -rf "$output_dir" "$final_output_dir"
mkdir -p "$output_dir"

if [[ ! -f "$gnustep_sh" ]]; then
  echo "phase19-confidence: GNUstep.sh not found at $gnustep_sh" >&2
  exit 1
fi

if [[ ! -f "$app_root/config/app.plist" ]] || [[ ! -f "$app_root/app_lite.m" && ! -f "$app_root/src/main.m" ]]; then
  echo "phase19-confidence: app root must contain config/app.plist and app_lite.m or src/main.m: $app_root" >&2
  exit 1
fi

run_shell_measurement() {
  local name="$1"
  local command="$2"
  local log_path="$output_dir/$name.log"
  local time_path="$output_dir/$name.time"
  local exit_path="$output_dir/$name.exitcode"
  local command_path="$output_dir/$name.command"
  local status=0

  printf '%s\n' "$command" >"$command_path"
  if /usr/bin/time -f '%e' -o "$time_path" \
      bash -lc "set -eo pipefail; set +u; source $quoted_gnustep_sh; set -u; cd $quoted_repo_root; $command" \
      >"$log_path" 2>&1; then
    status=0
  else
    status=$?
  fi

  printf '%s\n' "$status" >"$exit_path"
  if [[ $status -ne 0 ]]; then
    overall_status=1
  fi
}

write_skipped_scope() {
  local label="$1"
  local reason="$2"
  cat >"$output_dir/$label.scope" <<EOF
exit_code=skipped
reason=$reason
EOF
}

run_scope_probe() {
  local label="$1"
  local touch_path="$2"
  local dryrun_path="$output_dir/$label.scope.make_n.log"
  local probe_log_path="$output_dir/$label.scope.probe.log"
  local scope_path="$output_dir/$label.scope"
  local quoted_touch_path
  local status=0

  quoted_touch_path="$(shell_quote "$touch_path")"
  if bash -lc "set -eo pipefail; set +u; source $quoted_gnustep_sh; set -u; cd $quoted_repo_root; path=$quoted_touch_path; original_mtime=\$(stat -c %Y \"\$path\"); restore() { touch -d \"@\${original_mtime}\" \"\$path\"; }; trap restore EXIT; touch \"\$path\"; make -n build-tests > $(shell_quote "$dryrun_path")" \
      >"$probe_log_path" 2>&1; then
    status=0
  else
    status=$?
  fi

  {
    printf 'exit_code=%s\n' "$status"
    if [[ $status -eq 0 ]]; then
      printf 'framework_compile=%s\n' "$(grep -Fq -- "-c src/Arlen/MVC/View/ALNView.m -o $repo_root/build/obj/src/Arlen/MVC/View/ALNView.o" "$dryrun_path" && echo yes || echo no)"
      printf 'framework_archive=%s\n' "$(grep -Fq -- "ar rcs $repo_root/build/lib/libArlenFramework.a" "$dryrun_path" && echo yes || echo no)"
      printf 'root_transpile=%s\n' "$(grep -Fq -- "$repo_root/build/eocc --template-root $repo_root/templates --output-dir $repo_root/build/gen/templates --manifest $repo_root/build/gen/templates/manifest.json" "$dryrun_path" && echo yes || echo no)"
      printf 'template_index_compile=%s\n' "$(grep -Fq -- "-c build/gen/templates/index.html.eoc.m -o $repo_root/build/obj/build/gen/templates/index.html.eoc.o" "$dryrun_path" && echo yes || echo no)"
      printf 'template_layout_compile=%s\n' "$(grep -Fq -- "-c build/gen/templates/layouts/main.html.eoc.m -o $repo_root/build/obj/build/gen/templates/layouts/main.html.eoc.o" "$dryrun_path" && echo yes || echo no)"
      printf 'unit_test_compile=%s\n' "$(grep -Fq -- "-c tests/unit/BuildPolicyTests.m -o $repo_root/build/obj/tests/unit/BuildPolicyTests.o" "$dryrun_path" && echo yes || echo no)"
      printf 'unit_bundle_link=%s\n' "$(grep -Fq -- "-o $repo_root/build/tests/ArlenUnitTests.xctest/ArlenUnitTests" "$dryrun_path" && echo yes || echo no)"
      printf 'integration_bundle_link=%s\n' "$(grep -Fq -- "-o $repo_root/build/tests/ArlenIntegrationTests.xctest/ArlenIntegrationTests" "$dryrun_path" && echo yes || echo no)"
      printf 'boomhauer_link=%s\n' "$(grep -Fq -- "-o $repo_root/build/boomhauer" "$dryrun_path" && echo yes || echo no)"
    fi
  } >"$scope_path"

  if [[ $status -ne 0 ]]; then
    overall_status=1
  fi
}

run_shell_measurement "build_tests_cold" "make clean && make build-tests"
run_shell_measurement "build_tests_warm" "make build-tests"
run_shell_measurement "test_unit" "make test-unit"
run_shell_measurement "boomhauer_prepare_cold" "rm -rf $quoted_app_state_root && ARLEN_APP_ROOT=$quoted_app_root ./bin/boomhauer --prepare-only"
run_shell_measurement "boomhauer_prepare_warm" "ARLEN_APP_ROOT=$quoted_app_root ./bin/boomhauer --prepare-only"
run_shell_measurement "boomhauer_print_routes" "ARLEN_APP_ROOT=$quoted_app_root ./bin/boomhauer --print-routes"

if [[ -f "$output_dir/build_tests_warm.exitcode" ]] && [[ "$(cat "$output_dir/build_tests_warm.exitcode")" == "0" ]]; then
  run_scope_probe "framework" "src/Arlen/MVC/View/ALNView.m"
  run_scope_probe "template" "templates/index.html.eoc"
  run_scope_probe "unittest" "tests/unit/BuildPolicyTests.m"
else
  write_skipped_scope "framework" "build_tests_warm_failed"
  write_skipped_scope "template" "build_tests_warm_failed"
  write_skipped_scope "unittest" "build_tests_warm_failed"
fi

if ! python3 ./tools/ci/generate_phase19_confidence_artifacts.py \
    --repo-root "$repo_root" \
    --output-dir "$output_dir" \
    --app-root "$app_root"; then
  overall_status=1
fi

mkdir -p "$(dirname "$final_output_dir")"
cp -R "$output_dir" "$final_output_dir"
rm -rf "$output_dir"
echo "phase19-confidence: copied artifacts to $final_output_dir"

exit "$overall_status"
