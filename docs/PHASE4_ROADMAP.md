# Arlen Phase 4 Roadmap

Status: Active (Phase 4A complete; Phase 4B-4E planned)  
Last updated: 2026-02-20

Related docs:
- `docs/PHASE3_ROADMAP.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/ARLEN_DATA.md`

## 1. Objective

Advance Arlen's SQL/data-layer developer experience from "capable v2 builder" to best-in-class completeness and ergonomics, while preserving core Arlen principles:

- raw SQL remains first-class
- SQL builder remains optional/additive
- dialect-specific features remain isolated in explicit dialect modules

## 2. Scope Summary

1. Introduce a typed/internal query-expression representation to reduce stringly APIs and improve safety.
2. Expand SQL surface coverage for advanced production query patterns.
3. Add typed schema ergonomics and code generation for compile-time guidance.
4. Improve runtime performance and diagnostics for query compilation/execution paths.
5. Establish long-horizon conformance, fuzzing, and migration-hardening gates.

## 3. Milestones

## 3.1 Phase 4A: Query IR + Safety Foundation

Status: Complete (2026-02-20)

Deliverables:
- Add internal query/expression IR for builder compilation paths (identifiers, values, expressions, functions, tuples, fragments, subqueries).
- Formalize a safe raw-expression/fragment API with explicit value binding and identifier handling contracts.
- Add compile-time validation passes for malformed expression trees and unsupported clause shapes.
- Keep existing builder API source compatibility while routing through the new IR.

Acceptance (verified):
- Existing `ALNSQLBuilder`/`ALNPostgresSQLBuilder` contract tests pass unchanged through IR-backed compilation.
- Invalid/malformed expression shapes fail deterministically with actionable diagnostics.
- Security regressions are covered for identifier/literal/fragment misuse paths.

Implementation notes:
- Added trusted-expression IR dictionaries (`trusted-template-v1`) for expression-capable builder clauses with source-compatible API overloads.
- Added explicit identifier token binding (`{{token}}`) with safe identifier quoting contracts.
- Added strict parameter/placeholder contract validation (`$1..$N` coverage and bounds checks) and deterministic malformed IR diagnostics.
- Added dedicated Phase 4A unit coverage in `tests/unit/Phase4ATests.m`.
- Added PostgreSQL execution coverage for identifier-binding expression templates in `tests/unit/PgTests.m`.

## 3.2 Phase 4B: SQL Surface Completion

Deliverables:
- Add set-operation composition (`UNION`, `UNION ALL`, `INTERSECT`, `EXCEPT`).
- Add window-function composition and named window clauses.
- Add richer predicate/locking clauses (`EXISTS`/`ANY`/`ALL`, `FOR UPDATE`, `SKIP LOCKED`).
- Add join-surface completion (`USING`, `CROSS`, `FULL`) where supported by dialect modules.
- Expand CTE ergonomics and recursive composition contracts.

Acceptance:
- Deterministic SQL/parameter snapshot coverage for each new clause family.
- PostgreSQL execution coverage validates representative query behavior and row results.
- Unsupported dialect semantics fail with explicit, test-covered diagnostics.

## 3.3 Phase 4C: Typed Ergonomics + Schema Codegen

Deliverables:
- Add schema introspection/codegen pipeline for typed table/column symbols.
- Provide typed builder helper APIs generated from schema artifacts.
- Publish generator workflow docs and migration examples from string-based builder calls.

Acceptance:
- Generated artifacts are deterministic and diff-friendly.
- Generated APIs compile and execute in representative sample apps.
- Legacy string-based builder APIs remain supported during migration window.

## 3.4 Phase 4D: Performance + Diagnostics

Deliverables:
- Add compilation caching and prepared-statement reuse policy for builder-driven paths.
- Add structured query diagnostics/listener pipeline (compile, execute, result, error stages).
- Add redaction-safe query metadata logging for production incident workflows.
- Publish benchmark profiles specific to builder compilation/execution overhead.

Acceptance:
- Performance profiles show no regression relative to pre-Phase-4 baselines without documented rationale.
- Query diagnostics include stable metadata fields suitable for alerting/debugging.
- Cache behavior is deterministic and covered by unit/integration tests.

## 3.5 Phase 4E: Conformance + Migration Hardening

Deliverables:
- Introduce SQL builder conformance matrix and long-run regression suite.
- Add property/fuzz testing for placeholder shifting, parameter ordering, tuple predicates, and expression nesting.
- Add compatibility and migration guide from v2 string-heavy patterns to IR/typed patterns.
- Finalize deprecation policy for any transitional APIs introduced in 4A-4D.

Acceptance:
- CI enforces compile snapshots, execution semantics, and fuzz/property coverage.
- Migration guide is validated by at least one representative real-world upgrade path.
- Regression suite catches placeholder/encoding and shape-sensitive query bugs before release.

## 4. Testing Strategy (Adopted from Best-in-Class Patterns)

Phase 4 test architecture should follow these contracts:

- Separate compile/render correctness tests from execute/runtime behavior tests.
- Maintain dialect-matrix SQL expectation coverage from single query specs where practical.
- Keep strong negative tests for invalid DSL input and malformed expression shapes.
- Assert parameter ordering and placeholder-shifting behavior explicitly in snapshots.
- Keep dedicated SQL-injection and identifier-safety regression coverage.
- Add randomized/property cases for clause-composition and parameterized edge cases.

## 5. Scope Guardrails

- No full ORM default requirement in Phase 4.
- No change to "raw SQL first-class" default posture.
- Keep PostgreSQL-specific features in explicit dialect layers.
- Preserve Objective-C/GNUstep-first API style over syntax mimicry of other ecosystems.
