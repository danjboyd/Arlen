# Phase 5B Runtime Routing

Phase 5B introduces multi-database runtime routing primitives through
`ALNDatabaseRouter`.

## 1. Scope

`ALNDatabaseRouter` provides:

- operation-class aware target selection (`read`, `write`, `transaction`)
- optional read-after-write stickiness with bounded scope
- optional tenant/shard route override hook
- structured routing diagnostics events for observability

The router remains SQL-first and adapter-driven:

- no ORM coupling
- no hidden query rewriting
- routing decisions are explicit and testable

## 2. Core API

Header:

- `src/Arlen/Data/ALNDatabaseRouter.h`

Key contracts:

- `initWithTargets:defaultReadTarget:defaultWriteTarget:error:`
- `resolveTargetForOperationClass:routingContext:error:`
- `executeQuery:parameters:routingContext:error:`
- `executeCommand:parameters:routingContext:error:`
- `withTransactionUsingBlock:routingContext:error:`

## 3. Routing Semantics

Default behavior:

- reads route to `defaultReadTarget`
- writes/transactions route to `defaultWriteTarget`

Stickiness behavior:

- configure `readAfterWriteStickinessSeconds > 0`
- write success records scope timestamp
- subsequent reads within window route to write target
- scope key defaults to `stickiness_scope` in `routingContext`

Hook behavior:

- `routeTargetResolver` can override resolved target from context
- hook receives operation class, routing context, and default target
- unknown returned target fails with deterministic router diagnostics

Fallback behavior:

- `fallbackReadToWriteOnError` defaults to `YES`
- read target execution errors may retry once against write target
- fallback emits explicit diagnostics event metadata

## 4. Diagnostics Contract

`routingDiagnosticsListener` receives immutable event dictionaries with:

- operation class and stage
- selected/default/fallback targets
- stickiness usage + scope
- resolver override indicator
- optional tenant/shard identifiers
- optional error domain/code for fallback events

Event keys are constants in `ALNDatabaseRouter.h`.

## 5. Verification

Unit coverage:

- `tests/unit/Phase5BTests.m`

Integration coverage:

- `tests/integration/PostgresIntegrationTests.m` method
  `testDatabaseRouterReadWriteRoutingAcrossLiveAdapters`

Contract mapping:

- `tests/fixtures/phase5a/data_layer_reliability_contracts.json`
- `tests/fixtures/phase5a/external_regression_intake.json`
