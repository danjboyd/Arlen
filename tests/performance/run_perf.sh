#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

mkdir -p build/perf
report_file="build/perf/latest.json"
summary_csv="build/perf/latest.csv"
runs_csv="build/perf/latest_runs.csv"
trend_json="build/perf/latest_trend.json"
trend_md="build/perf/latest_trend.md"

profile="${ARLEN_PERF_PROFILE:-default}"
profile_file="${ARLEN_PERF_PROFILE_FILE:-tests/performance/profiles/${profile}.sh}"
if [[ ! -f "$profile_file" ]]; then
  echo "perf: profile file not found: $profile_file"
  exit 2
fi

PROFILE_NAME="$profile"
MAKE_TARGETS=(boomhauer)
SERVER_BINARY="./build/boomhauer"
SERVER_ARGS=(--port "{port}")
SERVER_ENV=()
READINESS_PATH="/healthz"
CONCURRENCY=1
SCENARIOS=(
  "healthz:/healthz"
  "api_status:/api/status"
  "root:/"
)

# shellcheck disable=SC1090
source "$profile_file"
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  echo "perf: profile contains no scenarios: $profile_file"
  exit 2
fi

concurrency="${ARLEN_PERF_CONCURRENCY:-$CONCURRENCY}"
if ! [[ "$concurrency" =~ ^[0-9]+$ ]] || (( concurrency < 1 )); then
  echo "perf: invalid concurrency value: ${concurrency}"
  exit 2
fi

if [[ "$PROFILE_NAME" == "default" && "$concurrency" == "1" ]]; then
  echo "perf: note: default profile is CI regression-oriented. For external comparisons use ARLEN_PERF_PROFILE=comparison_http."
fi

baseline_file="${ARLEN_PERF_BASELINE:-tests/performance/baselines/${PROFILE_NAME}.json}"
policy_file="${ARLEN_PERF_POLICY:-tests/performance/policies/${PROFILE_NAME}.json}"
if [[ ! -f "$policy_file" && -f "tests/performance/policy.json" ]]; then
  policy_file="tests/performance/policy.json"
fi
history_dir="${ARLEN_PERF_HISTORY_DIR:-build/perf/history/${PROFILE_NAME}}"

if [[ "${ARLEN_PERF_FAST:-0}" == "1" ]]; then
  repeats="${ARLEN_PERF_REPEATS:-1}"
  requests="${ARLEN_PERF_REQUESTS:-40}"
  skip_gate="${ARLEN_PERF_SKIP_GATE:-1}"
else
  repeats="${ARLEN_PERF_REPEATS:-3}"
  requests="${ARLEN_PERF_REQUESTS:-120}"
  skip_gate="${ARLEN_PERF_SKIP_GATE:-0}"
fi

make "${MAKE_TARGETS[@]}" >/dev/null

port="${ARLEN_PERF_PORT:-3301}"
resolved_args=()
for arg in "${SERVER_ARGS[@]}"; do
  resolved_args+=("${arg//\{port\}/$port}")
done

launch_cmd=(env)
for env_pair in "${SERVER_ENV[@]}"; do
  launch_cmd+=("$env_pair")
done
launch_cmd+=("$SERVER_BINARY")
launch_cmd+=("${resolved_args[@]}")

server_log="build/perf/server_${PROFILE_NAME}.log"
"${launch_cmd[@]}" >"$server_log" 2>&1 &
server_pid=$!

