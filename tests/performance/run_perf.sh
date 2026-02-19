#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

mkdir -p build/perf
baseline_file="tests/performance/baselines/default.json"
report_file="build/perf/latest.json"
csv_file="build/perf/latest.csv"

make boomhauer >/dev/null

port="${ARLEN_PERF_PORT:-3301}"
./build/boomhauer --port "$port" >/tmp/mojo_perf_server.log 2>&1 &
server_pid=$!

cleanup() {
  if kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for _ in $(seq 1 40); do
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

run_benchmark() {
  local name="$1"
  local path="$2"
  local requests="$3"
  local lat_raw
  local lat_sorted
  lat_raw="$(mktemp)"
  lat_sorted="$(mktemp)"

  local start_ns end_ns
  start_ns="$(date +%s%N)"
  for _ in $(seq 1 "$requests"); do
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
  reqps="$(awk -v n="$requests" -v d="$duration_s" 'BEGIN {if (d<=0) print "0"; else printf "%.2f", (n/d)}')"

  echo "${name},${requests},${p50},${p95},${p99},${max},${reqps}" >>"$csv_file"

  eval "${name}_p50=${p50}"
  eval "${name}_p95=${p95}"
  eval "${name}_p99=${p99}"
  eval "${name}_max=${max}"
  eval "${name}_reqps=${reqps}"

  rm -f "$lat_raw" "$lat_sorted"
}

echo "scenario,requests,p50_ms,p95_ms,p99_ms,max_ms,req_per_sec" >"$csv_file"

run_benchmark "healthz" "/healthz" 120
run_benchmark "api_status" "/api/status" 120
run_benchmark "root" "/" 120

mem_after_kb="$(ps -o rss= -p "$server_pid" | awk '{print $1+0}')"

cat >"$report_file" <<EOF
{
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "host": "127.0.0.1",
  "port": ${port},
  "healthz_p50_ms": ${healthz_p50},
  "healthz_p95_ms": ${healthz_p95},
  "healthz_p99_ms": ${healthz_p99},
  "healthz_max_ms": ${healthz_max},
  "healthz_req_per_sec": ${healthz_reqps},
  "api_status_p50_ms": ${api_status_p50},
  "api_status_p95_ms": ${api_status_p95},
  "api_status_p99_ms": ${api_status_p99},
  "api_status_max_ms": ${api_status_max},
  "api_status_req_per_sec": ${api_status_reqps},
  "root_p50_ms": ${root_p50},
  "root_p95_ms": ${root_p95},
  "root_p99_ms": ${root_p99},
  "root_max_ms": ${root_max},
  "root_req_per_sec": ${root_reqps},
  "memory_before_kb": ${mem_before_kb},
  "memory_after_kb": ${mem_after_kb}
}
EOF

if [[ ! -f "$baseline_file" ]]; then
  cp "$report_file" "$baseline_file"
  echo "perf: baseline created at $baseline_file"
  exit 0
fi

extract_json_number() {
  local file="$1"
  local key="$2"
  grep -E "\"${key}\"" "$file" | head -n1 | sed -E 's/.*: *([0-9.]+).*/\1/'
}

baseline_root_p95="$(extract_json_number "$baseline_file" "root_p95_ms")"
current_root_p95="$(extract_json_number "$report_file" "root_p95_ms")"
threshold="$(awk -v b="$baseline_root_p95" 'BEGIN {printf "%.6f", (b*1.15)}')"

if awk -v c="$current_root_p95" -v t="$threshold" 'BEGIN {exit !(c > t)}'; then
  echo "perf: regression detected root_p95_ms current=${current_root_p95} threshold=${threshold}"
  exit 1
fi

echo "perf: ok report=$report_file csv=$csv_file root_p95_ms=${current_root_p95}"
