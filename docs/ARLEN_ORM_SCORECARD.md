# Arlen ORM Scorecard

Phase 26 is done when Arlen can make a narrow, defensible best-in-class claim
for its target ecosystem.

## Shipped Proof Points

- Optional packaging:
  - `ArlenORM` is not folded into `Arlen/Arlen.h`
- SQL-first architecture:
  - `ALNSQLBuilder`, adapters, and raw SQL remain first-class
- Deterministic reflection/codegen:
  - stable SQL descriptors and snapshot artifacts
  - deterministic Dataverse descriptor generation from normalized metadata
- Explicit performance discipline:
  - joined/select-in/no-load/raise-on-access SQL relation strategies
  - explicit Dataverse relation loads instead of hidden IO
- Mutation discipline:
  - SQL changesets/value converters/write options
  - Dataverse changesets that preserve native lookup/choice/batch semantics
- Backend honesty:
  - explicit SQL capability metadata
  - separate Dataverse ORM capability metadata
- Confidence story:
  - split Phase 26 lanes for unit, generated, integration, backend parity,
    perf, live, and full confidence artifacts

## The Claim Arlen Can Defend

Arlen has a best-in-class optional ORM story for a SQL-first Objective-C /
GNUstep web framework, especially for teams that need:

- deterministic SQL descriptors and replayable history
- explicit load strategy control instead of callback-heavy magic
- raw SQL escape hatches that remain first-class
- a credible bridge from SQL ORM usage into Dataverse ORM without pretending
  Dataverse is a SQL dialect
