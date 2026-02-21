# SQL Builder Conformance Matrix (Phase 4E)

This matrix defines stable SQL/parameter conformance targets for Arlen's Phase 4 SQL builder surface.

Machine-readable source:

- `tests/fixtures/sql_builder/phase4e_conformance_matrix.json`

Primary verification suite:

- `tests/unit/Phase4ETests.m`

## Matrix Coverage

| Scenario ID | Category | Contract Focus | Regression Gate |
| --- | --- | --- | --- |
| `exists_any_all` | predicate composition | `EXISTS` + `ANY` + `ALL` placeholder ordering | `testConformanceMatrixMatchesExpectedSnapshots` |
| `expression_ordering` | expression-aware ordering | `NULLS FIRST/LAST` + identifier-safe expression templates in `ORDER BY` | `testConformanceMatrixMatchesExpectedSnapshots` |
| `lateral_join` | lateral join composition | `LEFT JOIN LATERAL` SQL rendering + parameter stability | `testConformanceMatrixMatchesExpectedSnapshots` |
| `locking_skip_locked` | locking semantics | `FOR UPDATE OF ... SKIP LOCKED` rendering contract | `testConformanceMatrixMatchesExpectedSnapshots` |
| `template_select` | expression templates | identifier binding safety + placeholder shifting | `testConformanceMatrixMatchesExpectedSnapshots` |
| `set_operation` | set composition | parameter ordering across `UNION ALL` + `EXCEPT` | `testConformanceMatrixMatchesExpectedSnapshots` |
| `tuple_cursor` | tuple predicates + ordering | cursor predicate rendering + expression-aware ordering | `testConformanceMatrixMatchesExpectedSnapshots` |
| `window_named` | window composition | named window binding + expression alias rendering | `testConformanceMatrixMatchesExpectedSnapshots` |
| `postgres_upsert_expression` | PostgreSQL dialect | structured upsert assignment expressions + `DO UPDATE WHERE` | `testConformanceMatrixMatchesExpectedSnapshots` |

## Property/Long-Run Gates

The matrix snapshots are reinforced by deterministic property/long-run tests:

- dictionary ordering determinism (`insert`/`update`)
- placeholder coverage/contiguity (`$1..$N`)
- tuple predicate parameter ordering
- nested expression shape stress runs

These run in `tests/unit/Phase4ETests.m` and are part of `make test-unit`.

## PostgreSQL Execution Gates

Compile-time snapshots are paired with PostgreSQL execution regressions in `tests/unit/PgTests.m`:

- matrix-aligned advanced builder execution coverage
- long projection + multi-parameter UTF-8 transport stress coverage (SQLSTATE `22021` regression class)
