#!/usr/bin/env bash
set -euo pipefail

# Exercise the real emitter without starting workers or inspecting other processes.
emitter="$(python3 - "$1" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index('emit_config_values() {')
end = text.index('\n}\n', start) + 3
print(text[start:end])
PY
)"
eval "$emitter"

python3() {
  local argument
  for argument in "$@"; do
    case "$argument" in
      *arlen-private-config-fixture*)
        echo 'merged configuration was passed in a process argument' >&2
        return 99
        ;;
    esac
  done
  command python3 "$@"
}

probe_config='{"session":{"secret":"arlen-private-config-fixture"},"host":"127.0.0.2","propaneAccessories":{"workerCount":3,"jobWorkerCommand":"job --token arlen-private-config-fixture"}}'
output="$(emit_config_values "$probe_config")"
[[ "$output" == *'config_host=127.0.0.2'* ]]
[[ "$output" == *'config_workers=3'* ]]
[[ "$output" == *'config_job_worker_command=job --token arlen-private-config-fixture'* ]]
echo 'private config input and unredacted worker settings preserved'
