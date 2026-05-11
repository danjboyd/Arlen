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
