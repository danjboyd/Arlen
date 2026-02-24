# Phase 7A Runtime Hardening

Phase 7A defines runtime hardening contracts for `boomhauer` and `propane` worker paths.

This document captures the initial 7A implementation slice completed on 2026-02-23.

## 1. Scope (Initial Slice)

- WebSocket session backpressure boundary for runtime worker/session paths.
- HTTP session backpressure boundary for runtime worker/session paths.
- Deterministic overload diagnostics instead of silent runtime fallback.
- Explicit config and environment contract for the session-limit safety boundary.

## 2. Runtime Limit Contract

Runtime key:

```plist
runtimeLimits = {
  maxConcurrentHTTPSessions = 256;
  maxConcurrentWebSocketSessions = 256;
};
```

Environment overrides:

- `ARLEN_MAX_HTTP_SESSIONS`
- legacy compatibility fallback: `MOJOOBJC_MAX_HTTP_SESSIONS`
- `ARLEN_MAX_WEBSOCKET_SESSIONS`
- legacy compatibility fallback: `MOJOOBJC_MAX_WEBSOCKET_SESSIONS`

Contract behavior:

- Default is `256` when unset.
- Values are normalized to integer form in final config output.
- Limits apply to HTTP session concurrency and websocket session concurrency
  managed by runtime worker threads.

## 3. Backpressure Response Contract

When an incoming HTTP session would exceed `runtimeLimits.maxConcurrentHTTPSessions`:

- return status: `503 Service Unavailable`
- return body: `server busy\n`
- include header: `Retry-After: 1`
- include header: `X-Arlen-Backpressure-Reason: http_session_limit`
- close the client socket; do not silently downgrade behavior

When an incoming websocket upgrade would exceed `runtimeLimits.maxConcurrentWebSocketSessions`:

- return status: `503 Service Unavailable`
- return body: `server busy\n`
- include header: `Retry-After: 1`
- include header: `X-Arlen-Backpressure-Reason: websocket_session_limit`
- close the client socket; do not silently downgrade behavior

## 4. Executable Verification

Machine-readable contract fixture:

- `tests/fixtures/phase7a/runtime_hardening_contracts.json`

Runtime/config verification:

- `tests/unit/ConfigTests.m`:
  - `testLoadConfigMergesAndAppliesDefaults`
  - `testEnvironmentOverridesRequestLimitsAndProxyFlags`
  - `testLegacyEnvironmentPrefixFallback`
- `tests/integration/HTTPIntegrationTests.m`:
  - `testHTTPSessionLimitReturns503UnderBackpressure`
  - `testWebSocketSessionLimitReturns503UnderBackpressure`
- `tests/unit/Phase7ATests.m`:
  - `testRuntimeHardeningContractFixtureSchemaAndTestCoverage`

## 5. Remaining 7A Follow-On

The broader 7A roadmap still includes:

- stronger timeout contracts (read/write/header/body/idle)
- additional graceful reload/shutdown hardening contracts
- additional crash-loop and slow-downstream failure-mode regression coverage
