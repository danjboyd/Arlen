# Phase 5E Production Hardening + Confidence Pack

Phase 5E focuses on reliability hardening and release evidence for Arlen's SQL-first data layer.

## 1. Scope

Phase 5E implementation includes:

- soak-focused query compile/execute regression coverage
- explicit fault-injection regression coverage
- deterministic release confidence artifact generation
- CI/release checklist wiring to Phase 5E quality gates

## 2. Soak + Fault Coverage

Primary 5E coverage lives in:

- `tests/unit/PgTests.m`
  - `testBuilderCacheEvictionChurnAndSoakExecutionRemainDeterministic`
  - `testConnectionInterruptionReturnsDeterministicErrorAndPoolRecovers`
  - `testTransactionAbortPathRollsBackAndConnectionRemainsUsable`

Soak iterations can be tuned with:

```bash
ARLEN_PHASE5E_SOAK_ITERS=240 make test-unit
```

If `ARLEN_PG_TEST_DSN` is unset, PostgreSQL-backed tests remain skipped by design.

## 3. Confidence Artifact Pack

Generate confidence artifacts:

```bash
python3 tools/ci/generate_phase5e_confidence_artifacts.py \
  --repo-root . \
  --output-dir build/release_confidence/phase5e
```

Generated artifacts:

- `adapter_capability_matrix_snapshot.json`
- `sql_builder_conformance_summary.json`
- `phase5e_release_confidence.md`
- `manifest.json`

## 4. CI Quality Gates

Phase 5E quality gate entrypoints:

- `tools/ci/run_phase5e_quality.sh`
- `tools/ci/run_phase5e_sanitizers.sh`

Convenience targets:

```bash
make ci-quality
make ci-sanitizers
make phase5e-confidence
```

## 5. Release Contract

Release candidates must include:

- passing Phase 5E quality and sanitizer gates
- deployment smoke validation
- generated confidence artifact pack attached to release evidence
