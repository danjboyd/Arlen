# Arlen ORM Migration Contracts

ArlenORM closes the migration-history gap by treating historical ORM
descriptors as explicit artifacts instead of an implicit side effect of current
model code.

## Shipped Contracts

- `ALNORMDescriptorSnapshot`
  - serializes stable SQL ORM descriptor snapshots
  - replays descriptor objects from a checked-in snapshot document
- `ALNORMSchemaDrift`
  - compares current descriptors against a historical snapshot
  - fails closed with explicit diagnostics when schema/codegen drift appears

The snapshot format is:

```text
arlen-orm-descriptor-snapshot-v1
```

## Why This Exists

Arlen follows Django/Ecto-style discipline here:

- old migration history must not depend on whatever the current model class
  happens to do today
- schema/codegen drift must produce diagnostics, not undefined behavior
- descriptor evolution is versioned and replayable

## Typical Workflow

1. Reflect or generate current ORM descriptors.
2. Write a snapshot document under app-owned history, typically near schema
   artifacts.
3. Validate future descriptor changes against that snapshot when replaying or
   certifying migrations.

## Current Boundary

This is a descriptor-history contract, not a second migration runner. Arlen's
canonical migration execution still lives in `ArlenData` and
`ALNMigrationRunner`.

## Generated property naming update

Regenerate SQL ORM headers, implementations and manifests together when adopting
reserved-name protection. Columns such as `State`, `Description`, `class`, `hash`,
`context` and `descriptor` now have safe property aliases; consult each manifest's
`property_name` or configure `property_names` in descriptor overrides. Update
application property accesses and deliberately review descriptor snapshot drift.
Original SQL columns, logical field names and relationship keys do not change.

Generated setters now preserve internal capitalization (`displayName` uses
`setDisplayName:`). Replace any direct calls to the previously emitted
`setDisplayname:` spelling. Regeneration is an API update, not a database migration.

## Adopting quoted SQL identifiers

Regenerate ORM models from original physical metadata to adopt quoted legacy
names. Ordinary generated names remain stable. Previously rejected punctuation
names now receive safe aliases; resolve normalization collisions with
`field_names` and inspect the manifest before updating application call sites.
Property overrides do not rename columns. See the
[identifier contract](ARLEN_ORM.md#quoted-sql-identifiers).

## Generated descriptor initialization update

Regenerate SQL model implementations with the updated `ALNORMCodegen` and rebuild
your application to adopt the fix for [issue #32](https://github.com/danjboyd/Arlen/issues/32).
Previously generated `+modelDescriptor` methods used an unsynchronized nil check;
concurrent first use could construct multiple descriptors or crash under ARC.
Updating the framework archive alone does not rewrite existing generated source.

New output uses a separate `dispatch_once` token for each model and retains the
fully initialized descriptor for subsequent callers. No application warm-up is
required. Model names, fields, relationships, and descriptor snapshot formats are
unchanged; no database migration is needed. This guarantee covers descriptor
initialization, not concurrent mutation of model instances or ORM contexts.
