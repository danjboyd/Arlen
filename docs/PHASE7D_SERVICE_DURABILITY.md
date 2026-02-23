# Phase 7D: Service Durability

Status: Initial slice implemented (2026-02-23)

This document defines the first durability contract slice for ecosystem services (jobs/cache/mail/attachments).

## 1. Scope

Phase 7D initial slice focuses on deterministic behavior for:

- jobs idempotency-key deduplication and replay safety
- cache expiry/removal consistency contracts
- mail retry policy wrapper contracts
- attachment retry policy wrapper contracts

## 2. Jobs Durability Contracts

`ALNJobAdapter` enqueue options now support:

- `idempotencyKey` (`NSString`)

Behavior:

- when `idempotencyKey` is provided and the mapped job is still pending/leased, enqueue returns the existing `jobID`
- duplicate enqueue does not create a second queued copy
- once the job is acknowledged, the key is released and a new enqueue with the same key creates a new `jobID`

Adapters covered:

- `ALNInMemoryJobAdapter`
- `ALNFileJobAdapter` (mapping is persisted in adapter state)

## 3. Cache Durability Contracts

`ALNRunCacheAdapterConformanceSuite` now enforces additional semantics:

- `ttlSeconds = 0` represents non-expiring storage (value remains readable across future timestamps)
- `setObject:nil` is treated as deterministic key removal

These checks apply across cache adapters through the shared conformance suite.

## 4. Mail Retry Policy Contract

`ALNRetryingMailAdapter` wraps any `id<ALNMailAdapter>` with deterministic retry policy controls:

- `maxAttempts` (default `3`)
- `retryDelaySeconds` (default `0`)

Behavior:

- retries delivery attempts up to `maxAttempts`
- succeeds immediately on first successful base-adapter delivery
- on exhaustion returns deterministic `ALNServiceErrorDomain` error:
  - code `4311`
  - user info includes `attempt_count`, `adapter`, and `NSUnderlyingErrorKey` when available

## 5. Attachment Retry Policy Contract

`ALNRetryingAttachmentAdapter` wraps any `id<ALNAttachmentAdapter>` for `saveAttachmentNamed:...` retries:

- `maxAttempts` (default `3`)
- `retryDelaySeconds` (default `0`)

Behavior:

- retries save attempts up to `maxAttempts`
- on exhaustion returns deterministic `ALNServiceErrorDomain` error:
  - code `564`
  - user info includes `attempt_count`, `adapter`, and `NSUnderlyingErrorKey` when available

Read/list/delete/reset operations are forwarded directly to the base adapter.

## 6. Contract Fixture

- `tests/fixtures/phase7d/service_durability_contracts.json`

Fixture validation test:

- `tests/unit/Phase7DTests.m` (`testServiceDurabilityContractFixtureSchemaAndTestCoverage`)

## 7. Verification

Primary tests:

- `tests/unit/Phase7DTests.m`
  - `testInMemoryJobAdapterIdempotencyKeyDeduplicatesUntilAcknowledged`
  - `testFileJobAdapterIdempotencyKeyPersistsAcrossAdapterReload`
  - `testCacheConformanceSuiteCoversPersistenceAndNilRemovalSemantics`
  - `testRetryingMailAdapterRetriesToSuccess`
  - `testRetryingMailAdapterReturnsDeterministicErrorWhenExhausted`
  - `testRetryingAttachmentAdapterRetriesToSuccess`
  - `testRetryingAttachmentAdapterReturnsDeterministicErrorWhenExhausted`

Conformance and compatibility coverage:

- `tests/unit/Phase3ETests.m`
  - `testPluginWiresAdaptersAndRunsCompatibilitySuites`
  - `testFileJobAdapterConformanceSuite`
