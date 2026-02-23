# Phase 5D Typed Data Contracts

Phase 5D adds SQL-first typed contract workflows without introducing ORM coupling.

## 1. Scope

Phase 5D implementation includes:

- optional typed table contracts in `schema-codegen`
- generated runtime decode helpers for typed row mapping
- optional typed SQL artifact compilation workflow

Raw SQL and existing builder usage remain supported unchanged.

## 2. Typed Table Contracts

Enable typed contracts with:

```bash
/path/to/Arlen/bin/arlen schema-codegen --typed-contracts --force
```

For each generated table class, codegen now emits:

- `<TableClass>Row`
- `<TableClass>Insert`
- `<TableClass>Update`

And table-level helpers:

- `insertContract:`
- `updateContract:`
- `decodeTypedRow:error:`
- `decodeTypedRows:error:`

Decode helpers enforce deterministic runtime failures via generated decode error domain/codes.

## 3. Typed SQL Artifacts

Generate typed SQL helpers from SQL files:

```bash
/path/to/Arlen/bin/arlen typed-sql-codegen --force
```

Default input directory:

- `db/sql/typed`

Each SQL file uses metadata comments:

```sql
-- arlen:name list_users_by_status
-- arlen:params status:text limit:int
-- arlen:result id:text name:text
SELECT id, name FROM users WHERE status = $1 LIMIT $2;
```

Generated output (default):

- `src/Generated/ALNDBTypedSQL.h`
- `src/Generated/ALNDBTypedSQL.m`
- `db/schema/arlen_typed_sql.json`

Artifacts include typed parameter builders and typed row decode helpers per query.

## 4. Compatibility Contract

- Existing `schema-codegen` output remains backward compatible when `--typed-contracts` is omitted.
- Existing SQL builder and raw SQL APIs continue to function unchanged.
- Typed workflows are additive and opt-in.

## 5. Verification

Unit coverage:

- `tests/unit/SchemaCodegenTests.m`

Integration coverage:

- `tests/integration/PostgresIntegrationTests.m`
  - `testArlenSchemaCodegenTypedContractsCompileAndDecodeDeterministically`
  - `testArlenTypedSQLCodegenGeneratesTypedParameterAndResultHelpers`
