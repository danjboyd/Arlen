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

meili_task_uid_from_file() {
  local response_path="$1"
  python3 - "$response_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)
uid = payload.get("taskUid", payload.get("uid", ""))
if uid in (None, ""):
    raise SystemExit("missing Meilisearch task uid")
print(uid)
PY
}

wait_for_meilisearch_task() {
  local base_url="$1"
  local task_uid="$2"
  local label="$3"
  shift 3
  local task_json="$meili_dir/${label}_task.json"

  for _ in $(seq 1 60); do
    curl -fsS "$@" "${base_url}/tasks/${task_uid}" >"$task_json"
    local status
    status="$(python3 - "$task_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)
print(str(payload.get("status", "")))
PY
)"
    case "$status" in
      succeeded)
        return 0
        ;;
      failed)
        python3 - "$task_json" "$label" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)
error = payload.get("error") or {}
message = error.get("message") or payload.get("status") or "unknown Meilisearch task failure"
raise SystemExit(f"{sys.argv[2]} task failed: {message}")
PY
        ;;
      enqueued|processing)
        sleep 1
        ;;
      *)
        sleep 1
        ;;
    esac
  done

  echo "Meilisearch ${label} task ${task_uid} did not complete within timeout" >&2
  return 1
}

probe_meilisearch() {
  local url="${ARLEN_PHASE27_MEILI_URL:-}"
  local artifact="$meili_dir/validation.json"
  if [[ -z "$url" ]]; then
    printf '%s\n' "phase27-confidence: live Meilisearch validation requires ARLEN_PHASE27_MEILI_URL" | tee "$meili_log"
    write_probe_manifest "$meili_dir" "fail" "missing_ARLEN_PHASE27_MEILI_URL" "../$(basename "$meili_log")"
    return 0
  fi

  local base_url="${url%/}"
  local index_name="phase27_confidence_meili_$(date +%s)_$$"
  local create_json="$meili_dir/create_response.json"
  local settings_json="$meili_dir/settings_response.json"
  local sync_json="$meili_dir/sync_response.json"
  local search_json="$meili_dir/search_response.json"
  local -a auth_headers=()
  if [[ -n "${ARLEN_PHASE27_MEILI_API_KEY:-}" ]]; then
    auth_headers+=(-H "Authorization: Bearer ${ARLEN_PHASE27_MEILI_API_KEY}")
  fi

  local status=0
  set +e
  {
    echo "phase27-confidence: validating Meilisearch sync/query against ${base_url}"
    curl -fsS "${auth_headers[@]}" -X DELETE "${base_url}/indexes/${index_name}" >/dev/null 2>&1 || true
    curl -fsS "${auth_headers[@]}" -H "Content-Type: application/json" -X POST "${base_url}/indexes" \
      --data-binary "{\"uid\":\"${index_name}\",\"primaryKey\":\"recordID\"}" >"$create_json"
    wait_for_meilisearch_task "${base_url}" "$(meili_task_uid_from_file "$create_json")" "create" "${auth_headers[@]}"
    curl -fsS "${auth_headers[@]}" -H "Content-Type: application/json" \
      -X PATCH "${base_url}/indexes/${index_name}/settings" \
      --data-binary '{"filterableAttributes":["category","inventory_count"],"sortableAttributes":["inventory_count"],"searchableAttributes":["title","summary"],"displayedAttributes":["recordID","title","summary","category","inventory_count"]}' \
      >"$settings_json"
    wait_for_meilisearch_task "${base_url}" "$(meili_task_uid_from_file "$settings_json")" "settings" "${auth_headers[@]}"
    curl -fsS "${auth_headers[@]}" -H "Content-Type: application/json" \
      -X POST "${base_url}/indexes/${index_name}/documents?primaryKey=recordID" \
      --data-binary @- >"$sync_json" <<'EOF'
[
  {
    "recordID": "sku-100",
    "title": "Starter Kit",
    "summary": "Entry starter kit for new operators.",
    "category": "starter",
    "inventory_count": 12
  },
  {
    "recordID": "sku-102",
    "title": "Priority Kit",
    "summary": "Priority workflow kit for fast-moving queues.",
    "category": "priority",
    "inventory_count": 4
  },
  {
    "recordID": "sku-103",
    "title": "Priority Rack",
    "summary": "Rack accessory for priority stations.",
    "category": "priority",
    "inventory_count": 7
  }
]
EOF
    wait_for_meilisearch_task "${base_url}" "$(meili_task_uid_from_file "$sync_json")" "sync" "${auth_headers[@]}"
    curl -fsS "${auth_headers[@]}" -H "Content-Type: application/json" \
      -X POST "${base_url}/indexes/${index_name}/search" \
      --data-binary @- >"$search_json" <<'EOF'
{
  "q": "priority",
  "limit": 10,
  "filter": [
    "category = \"priority\"",
    "inventory_count >= 5"
  ],
  "sort": [
    "inventory_count:desc"
  ],
  "facets": [
    "category"
  ],
  "showRankingScore": true
}
EOF
    python3 - "$artifact" "$search_json" "$create_json" "$settings_json" "$sync_json" <<'PY'
import json
import sys

artifact_path, search_path, create_path, settings_path, sync_path = sys.argv[1:]
with open(search_path, "r", encoding="utf-8") as handle:
    search = json.load(handle)
hits = search.get("hits") or []
if not hits or hits[0].get("recordID") != "sku-103":
    raise SystemExit("expected Meilisearch top hit sku-103 after sync/query validation")
facet_distribution = search.get("facetDistribution") or {}
if int((facet_distribution.get("category") or {}).get("priority", 0)) < 1:
    raise SystemExit("expected Meilisearch category facet to include priority")
summary = {
    "status": "pass",
    "topRecordID": hits[0].get("recordID", ""),
    "totalHits": search.get("estimatedTotalHits", len(hits)),
    "facetDistribution": facet_distribution,
    "createResponse": json.load(open(create_path, "r", encoding="utf-8")),
    "settingsResponse": json.load(open(settings_path, "r", encoding="utf-8")),
    "syncResponse": json.load(open(sync_path, "r", encoding="utf-8")),
}
with open(artifact_path, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  } 2>&1 | tee "$meili_log"
  status=$?
  set -e
  curl -fsS "${auth_headers[@]}" -X DELETE "${base_url}/indexes/${index_name}" >/dev/null 2>&1 || true

  if [[ $status -eq 0 ]]; then
    write_probe_manifest "$meili_dir" "pass" "" "validation.json"
  else
    write_probe_manifest "$meili_dir" "fail" "meilisearch_live_validation_failed" "../$(basename "$meili_log")"
  fi
  return 0
}

probe_opensearch() {
  local url="${ARLEN_PHASE27_OPENSEARCH_URL:-}"
  local artifact="$open_dir/validation.json"
  if [[ -z "$url" ]]; then
    printf '%s\n' "phase27-confidence: live OpenSearch validation requires ARLEN_PHASE27_OPENSEARCH_URL" | tee "$open_log"
    write_probe_manifest "$open_dir" "fail" "missing_ARLEN_PHASE27_OPENSEARCH_URL" "../$(basename "$open_log")"
    return 0
  fi

  local base_url="${url%/}"
  local index_name="phase27_confidence_opensearch_$(date +%s)_$$"
  local create_json="$open_dir/create_response.json"
  local bulk_json="$open_dir/bulk_response.json"
  local search_json="$open_dir/search_response.json"
  local -a auth_headers=()
  if [[ -n "${ARLEN_PHASE27_OPENSEARCH_AUTH_HEADER:-}" ]]; then
    auth_headers+=(-H "${ARLEN_PHASE27_OPENSEARCH_AUTH_HEADER}")
  elif [[ -n "${ARLEN_PHASE27_OPENSEARCH_API_KEY:-}" ]]; then
    auth_headers+=(-H "Authorization: ApiKey ${ARLEN_PHASE27_OPENSEARCH_API_KEY}")
  fi

  local status=0
  set +e
  {
    echo "phase27-confidence: validating OpenSearch sync/query against ${base_url}"
    curl -fsS "${auth_headers[@]}" -X DELETE "${base_url}/${index_name}" >/dev/null 2>&1 || true
    curl -fsS "${auth_headers[@]}" -H "Content-Type: application/json" \
      -X PUT "${base_url}/${index_name}" \
      --data-binary @- >"$create_json" <<'EOF'
{
  "mappings": {
    "properties": {
      "recordID": { "type": "keyword" },
      "title": { "type": "text", "fields": { "keyword": { "type": "keyword" } } },
      "summary": { "type": "text" },
      "category": { "type": "keyword" },
      "inventory_count": { "type": "integer" }
      }
    }
}
EOF
    cat >"$open_dir/bulk_request.ndjson" <<EOF
{"index":{"_index":"${index_name}","_id":"sku-100"}}
{"recordID":"sku-100","title":"Starter Kit","summary":"Entry starter kit for new operators.","category":"starter","inventory_count":12}
{"index":{"_index":"${index_name}","_id":"sku-102"}}
{"recordID":"sku-102","title":"Priority Kit","summary":"Priority workflow kit for fast-moving queues.","category":"priority","inventory_count":4}
{"index":{"_index":"${index_name}","_id":"sku-103"}}
{"recordID":"sku-103","title":"Priority Rack","summary":"Rack accessory for priority stations.","category":"priority","inventory_count":7}
EOF
    curl -fsS "${auth_headers[@]}" -H "Content-Type: application/x-ndjson" \
      -X POST "${base_url}/${index_name}/_bulk?refresh=true" \
      --data-binary @"$open_dir/bulk_request.ndjson" >"$bulk_json"
    curl -fsS "${auth_headers[@]}" -H "Content-Type: application/json" \
      -X POST "${base_url}/${index_name}/_search" \
      --data-binary @- >"$search_json" <<'EOF'
{
  "size": 10,
  "track_total_hits": true,
  "query": {
    "bool": {
      "must": [
        {
          "multi_match": {
            "query": "priority",
            "fields": ["title^3", "summary"]
          }
        }
      ],
      "filter": [
        { "term": { "category": "priority" } },
        { "range": { "inventory_count": { "gte": 5 } } }
      ]
    }
  },
  "sort": [
    { "inventory_count": { "order": "desc" } }
  ],
  "aggs": {
    "category": {
      "terms": {
        "field": "category",
        "size": 10
      }
    }
  }
}
EOF
    python3 - "$artifact" "$search_json" "$create_json" "$bulk_json" <<'PY'
import json
import sys

artifact_path, search_path, create_path, bulk_path = sys.argv[1:]
with open(search_path, "r", encoding="utf-8") as handle:
    search = json.load(handle)
hits = ((search.get("hits") or {}).get("hits") or [])
if not hits:
    raise SystemExit("expected OpenSearch hits after sync/query validation")
top = hits[0]
source = top.get("_source") or {}
if source.get("recordID") != "sku-103":
    raise SystemExit("expected OpenSearch top hit sku-103 after sync/query validation")
aggregations = search.get("aggregations") or {}
buckets = ((aggregations.get("category") or {}).get("buckets") or [])
priority_bucket = next((bucket for bucket in buckets if bucket.get("key") == "priority"), None)
if not priority_bucket or int(priority_bucket.get("doc_count", 0)) < 1:
    raise SystemExit("expected OpenSearch category aggregation to include priority")
bulk = json.load(open(bulk_path, "r", encoding="utf-8"))
if bulk.get("errors"):
    raise SystemExit("OpenSearch bulk validation returned partial failures")
summary = {
    "status": "pass",
    "topRecordID": source.get("recordID", ""),
    "totalHits": ((search.get("hits") or {}).get("total") or {}).get("value", 0),
    "aggregations": aggregations,
    "createResponse": json.load(open(create_path, "r", encoding="utf-8")),
    "bulkResponse": bulk,
}
with open(artifact_path, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  } 2>&1 | tee "$open_log"
  status=$?
  set -e
  curl -fsS "${auth_headers[@]}" -X DELETE "${base_url}/${index_name}" >/dev/null 2>&1 || true

  if [[ $status -eq 0 ]]; then
    write_probe_manifest "$open_dir" "pass" "" "validation.json"
  else
    write_probe_manifest "$open_dir" "fail" "opensearch_live_validation_failed" "../$(basename "$open_log")"
  fi
  return 0
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

if [[ -z "${ARLEN_PG_TEST_DSN:-}" ]]; then
  printf '%s\n' "phase27-confidence: PostgreSQL characterization is required and ARLEN_PG_TEST_DSN is not set" | tee -a "$search_log"
fi

probe_meilisearch
probe_opensearch

python3 "$repo_root/tools/ci/generate_phase27_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --search-log "$search_log" \
  --characterization "$characterization_json" \
  --meilisearch-manifest "$meili_dir/manifest.json" \
  --opensearch-manifest "$open_dir/manifest.json"

echo "ci: phase27 confidence gate complete"
