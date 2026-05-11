# Phase 9I Fault Injection

Phase 9I adds deterministic fault-injection coverage for runtime seams most likely to regress under load or malformed client behavior.

## Command Path

Primary command path:

```bash
make ci-fault-injection
```

This executes:

- `tools/ci/run_phase9i_fault_injection.sh`
- `tools/ci/runtime_fault_injection.py`

## Covered Runtime Seams

Scenario matrix source:

- `tests/fixtures/fault_injection/phase9i_fault_scenarios.json`

Current seam coverage:

- `http_parser_dispatcher`
  - partial request disconnects
  - delayed/chunked writes
  - socket churn burst
- `websocket_handshake_lifecycle`
  - malformed upgrade handshake (accept/reject outcome captured as deterministic diagnostics)
  - partial frame disconnect + recovery
- `runtime_stop_start_boundary`
  - stop/start overlap under active load

## Seed Replay

Replay exact scenario sequencing:

```bash
ARLEN_PHASE9I_SEED=9011 make ci-fault-injection
```

Control execution scope:

```bash
ARLEN_PHASE9I_ITERS=2 \
ARLEN_PHASE9I_MODES=concurrent,serialized \
ARLEN_PHASE9I_SCENARIOS=http_partial_request_disconnect,websocket_malformed_upgrade \
make ci-fault-injection
```

## Artifacts

Output directory:

- `build/release_confidence/phase9i/`

Generated files:

- `fault_injection_results.json`
- `phase9i_fault_injection_summary.md`
- `manifest.json`

The JSON results include normalized failure signatures for deterministic triage.
