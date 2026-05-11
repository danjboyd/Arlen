# Phase 5C Multi-Database Tooling

Phase 5C extends Arlen CLI tooling to support explicit multi-database targets for
migrations and schema-codegen.

## 1. Scope

Phase 5C adds:

- `arlen migrate --database <target>`
- `arlen schema-codegen --database <target>`
- deterministic migration state per named target
- schema manifest metadata that records the selected database target

This remains SQL-first and adapter-first:

- no ORM requirement
- explicit target selection at CLI boundary
- deterministic, file-system-friendly output defaults per target

## 2. Config Contract

Existing single-database config remains valid:

```plist
database = {
  connectionString = "...";
  poolSize = 8;
};
```

Multi-target config is additive:

```plist
databases = {
  primary = {
    connectionString = "...";
    poolSize = 8;
  };
  analytics = {
    connectionString = "...";
    poolSize = 4;
  };
};
```

Resolution order for connection strings:

1. `--dsn`
2. `ARLEN_DATABASE_URL_<TARGET>` (for non-default targets)
3. `ARLEN_DATABASE_URL`
4. config target entry (`databases.<target>.connectionString`)
5. fallback `config.database.connectionString` (for compatibility)

## 3. Migration Target Semantics

When `--database` is omitted:

- target = `default`
- migration path = `db/migrations`
- migration state table = `arlen_schema_migrations`

When `--database <target>` is present:

- migration path = `db/migrations/<target>`
- migration state table = `arlen_schema_migrations__<target>`

Target names must match:

- `[a-z][a-z0-9_]*`
- max length: 32

This guarantees deterministic and injection-safe migration state routing.

## 4. Schema Codegen Target Semantics

When `--database` is omitted:

- behavior is unchanged (`src/Generated`, `db/schema/arlen_schema.json`, `ALNDB` prefix)

When `--database <target>` is present and output options are omitted:

- output dir default: `src/Generated/<target>`
- manifest default: `db/schema/arlen_schema_<target>.json`
- class prefix default: `ALNDB<PascalTarget>`

Generated manifest now includes:

- `"database_target": "<target>"`

## 5. Verification

Integration coverage:

- `tests/integration/PostgresIntegrationTests.m`
  - `testArlenMigrateCommandSupportsNamedDatabaseTargetsAndFailureRetry`
  - `testArlenSchemaCodegenSupportsNamedDatabaseTargets`

Unit coverage:

- `tests/unit/SchemaCodegenTests.m`
  - `testRenderArtifactsIncludesDatabaseTargetMetadata`
  - `testRenderArtifactsRejectsInvalidDatabaseTarget`

Contract fixtures:

- `tests/fixtures/phase5a/data_layer_reliability_contracts.json`
- `tests/fixtures/phase5a/external_regression_intake.json`
