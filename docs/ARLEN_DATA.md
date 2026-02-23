# ArlenData Reuse Guide

This guide defines how to consume Arlen's data layer independently of the HTTP/MVC runtime.

## 1. Scope

`ArlenData` is the standalone data-layer surface composed of:

- `src/Arlen/Data/*`
- `src/ArlenData/ArlenData.h` (umbrella header)

Primary contracts:

- `ALNSQLBuilder` (v2 query builder with expression selects/predicates/order clauses, subquery+lateral joins, and tuple-friendly cursor predicates)
- `ALNPostgresSQLBuilder` (PostgreSQL dialect extension for conflict/upsert, including expression-based `DO UPDATE SET` and optional `DO UPDATE ... WHERE`)
- `ALNSchemaCodegen` (deterministic typed schema helper artifact rendering)
- `ALNPg` builder execution/caching/diagnostics APIs (`executeBuilderQuery`, `executeBuilderCommand`, query stage listener events)
- `ALNDatabaseAdapter` / `ALNDatabaseConnection`
- `ALNDatabaseRouter` (multi-target runtime routing with stickiness and diagnostics)
- `ALNDisplayGroup`
- `ALNAdapterConformance` helpers
- `ALNPg`, `ALNMigrationRunner`, `ALNGDL2Adapter`

## 2. Non-Arlen Consumption

Compile only data-layer sources and import the umbrella header:

```objc
#import "ArlenData/ArlenData.h"
```

