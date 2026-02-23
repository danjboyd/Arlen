# Arlen Phase 5 Roadmap

Status: Phase 5A-5E initial implementation complete  
Last updated: 2026-02-23

Related docs:
- `docs/PHASE4_ROADMAP.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/STATUS.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/ARLEN_DATA.md`
- `docs/SQL_BUILDER_CONFORMANCE_MATRIX.md`

## 1. Objective

Increase Arlen data-layer confidence and adoption readiness after Phase 4 by delivering:

- wider multi-database maturity
- stronger compile-time typed guidance for SQL-first workflows
- explicit reliability contracts backed by high-signal regression coverage

This roadmap preserves core Arlen principles:

- raw SQL remains first-class
- SQL abstractions remain optional/additive
- no default full ORM requirement
- dialect-specific behavior remains isolated in explicit dialect modules

## 2. Scope Summary

1. Formalize reliability contracts for advertised data-layer behavior.
2. Add multi-database runtime routing primitives (read/write roles and optional tenant/shard hooks).
3. Extend migrations and schema codegen for multi-database workflows.
4. Expand compile-time typed data contracts without introducing ORM coupling.
5. Add release-grade hardening and confidence artifacts for new users.

## 3. Milestones

## 3.1 Phase 5A: Reliability Contracts + External Regression Intake

Status: Initial implementation complete (2026-02-23)

Deliverables:

- Publish an explicit data-layer reliability contract map:
  - every documented behavior links to concrete unit/integration/regression tests
  - unsupported behavior paths must map to deterministic diagnostics
- Add an external regression intake workflow:
  - reference scenarios from competitor framework test suites as inspiration
  - translate scenario intent into Arlen-native contracts and tests
  - record provenance in docs/tests for maintenance traceability
- Introduce capability metadata for adapters/dialects (for example: lock modes, upsert style, window support) so unsupported semantics fail clearly.
- Add CI quality gate script for Phase 5A contract coverage and metadata consistency.

Acceptance (required):

- Every new Phase 5 feature claim is tied to an executable contract in CI.
- External inspiration scenarios are tracked with source + Arlen contract mapping.
- Silent fallback behavior for unsupported dialect features is eliminated.

Implementation notes:

- Added Phase 5A contract docs and machine-readable fixtures:
  - `docs/PHASE5A_RELIABILITY_CONTRACTS.md`
  - `tests/fixtures/phase5a/data_layer_reliability_contracts.json`
  - `tests/fixtures/phase5a/external_regression_intake.json`
  - `tests/fixtures/phase5a/adapter_capabilities.json`
- Added capability metadata contract surface:
  - optional `capabilityMetadata` on `ALNDatabaseAdapter`
  - concrete metadata on `ALNPg` and `ALNGDL2Adapter`
- Added Phase 5A unit coverage + fixture/reference enforcement:
  - `tests/unit/Phase5ATests.m`
  - `tools/ci/check_phase5a_contracts.py`
- Added dedicated Phase 5A CI quality gate script:
  - `tools/ci/run_phase5a_quality.sh`

## 3.2 Phase 5B: Multi-Database Runtime Routing

Status: Initial implementation complete (2026-02-23)

Deliverables:

- Add runtime DB routing contract for operation-class aware target selection (for example read/write role routing).
- Add optional read-after-write stickiness policy with bounded scope.
- Add optional tenant/shard hook surface while keeping default flow simple.
- Extend diagnostics events with routing metadata so query destination decisions are observable.

Acceptance (required):

- Unit tests verify deterministic routing decisions from stable inputs.
- Integration tests validate read/write routing behavior against multiple live DB endpoints.
- Regression tests cover pool exhaustion, route fallback, and rollback boundaries.

Implementation notes:

- Added runtime router surface:
  - `src/Arlen/Data/ALNDatabaseRouter.h`
  - `src/Arlen/Data/ALNDatabaseRouter.m`
- Added ArlenData export for router:
  - `src/ArlenData/ArlenData.h`
- Added dedicated Phase 5B unit + integration coverage:
  - `tests/unit/Phase5BTests.m`
  - `tests/integration/PostgresIntegrationTests.m` (`testDatabaseRouterReadWriteRoutingAcrossLiveAdapters`)
- Added Phase 5B docs and contract mappings:
  - `docs/PHASE5B_RUNTIME_ROUTING.md`
  - updated `tests/fixtures/phase5a/data_layer_reliability_contracts.json`
  - updated `tests/fixtures/phase5a/external_regression_intake.json`

## 3.3 Phase 5C: Multi-Database Tooling + Migration Targeting

Status: Initial implementation complete (2026-02-23)

Deliverables:

- Extend CLI commands with explicit database target selection:
  - `arlen migrate --database <name>`
  - `arlen schema-codegen --database <name>`
- Add deterministic migration state handling for multiple named database targets.
- Extend generated schema/codegen manifests with database target metadata.
- Add integration fixtures/examples that exercise multi-database migration + generation workflows.

Acceptance (required):

- End-to-end tests prove migration ordering/idempotency for at least two named database targets.
- Codegen outputs remain deterministic and diff-friendly per target.
- Failure/retry behavior is covered by regression tests.

Implementation notes:

- Extended CLI target selection for migration and schema codegen:
  - `tools/arlen.m` (`migrate --database <target>`, `schema-codegen --database <target>`)
- Added deterministic per-target migration state isolation:
  - `src/Arlen/Data/ALNMigrationRunner.h`
  - `src/Arlen/Data/ALNMigrationRunner.m`
- Added schema-codegen manifest target metadata support:
  - `src/Arlen/Data/ALNSchemaCodegen.h`
  - `src/Arlen/Data/ALNSchemaCodegen.m`
