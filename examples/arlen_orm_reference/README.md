# Arlen ORM Reference

`ArlenORM` remains optional. This reference example is a small command-line
entrypoint that exercises the shipped Phase 26 contracts without requiring a
database server:

```bash
source tools/source_gnustep_env.sh
make arlen-orm-reference
./build/arlen-orm-reference
```

The example:

- reflects the checked-in SQL schema fixture into ORM descriptors
- emits a historical descriptor snapshot
- shows the SQL ORM capability contract for PostgreSQL
- reflects the checked-in Dataverse fixture into separate Dataverse ORM
  descriptors

This is intentionally a reference/demo surface rather than a required app
scaffold. Apps that do not want ORM still ignore the entire package.
