# Phase 5A Reliability Contracts

This document defines the executable artifacts used to implement Phase 5A:

- reliability contract mapping for advertised data-layer behavior
- external regression intake from competitor framework bug classes
- adapter/dialect capability metadata baselines

## 1. Machine-Readable Artifacts

- `tests/fixtures/phase5a/data_layer_reliability_contracts.json`
- `tests/fixtures/phase5a/external_regression_intake.json`
- `tests/fixtures/phase5a/adapter_capabilities.json`

## 2. Contract Rules

Each contract entry must include:

- stable `id`
- clear behavior claim
- source docs list
- one or more executable verification references (`file` + `test`)

If unsupported behavior is part of the contract, the entry must include expected diagnostic symbol references.

## 3. External Regression Intake Rules

External framework tests are reference input only.

Required workflow:

1. Capture scenario metadata from a competitor framework bug class.
2. Map the scenario to an Arlen contract ID.
3. Add Arlen-native test references for coverage.
4. Preserve provenance metadata in fixture fields (`source_framework`, `source_area`, `source_reference`).

Policy:

- Do not copy external tests verbatim.
- Arlen contracts remain the source of truth.
- Intake entries may be `covered` or `planned`, but all entries must map to known contract IDs.

## 4. Adapter Capability Metadata

Phase 5A introduces adapter capability metadata contracts through:

- optional protocol method `capabilityMetadata` on `ALNDatabaseAdapter`
- concrete metadata on:
  - `ALNPg`
  - `ALNGDL2Adapter`

Current baseline covers capabilities needed by the SQL builder conformance families:

- CTE / recursive CTE
- set operations
- window clauses
- lateral joins
- lock clauses (`FOR UPDATE`, `SKIP LOCKED`)
- PostgreSQL conflict handling
- builder diagnostics/caching support

## 5. CI Enforcement

Phase 5A quality gates:

- `tools/ci/check_phase5a_contracts.py`
- `tools/ci/run_phase5a_quality.sh`

The gate validates:

- fixture schema and uniqueness constraints
- cross-reference integrity between contracts/intake/capabilities
- test reference resolution against real Objective-C test method names
