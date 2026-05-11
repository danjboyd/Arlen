# Arlen ORM Backend Matrix

Arlen ships two ORM families with intentionally different boundaries.

## SQL ORM

`ALNORMContext` exposes backend capability metadata on top of
`ALNDatabaseAdapter`.

### PostgreSQL

- SQL runtime: yes
- schema reflection: yes
- generated models: yes
- associations: yes
- many-to-many: yes
- strict loading: yes
- optimistic locking: yes
- upsert: yes

### MSSQL

- SQL runtime: yes
- schema reflection: no in the current ORM contract
- generated models: no
- associations: yes for runtime descriptors that already exist
- many-to-many: yes at the runtime layer
- strict loading: yes
- optimistic locking: yes
- upsert: no in the current ORM contract

## Dataverse ORM

`ALNORMDataverseContext` exposes a separate capability contract on top of
`ALNDataverseClient`.

- SQL runtime: no
- Dataverse ORM: yes
- generated models: yes
- lookup relations: yes
- inferred reverse collections: yes
- many-to-many: no in the current ORM bridge
- transactions: no
- batch writes: yes
- upsert: yes

## Design Rule

Arlen does not pretend PostgreSQL, MSSQL, and Dataverse are interchangeable.
Capability metadata is part of the public contract so apps can fail closed
instead of discovering backend gaps at runtime by accident.