- Added 5C integration + unit coverage:
  - `tests/integration/PostgresIntegrationTests.m`
    - `testArlenMigrateCommandSupportsNamedDatabaseTargetsAndFailureRetry`
    - `testArlenSchemaCodegenSupportsNamedDatabaseTargets`
  - `tests/unit/SchemaCodegenTests.m`
- Added Phase 5C docs and contract mappings:
  - `docs/PHASE5C_MULTI_DATABASE_TOOLING.md`
  - updated `tests/fixtures/phase5a/data_layer_reliability_contracts.json`
  - updated `tests/fixtures/phase5a/external_regression_intake.json`

## 3.4 Phase 5D: Compile-Time Typed Data Contracts (SQL-First)

Status: Initial implementation complete (2026-02-23)

Deliverables:

- Extend schema-codegen outputs beyond symbol helpers to optional typed row/insert/update artifacts.
- Add generated decode helpers for mapping query result dictionaries to typed data contracts.
- Add optional typed SQL artifact workflow (SQL files compiled into typed parameter/result helpers).
- Preserve backward compatibility for existing builder + raw SQL APIs during migration.

Acceptance (required):

- Compile-time checks fail clearly for broken typed contract usage.
- Runtime decode mismatch failures are deterministic and test-covered.
- Existing SQL-builder contract tests continue passing unchanged.

Implementation notes:

- Extended schema codegen for optional typed contract output:
  - `tools/arlen.m` (`schema-codegen --typed-contracts`)
  - `src/Arlen/Data/ALNSchemaCodegen.h`
  - `src/Arlen/Data/ALNSchemaCodegen.m`
- Generated typed row/insert/update artifacts now include:
  - typed contract classes per table (`Row`, `Insert`, `Update`)
  - `insertContract`/`updateContract` helpers
  - deterministic `decodeTypedRow`/`decodeTypedRows` runtime decode helpers
  - explicit typed decode error domain + codes in generated output
- Added optional typed SQL artifact workflow:
  - `tools/arlen.m` command `typed-sql-codegen`
  - SQL input files with `-- arlen:name|params|result` metadata compile into typed parameter/result helpers
- Added 5D unit + integration coverage:
  - `tests/unit/SchemaCodegenTests.m`
  - `tests/integration/PostgresIntegrationTests.m`
    - `testArlenSchemaCodegenTypedContractsCompileAndDecodeDeterministically`
    - `testArlenTypedSQLCodegenGeneratesTypedParameterAndResultHelpers`
- Added Phase 5D docs and contract mappings:
  - `docs/PHASE5D_TYPED_CONTRACTS.md`
  - updated `tests/fixtures/phase5a/data_layer_reliability_contracts.json`
  - updated `tests/fixtures/phase5a/external_regression_intake.json`

## 3.5 Phase 5E: Production Hardening + Confidence Release Pack

Status: Initial implementation complete (2026-02-23)

Deliverables:

- Add long-run soak suites for query compile/execute paths across representative workloads.
- Add fault-injection regression coverage (connectivity interruption, transaction abort paths, cache eviction churn).
- Publish release confidence artifacts:
  - adapter/dialect capability matrix snapshots
  - conformance summary for each release train
- Wire release checklist requirements to Phase 5 quality gates.

Acceptance (required):

- Phase 5 release candidates require passing soak + fault-injection gates.
- Confidence artifacts are produced and reviewed as part of each release cycle.

Implementation notes:

- Added long-run/fault-injection PostgreSQL regression coverage:
  - `tests/unit/PgTests.m`
    - `testBuilderCacheEvictionChurnAndSoakExecutionRemainDeterministic`
    - `testConnectionInterruptionReturnsDeterministicErrorAndPoolRecovers`
    - `testTransactionAbortPathRollsBackAndConnectionRemainsUsable`
- Added deterministic release confidence artifact generator and integration validation:
  - `tools/ci/generate_phase5e_confidence_artifacts.py`
  - `tests/integration/DeploymentIntegrationTests.m`
    - `testPhase5EConfidenceArtifactGeneratorProducesExpectedPack`
- Added Phase 5E quality/sanitizer gate entrypoints:
  - `tools/ci/run_phase5e_quality.sh`
  - `tools/ci/run_phase5e_sanitizers.sh`
  - `GNUmakefile` targets: `ci-quality`, `ci-sanitizers`, `phase5e-confidence`
- Added Phase 5E docs and contract mappings:
  - `docs/PHASE5E_HARDENING_CONFIDENCE.md`
  - updated `tests/fixtures/phase5a/data_layer_reliability_contracts.json`
  - updated `tests/fixtures/phase5a/external_regression_intake.json`

## 4. Testing and Regression Strategy

Phase 5 relies on contract-first testing with layered coverage:

- Unit contract tests:
  - clause/render/validation behavior
  - routing decision determinism
  - typed decode and contract-shape validation
- Integration execution tests:
  - real database execution per adapter/dialect target
  - multi-database route behavior
  - migration/codegen target correctness
- Long-run/property/fault tests:
  - placeholder/order determinism under randomized composition
  - route/failover stress loops
  - retry/rollback and pool-behavior fault cases

External regression intake policy:

1. Identify behavior from competitor framework tests that represent high-value production bug classes.
2. Translate behavior into an Arlen contract statement (not a direct copy of external test code).
3. Implement Arlen-native unit/integration/regression coverage.
4. Record provenance and rationale in docs/test comments.
5. Keep Arlen contracts as the source of truth; external suites are reference input only.

## 5. Scope Guardrails

- No full ORM default requirement in Phase 5.
- No reduction of raw SQL first-class behavior.
- Keep PostgreSQL-specific features in explicit dialect modules.
- Preserve Objective-C/GNUstep-first API style and deterministic diagnostics.