cleanup() {
  if kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${port}${READINESS_PATH}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

if ! curl -fsS "http://127.0.0.1:${port}${READINESS_PATH}" >/dev/null 2>&1; then
  echo "perf: server failed to start"
  echo "perf: startup log follows"
  cat "$server_log"
  exit 1
fi

mem_before_kb="$(ps -o rss= -p "$server_pid" | awk '{print $1+0}')"

percentile() {
  local file="$1"
  local p="$2"
  awk -v p="$p" '
    {a[++n]=$1}
    END {
      if (n==0) {print "0"; exit}
      idx=int((p/100)*n)
      if (idx < 1) idx=1
      if (idx > n) idx=n
      printf "%.3f", a[idx]
    }
  ' "$file"
}

run_benchmark_once() {
  local profile_local="$1"
  local scenario="$2"
  local path="$3"
  local requests_local="$4"
  local run_id="$5"
  local lat_raw
  local lat_sorted
  lat_raw="$(mktemp)"
  lat_sorted="$(mktemp)"

  local start_ns end_ns
  start_ns="$(date +%s%N)"
  local url="http://127.0.0.1:${port}${path}"
  if (( concurrency <= 1 )); then
    for _ in $(seq 1 "$requests_local"); do
      curl -o /dev/null -sS -w "%{time_total}\n" "$url" >>"$lat_raw"
    done
  else
    seq 1 "$requests_local" \
      | xargs -P "$concurrency" -I{} curl -o /dev/null -sS -w "%{time_total}\n" "$url" \
          >>"$lat_raw"
  fi
  end_ns="$(date +%s%N)"

  awk '{printf "%.6f\n", ($1*1000.0)}' "$lat_raw" | sort -n >"$lat_sorted"
  local p50 p95 p99 max reqps duration_s
  p50="$(percentile "$lat_sorted" 50)"
  p95="$(percentile "$lat_sorted" 95)"
  p99="$(percentile "$lat_sorted" 99)"
  max="$(awk 'END {if (NR==0) print "0"; else printf "%.3f", $1}' "$lat_sorted")"
  duration_s="$(awk -v s="$start_ns" -v e="$end_ns" 'BEGIN {printf "%.6f", ((e-s)/1000000000.0)}')"
  reqps="$(awk -v n="$requests_local" -v d="$duration_s" 'BEGIN {if (d<=0) print "0"; else printf "%.2f", (n/d)}')"

  echo "${profile_local},${scenario},${run_id},${requests_local},${concurrency},${p50},${p95},${p99},${max},${reqps},${duration_s}" >>"$runs_csv"
  rm -f "$lat_raw" "$lat_sorted"
}

echo "profile,scenario,run,requests,concurrency,p50_ms,p95_ms,p99_ms,max_ms,req_per_sec,duration_s" >"$runs_csv"

for run_id in $(seq 1 "$repeats"); do
  for scenario_entry in "${SCENARIOS[@]}"; do
    scenario_name="${scenario_entry%%:*}"
    scenario_path="${scenario_entry#*:}"
    run_benchmark_once "$PROFILE_NAME" "$scenario_name" "$scenario_path" "$requests" "$run_id"
  done
done

mem_after_kb="$(ps -o rss= -p "$server_pid" | awk '{print $1+0}')"

set +e
python3 tests/performance/check_perf.py \
  --runs-csv "$runs_csv" \
  --report "$report_file" \
  --summary-csv "$summary_csv" \
  --baseline "$baseline_file" \
  --policy "$policy_file" \
  --profile "$PROFILE_NAME" \
  --host "127.0.0.1" \
  --port "$port" \
  --mem-before-kb "$mem_before_kb" \
  --mem-after-kb "$mem_after_kb" \
  $([[ "$skip_gate" == "1" ]] && echo "--skip-gate")
gate_status=$?
set -e

timestamp_utc="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$history_dir"
archived_report="${history_dir}/${timestamp_utc}.json"
cp "$report_file" "$archived_report"

python3 tests/performance/trend_report.py \
  --history-dir "$history_dir" \
  --output-json "$trend_json" \
  --output-md "$trend_md" \
  --profile "$PROFILE_NAME"

echo "perf: complete profile=$PROFILE_NAME report=$report_file summary=$summary_csv runs=$runs_csv"
echo "perf: archived report=$archived_report trend_json=$trend_json trend_md=$trend_md"
exit "$gate_status"
