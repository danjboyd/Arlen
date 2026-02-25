# Concurrency Audit (2026-02-25)

## Scope

Audit target was Arlen runtime paths where concurrent request/session handling can interact with mutable state and process lifecycle:

- HTTP server connection/session lifecycle
- websocket fanout/session state
- template runtime shared registries
- database driver global initialization
- shared singleton services

This audit was performed immediately after fixing worker crash issue #1 (`malloc_consolidate` / intermittent `502`) via commit `0920889`.

## Changes Applied During Audit

1. Serialized dispatch lifecycle hardening (already shipped in `0920889`):
   - `serialized` mode now enforces one request per connection (`Connection: close`)
   - detached per-connection threading disabled in serialized mode
   - regression test added: `HTTPIntegrationTests::testProductionSerializedDispatchClosesHTTPConnections`

2. Websocket session state race hardening:
   - added lock-protected closed-state snapshot in
     `src/Arlen/HTTP/ALNHTTPServer.m` (`ALNWebSocketClientSession`)
   - websocket receive loop now checks `isClosedSnapshot` instead of raw property read

3. Template registry initialization hardening:
   - synchronized lazy initialization for `ALNEOCTemplateRegistry` in
     `src/Arlen/MVC/Template/ALNEOCRuntime.m`

## Findings

### High Priority

1. Global stop flag was process-global, not server-instance scoped. `resolved`
   - Location: `src/Arlen/HTTP/ALNHTTPServer.m` (`gShouldRun`)
   - Risk: multiple `ALNHTTPServer` instances in one process can interfere with each other during stop/reload.
   - Applied fix:
     - per-instance `shouldRun` state now controls request/session loops
     - process signal handling now uses `gSignalStopRequested` only for signal-triggered termination

2. Concurrent mode used detached thread per accepted connection. `resolved`
   - Location: `src/Arlen/HTTP/ALNHTTPServer.m` (`detachNewThreadSelector`)
   - Risk: thread fanout pressure and lifecycle complexity under heavy keep-alive/slow-client traffic.
   - Applied fix:
     - bounded HTTP worker pool (`maxConcurrentHTTPWorkers`)
     - bounded queue (`maxQueuedHTTPConnections`)
     - deterministic backpressure response (`X-Arlen-Backpressure-Reason: http_worker_queue_full`)

### Medium Priority

3. Realtime hub subscription set was global singleton and unbounded by channel cardinality. `resolved`
   - Location: `src/Arlen/Support/ALNRealtime.m`
   - Risk: memory growth and stale subscription accumulation if app-level flows fail to unsubscribe cleanly.
   - Applied fix:
     - optional global cap (`maxRealtimeTotalSubscribers`)
     - optional per-channel cap (`maxRealtimeChannelSubscribers`)
     - metrics snapshot for active/peak/churn/rejected subscribers

4. libpq loader synchronization used `@synchronized([NSObject class])`. `resolved`
   - Location: `src/Arlen/Data/ALNPg.m`
   - Risk: coarse global lock coupling; avoid locking on broadly shared class object.
   - Applied fix:
     - dedicated lock token now isolates libpq loader initialization path

5. EOC strict-mode options were thread-local and sticky for thread lifetime. `resolved`
   - Location: `src/Arlen/MVC/Template/ALNEOCRuntime.m`
   - Risk: option bleed across reused worker threads if callers set strict flags without reset discipline.
   - Applied fix:
     - scoped strict-mode API (`ALNEOCPushRenderOptions` / `ALNEOCPopRenderOptions`)
     - view rendering now uses scoped option handling

## Proactive Test Plan

1. Add a stress integration suite for HTTP session lifecycle. `completed`
   - mixed keep-alive + slow clients + websocket upgrades
   - run in both `serialized` and `concurrent` modes

2. Add sanitizer gating focused on runtime concurrency. `completed`
   - ASAN/UBSAN minimum gate stays required
   - add TSAN experiment profile where toolchain/runtime support permits

3. Add long-running fanout test for realtime hub. `completed`
   - subscription churn + forced disconnect paths
   - validate bounded growth and deterministic cleanup

## Status

- Critical production crash issue is resolved in consumer validation.
- Additional hardening in websocket and template registry paths has been applied.
- Follow-up concurrency hardening actions above are now implemented with unit/integration/CI coverage.
