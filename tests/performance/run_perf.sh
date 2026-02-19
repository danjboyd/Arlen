#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

mkdir -p build/perf
baseline_file="${ARLEN_PERF_BASELINE:-tests/performance/baselines/default.json}"
policy_file="${ARLEN_PERF_POLICY:-tests/performance/policy.json}"
report_file="build/perf/latest.json"
summary_csv="build/perf/latest.csv"
runs_csv="build/perf/latest_runs.csv"

if [[ "${ARLEN_PERF_FAST:-0}" == "1" ]]; then
  repeats="${ARLEN_PERF_REPEATS:-1}"
  requests="${ARLEN_PERF_REQUESTS:-40}"
  skip_gate="${ARLEN_PERF_SKIP_GATE:-1}"
else
  repeats="${ARLEN_PERF_REPEATS:-3}"
  requests="${ARLEN_PERF_REQUESTS:-120}"
  skip_gate="${ARLEN_PERF_SKIP_GATE:-0}"
fi

make boomhauer >/dev/null

port="${ARLEN_PERF_PORT:-3301}"
./build/boomhauer --port "$port" >/tmp/arlen_perf_server.log 2>&1 &
server_pid=$!

cleanup() {
  if kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

if ! curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
  echo "perf: server failed to start"
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
  local scenario="$1"
  local path="$2"
  local requests_local="$3"
  local run_id="$4"
  local lat_raw
  local lat_sorted
  lat_raw="$(mktemp)"
  lat_sorted="$(mktemp)"

  local start_ns end_ns
  start_ns="$(date +%s%N)"
  for _ in $(seq 1 "$requests_local"); do
    curl -o /dev/null -sS -w "%{time_total}\n" "http://127.0.0.1:${port}${path}" >>"$lat_raw"
  done
  end_ns="$(date +%s%N)"

  awk '{printf "%.6f\n", ($1*1000.0)}' "$lat_raw" | sort -n >"$lat_sorted"
  local p50 p95 p99 max reqps duration_s
  p50="$(percentile "$lat_sorted" 50)"
  p95="$(percentile "$lat_sorted" 95)"
  p99="$(percentile "$lat_sorted" 99)"
  max="$(awk 'END {if (NR==0) print "0"; else printf "%.3f", $1}' "$lat_sorted")"
  duration_s="$(awk -v s="$start_ns" -v e="$end_ns" 'BEGIN {printf "%.6f", ((e-s)/1000000000.0)}')"
  reqps="$(awk -v n="$requests_local" -v d="$duration_s" 'BEGIN {if (d<=0) print "0"; else printf "%.2f", (n/d)}')"

  echo "${scenario},${run_id},${requests_local},${p50},${p95},${p99},${max},${reqps},${duration_s}" >>"$runs_csv"
  rm -f "$lat_raw" "$lat_sorted"
}

echo "scenario,run,requests,p50_ms,p95_ms,p99_ms,max_ms,req_per_sec,duration_s" >"$runs_csv"

for run_id in $(seq 1 "$repeats"); do
  run_benchmark_once "healthz" "/healthz" "$requests" "$run_id"
  run_benchmark_once "api_status" "/api/status" "$requests" "$run_id"
  run_benchmark_once "root" "/" "$requests" "$run_id"
done

mem_after_kb="$(ps -o rss= -p "$server_pid" | awk '{print $1+0}')"

python3 tests/performance/check_perf.py \
  --runs-csv "$runs_csv" \
  --report "$report_file" \
  --summary-csv "$summary_csv" \
  --baseline "$baseline_file" \
  --policy "$policy_file" \
  --host "127.0.0.1" \
  --port "$port" \
  --mem-before-kb "$mem_before_kb" \
  --mem-after-kb "$mem_after_kb" \
  $([[ "$skip_gate" == "1" ]] && echo "--skip-gate")

echo "perf: complete report=$report_file summary=$summary_csv runs=$runs_csv"
