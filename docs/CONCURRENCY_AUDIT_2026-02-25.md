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

1. Global stop flag is process-global, not server-instance scoped.
   - Location: `src/Arlen/HTTP/ALNHTTPServer.m` (`gShouldRun`)
   - Risk: multiple `ALNHTTPServer` instances in one process can interfere with each other during stop/reload.
   - Recommendation: move stop state to per-instance field and isolate signal handling/loop control per server instance.

2. Concurrent mode still uses detached thread per accepted connection.
   - Location: `src/Arlen/HTTP/ALNHTTPServer.m` (`detachNewThreadSelector`)
   - Risk: thread fanout pressure and lifecycle complexity under heavy keep-alive/slow-client traffic.
   - Recommendation: replace detached-thread model with bounded worker pool or queue-driven execution.

### Medium Priority

3. Realtime hub subscription set is global singleton and unbounded by channel cardinality.
   - Location: `src/Arlen/Support/ALNRealtime.m`
   - Risk: memory growth and stale subscription accumulation if app-level flows fail to unsubscribe cleanly.
   - Recommendation: add optional channel/subscriber caps + stale-subscription pruning diagnostics.

4. libpq loader synchronization uses `@synchronized([NSObject class])`.
   - Location: `src/Arlen/Data/ALNPg.m`
   - Risk: coarse global lock coupling; avoid locking on broadly shared class object.
   - Recommendation: switch to dedicated static lock token for libpq load path.

5. EOC strict-mode options are thread-local and sticky for thread lifetime.
   - Location: `src/Arlen/MVC/Template/ALNEOCRuntime.m`
   - Risk: option bleed across reused worker threads if callers set strict flags without reset discipline.
   - Recommendation: add scoped push/pop API for render options (RAII-style helper).

## Proactive Test Plan

1. Add a stress integration suite for HTTP session lifecycle:
   - mixed keep-alive + slow clients + websocket upgrades
   - run in both `serialized` and `concurrent` modes

2. Add sanitizer gating focused on runtime concurrency:
   - ASAN/UBSAN minimum gate stays required
   - add TSAN experiment profile where toolchain/runtime support permits

3. Add long-running fanout test for realtime hub:
   - subscription churn + forced disconnect paths
   - validate bounded growth and deterministic cleanup

## Status

- Critical production crash issue is resolved in consumer validation.
- Additional hardening in websocket and template registry paths has been applied.
- Remaining items above are proactive engineering backlog, not currently known live regressions.