Reference build/usage validation:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make test-data-layer
```

`make test-data-layer` builds and runs `build/arlen-data-example` using only ArlenData sources.

## 3. Git Partial Checkout

If consumers only need ArlenData, use sparse checkout:

```bash
git clone --filter=blob:none --no-checkout https://github.com/danjboyd/Arlen.git
cd Arlen
git sparse-checkout init --cone
git sparse-checkout set src/Arlen/Data src/ArlenData docs/ARLEN_DATA.md examples/arlen_data GNUmakefile
git checkout main
```

This keeps clone size focused on the data layer and its example/docs.

## 4. Optional Split-Repo Workflow

For teams that want a separate distribution repository, export ArlenData-only history/worktree:

```bash
git subtree split --prefix=src/Arlen/Data --branch arlen-data-split
```

Then publish `arlen-data-split` to a dedicated repository and add `src/ArlenData/ArlenData.h` as the umbrella include surface.

## 5. Versioning Policy

ArlenData follows semantic versioning aligned with framework release tags:

- `MAJOR`: breaking API or behavior changes in `src/Arlen/Data` or `src/ArlenData`
- `MINOR`: additive APIs/capabilities (for example, new query-builder features)
- `PATCH`: bug fixes and diagnostics hardening without API breaks

Compatibility contract:

- Changes to SQL rendering behavior require deterministic snapshot updates in unit tests.
- Data-layer standalone validation (`make test-data-layer`) must pass in CI.
- Dialect-specific additions must remain in explicit dialect modules (`ALNPostgresSQLBuilder`) and not leak into base builder requirements.

## 6. CI Enforcement

ArlenData reuse remains continuously validated by CI via:

- `tools/ci/run_phase3c_quality.sh` calling `make test-data-layer`
- unit snapshots in `tests/unit/Phase3GTests.m`
- Phase 4A safety/IR regressions in `tests/unit/Phase4ATests.m`
- PostgreSQL execution regression for identifier-bound templates in `tests/unit/PgTests.m`

## 7. Expression Template Safety Contracts (Phase 4A)

Expression-capable builder APIs now route through a trusted-template IR (`trusted-template-v1`) with explicit contracts:

- Identifier slots use `{{token}}` and must be satisfied by `identifierBindings`.
- Identifier bindings must resolve to safe SQL identifiers/wildcards (for example `d.state_code`, `d.*`, `*`).
- Expression parameters must be an array and placeholders must map exactly to `$1..$N`.
- Malformed expression IR shapes fail deterministically with `ALNSQLBuilderErrorDomain` diagnostics.

These contracts apply to:

- `selectExpression:...identifierBindings:parameters:`
- `whereExpression:identifierBindings:parameters:`
- `havingExpression:identifierBindings:parameters:`
- `orderByExpression:...identifierBindings:parameters:`
- subquery/lateral join `onExpression` APIs with `identifierBindings`

## 8. Typed Schema Codegen Workflow (Phase 4C)

Use the CLI in an app root with PostgreSQL config:

```bash
/path/to/Arlen/bin/arlen schema-codegen --env development
```

This introspects `information_schema` and writes deterministic artifacts:

- `src/Generated/ALNDBSchema.h`
- `src/Generated/ALNDBSchema.m`
- `db/schema/arlen_schema.json`

Generated table APIs expose:

- typed table-level builder entrypoints (`selectAll`, `selectColumns`, `insertValues`, `updateValues`, `deleteBuilder`)
- typed column accessor methods (`columnX`, `qualifiedColumnX`)

Consumers can include generated files in non-Arlen builds as long as `ALNSQLBuilder` is linked.

## 9. Phase 4D Query Execution Diagnostics + Caching

`ALNPgConnection`/`ALNPg` now expose builder-driven execution helpers:

- `executeBuilderQuery:error:`
- `executeBuilderCommand:error:`
- `resetExecutionCaches`

Runtime controls:

- prepared statement reuse policy: `disabled`, `auto`, `always`
- cache limits:
  - `preparedStatementCacheLimit`
  - `builderCompilationCacheLimit`
- diagnostics controls:
  - `queryDiagnosticsListener` (stage events: `compile`, `execute`, `result`, `error`)
  - `emitDiagnosticsEventsToStderr`
  - `includeSQLInDiagnosticsEvents` (default off; redaction-safe metadata remains default)

## 10. Phase 4E Conformance + Migration Hardening

Conformance matrix:

- `docs/SQL_BUILDER_CONFORMANCE_MATRIX.md`
- `tests/fixtures/sql_builder/phase4e_conformance_matrix.json`
- `tests/unit/Phase4ETests.m`

Migration/deprecation docs:

- `docs/SQL_BUILDER_PHASE4_MIGRATION.md`
- `docs/RELEASE_PROCESS.md` (phase-4 transitional API lifecycle)

## 11. Phase 5B Multi-Database Runtime Routing

`ALNDatabaseRouter` provides operation-aware target selection on top of adapter contracts:

- read routes (`executeQuery`) default to a named read target
- write routes (`executeCommand`, transactions) default to a named write target
- optional read-after-write stickiness via bounded scope keys in routing context
- optional tenant/shard hook override via `routeTargetResolver`
- optional read fallback to write target on execution error
- structured route diagnostics via `routingDiagnosticsListener`

Primary reference:

- `docs/PHASE5B_RUNTIME_ROUTING.md`

## 12. Phase 5C Target-Aware Migration + Codegen Tooling

CLI workflows now support explicit target selection:

- `arlen migrate --database <target>`
- `arlen schema-codegen --database <target>`

Target-aware defaults:

- migrations path: `db/migrations/<target>`
- migration state table: `arlen_schema_migrations__<target>`
- schema output dir: `src/Generated/<target>`
- schema manifest path: `db/schema/arlen_schema_<target>.json`

Schema manifests include `database_target` metadata for deterministic per-target artifact tracking.

Primary reference:

- `docs/PHASE5C_MULTI_DATABASE_TOOLING.md`

## 13. Phase 5D Typed Data Contracts + Typed SQL

Schema codegen now supports optional typed contract output:

- `arlen schema-codegen --typed-contracts`

When enabled, generated schema artifacts include:

- per-table `Row`, `Insert`, and `Update` classes
- table-level `insertContract` / `updateContract` helpers
- deterministic runtime decode helpers (`decodeTypedRow`, `decodeTypedRows`)
- generated decode error domain + error codes

Typed SQL helpers are available through:

- `arlen typed-sql-codegen`

This compiles SQL files with metadata comments into typed parameter/result helper APIs.

Primary reference:

- `docs/PHASE5D_TYPED_CONTRACTS.md`
