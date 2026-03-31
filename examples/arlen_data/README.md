# ArlenData Example

This example demonstrates using Arlen's data layer without the HTTP/MVC runtime.

Build and run from repo root:

```bash
source /path/to/Arlen/tools/source_gnustep_env.sh
make test-data-layer
```

The executable (`build/arlen-data-example`) composes CTE/join/group queries and a
PostgreSQL upsert snapshot using `ArlenData/ArlenData.h`.

Phase 17 note:

- `ArlenData` now also exposes `ALNSQLDialect`, `ALNPostgresDialect`,
  `ALNMSSQLDialect`, and the optional `ALNMSSQL` adapter
- `ALNSQLBuilder build:` remains PostgreSQL-default
- use `buildWithDialect:[ALNMSSQLDialect sharedDialect]` for SQL Server
  compilation
- runtime MSSQL usage requires an ODBC manager/runtime client plus a SQL Server
  driver; core Arlen does not hard-link to Microsoft’s driver
