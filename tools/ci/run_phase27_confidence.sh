#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE27_OUTPUT_DIR:-$repo_root/build/release_confidence/phase27}"
search_log="$output_dir/phase27_search_tests.log"
characterization_json="$output_dir/search_characterization.json"
meili_dir="$output_dir/live_meilisearch"
open_dir="$output_dir/live_opensearch"
meili_log="$output_dir/phase27_meilisearch_live.log"
open_log="$output_dir/phase27_opensearch_live.log"

mkdir -p "$output_dir" "$meili_dir" "$open_dir"

write_probe_manifest() {
  local target_dir="$1"
  local status="$2"
  local reason="$3"
  local artifact="$4"
  cat >"$target_dir/manifest.json" <<EOF
{
  "status": "$status",
  "reason": "$reason",
  "artifacts": [
    "$artifact"
  ]
}
EOF
}

probe_meilisearch() {
  local url="${ARLEN_PHASE27_MEILI_URL:-}"
  local artifact="$meili_dir/health.json"
  if [[ -z "$url" ]]; then
    printf '%s\n' "phase27-confidence: live Meilisearch probe skipped because ARLEN_PHASE27_MEILI_URL is not set" | tee "$meili_log"
    write_probe_manifest "$meili_dir" "skipped" "missing_ARLEN_PHASE27_MEILI_URL" "../$(basename "$meili_log")"
    return 0
  fi

  local -a headers=()
  if [[ -n "${ARLEN_PHASE27_MEILI_API_KEY:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${ARLEN_PHASE27_MEILI_API_KEY}")
  fi

  set +e
  {
    echo "phase27-confidence: probing Meilisearch $url/health"
    curl -fsS "${headers[@]}" "${url%/}/health" >"$artifact"
  } 2>&1 | tee "$meili_log"
  local status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    write_probe_manifest "$meili_dir" "pass" "" "health.json"
  else
    write_probe_manifest "$meili_dir" "fail" "meilisearch_probe_failed" "../$(basename "$meili_log")"
    return $status
  fi
}

probe_opensearch() {
  local url="${ARLEN_PHASE27_OPENSEARCH_URL:-}"
  local artifact="$open_dir/cluster_health.json"
  if [[ -z "$url" ]]; then
    printf '%s\n' "phase27-confidence: live OpenSearch probe skipped because ARLEN_PHASE27_OPENSEARCH_URL is not set" | tee "$open_log"
    write_probe_manifest "$open_dir" "skipped" "missing_ARLEN_PHASE27_OPENSEARCH_URL" "../$(basename "$open_log")"
    return 0
  fi

  local -a headers=()
  if [[ -n "${ARLEN_PHASE27_OPENSEARCH_AUTH_HEADER:-}" ]]; then
    headers+=(-H "${ARLEN_PHASE27_OPENSEARCH_AUTH_HEADER}")
  elif [[ -n "${ARLEN_PHASE27_OPENSEARCH_API_KEY:-}" ]]; then
    headers+=(-H "Authorization: ApiKey ${ARLEN_PHASE27_OPENSEARCH_API_KEY}")
  fi

  set +e
  {
    echo "phase27-confidence: probing OpenSearch ${url%/}/_cluster/health"
    curl -fsS "${headers[@]}" "${url%/}/_cluster/health" >"$artifact"
  } 2>&1 | tee "$open_log"
  local status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    write_probe_manifest "$open_dir" "pass" "" "cluster_health.json"
  else
    write_probe_manifest "$open_dir" "fail" "opensearch_probe_failed" "../$(basename "$open_log")"
    return $status
  fi
}

set +u
source "$repo_root/tools/source_gnustep_env.sh"
set -u

make -C "$repo_root" phase27-search-tests 2>&1 | tee "$search_log"
make -C "$repo_root" phase27-search-characterize >/dev/null

mkdir -p "$repo_root/.gnustep-home/GNUstep/Defaults/.lck"
export HOME="$repo_root/.gnustep-home"
export GNUSTEP_USER_DIR="$repo_root/.gnustep-home/GNUstep"
export GNUSTEP_USER_ROOT="$repo_root/.gnustep-home/GNUstep"
export GNUSTEP_USER_DEFAULTS_DIR="$repo_root/.gnustep-home/GNUstep/Defaults"
"$repo_root/build/phase27-search-characterize" >"$characterization_json"

probe_meilisearch
probe_opensearch

python3 "$repo_root/tools/ci/generate_phase27_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --search-log "$search_log" \
  --characterization "$characterization_json" \
  --meilisearch-manifest "$meili_dir/manifest.json" \
  --opensearch-manifest "$open_dir/manifest.json"

echo "ci: phase27 confidence gate complete"
