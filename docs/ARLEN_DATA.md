# ArlenData Reuse Guide

This guide defines how to consume Arlen's data layer independently of the HTTP/MVC runtime.

## 1. Scope

`ArlenData` is the standalone data-layer surface composed of:

- `src/Arlen/Data/*`
- `src/ArlenData/ArlenData.h` (umbrella header)

Primary contracts:

- `ALNSQLBuilder` (v2 query builder with expression selects/predicates/order clauses, subquery+lateral joins, and tuple-friendly cursor predicates)
- `ALNPostgresSQLBuilder` (PostgreSQL dialect extension for conflict/upsert, including expression-based `DO UPDATE SET` and optional `DO UPDATE ... WHERE`)
- `ALNDatabaseAdapter` / `ALNDatabaseConnection`
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
