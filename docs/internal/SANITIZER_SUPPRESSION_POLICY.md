# Sanitizer Suppression Policy

Arlen keeps sanitizer confidence high by treating suppressions as temporary and auditable.

## Registry

All temporary suppressions are recorded in:

- `tests/fixtures/sanitizers/phase9h_suppressions.json`

The registry is validated by:

```bash
python3 ./tools/ci/check_sanitizer_suppressions.py
```

This check is part of the explicit the sanitizer entrypoint
`bash ./tools/ci/run_phase5e_sanitizers.sh` and must pass for release candidates.

## Required Fields

Each active suppression entry must include:

- `id`: stable unique identifier
- `status`: `active` or `resolved`
- `sanitizer`: sanitizer lane (for example `thread`, `address`, `undefined`)
- `owner`: owning team/person for cleanup
- `reason`: short root-cause summary
- `introducedOn`: ISO date (`YYYY-MM-DD`)
- `expiresOn`: ISO date (`YYYY-MM-DD`)

Validation rules:

- `expiresOn` must be greater than or equal to `introducedOn`
- expired active suppressions fail CI
- malformed date/field values fail CI

## Expiration Contract

- suppressions are temporary and must carry an explicit expiration date
- any suppression approaching expiry (14-day window) is treated as cleanup priority
- resolved suppressions should remain in the registry with `status: "resolved"` for audit history

## Artifact Contract

Sanitizer confidence artifacts are generated at:

- `build/release_confidence/phase9h/`

TSAN experimental artifacts are retained at:

- `build/sanitizers/tsan/`

Confidence generation command:

```bash
bash ./tools/ci/run_phase5e_sanitizers.sh
```

Outputs include lane status, suppression summary, and status deltas for release triage.

## TSAN evidence and matching contract

Active thread-sanitizer entries must also declare `patterns` matching the
suppression file exactly and an `evidence` document present in the repository.
The validator rejects unregistered patterns and missing evidence. Retired
suppressions stay in the registry as `resolved`; that status retires the
exception, not necessarily the underlying runtime finding.

Library-wide patterns can hide application-owned races through library
callbacks. New or renewed exceptions require a minimal reproducer, captured
raw stacks/toolchain identity, a scoped matching rationale, and a positive
control that still detects an application race with the exceptions enabled.
Do not classify a runtime finding as a false positive without evidence.

See [the September 21 investigation](TSAN_RELIABILITY_2026-09-21.md) for current
findings, retired broad rules, and the conditions for TSAN gate promotion.
