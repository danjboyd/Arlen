# Phase 7C Observability and Operability Maturity

Phase 7C defines deterministic observability and operability contracts for runtime request flows and deployment probes.

This document captures the initial 7C implementation slice completed on 2026-02-23.

## 1. Scope (Initial Slice)

- Request-level correlation and trace propagation headers with deterministic shapes.
- Trace exporter payload enrichment for route/controller/action correlation.
- JSON health/readiness signal payloads with deterministic check objects.
- Strict readiness policy switch for startup-gated `readyz` behavior.
- Executable deployment operability validation script wired into release smoke runbook checks.

## 2. Observability Config Contract

Top-level config key:

```plist
observability = {
  tracePropagationEnabled = YES;
  healthDetailsEnabled = YES;
  readinessRequiresStartup = NO;
};
```

Environment overrides:

- `ARLEN_TRACE_PROPAGATION_ENABLED`
- `ARLEN_HEALTH_DETAILS_ENABLED`
- `ARLEN_READINESS_REQUIRES_STARTUP`
- legacy compatibility fallback: `MOJOOBJC_*` equivalents

Default behavior:

- `tracePropagationEnabled = YES`
- `healthDetailsEnabled = YES`
- `readinessRequiresStartup = NO` (compatibility-first default)

## 3. Trace and Correlation Contract

Per request, Arlen now emits:

- `X-Request-Id`
- `X-Correlation-Id`
- `X-Trace-Id` (when trace propagation enabled)
- `traceparent` (when trace propagation enabled)

Trace context behavior:

- If inbound `traceparent` is valid, Arlen reuses its trace-id and generates a new span-id.
- If inbound `traceparent` is absent/invalid, Arlen uses valid `x-trace-id` (32 hex) when provided.
- Otherwise Arlen generates a new trace-id.

Request-complete logs and trace exporter payloads now include stable metadata fields:

- `event = "http.request.completed"` in request logs
- `trace_id`, `span_id`, `parent_span_id`, `traceparent`, `request_id`, `correlation_id`

## 4. Health and Readiness Signal Contract

Text probes remain backward-compatible:

- `GET /healthz` -> `200 ok\n`
- `GET /readyz` -> `200 ready\n` (default policy)
- `GET /livez` -> `200 live\n`

JSON probes are available when `Accept: application/json` (or `?format=json`) and `healthDetailsEnabled=YES`:

- `GET /healthz` JSON includes deterministic fields:
  - `signal`, `status`, `ok`, `timestamp_utc`, `uptime_seconds`, `checks`
- `GET /readyz` JSON includes deterministic fields:
  - `signal`, `status`, `ok`, `ready`, `timestamp_utc`, `uptime_seconds`, `checks`

Strict readiness option:

- When `observability.readinessRequiresStartup = YES` and app startup has not completed:
  - `GET /readyz` returns `503` with `not_ready` signal state.

## 5. Deployment Runbook Operability Validation

New script:

- `tools/deploy/validate_operability.sh`

Behavior:

- validates text contracts for `/healthz` and `/readyz`
- validates JSON signal payload shape for `/healthz` and `/readyz`
- validates `/metrics` includes `aln_http_requests_total`

Release smoke integration:

- `tools/deploy/smoke_release.sh` now runs `validate_operability.sh` before declaring release smoke success.

## 6. Executable Verification

Machine-readable contract fixture:

- `tests/fixtures/phase7c/observability_operability_contracts.json`

Runtime/config/deploy verification:

- `tests/unit/ConfigTests.m`
  - `testLoadConfigMergesAndAppliesDefaults`
  - `testEnvironmentOverridesRequestLimitsAndProxyFlags`
  - `testLegacyEnvironmentPrefixFallback`
- `tests/unit/ApplicationTests.m`
  - `testResponseIncludesTracePropagationHeadersAndCorrelationByDefault`
  - `testTracePropagationCanBeDisabledByConfig`
  - `testHealthzJSONPayloadIncludesDeterministicSignalChecks`
  - `testReadyzJSONCanRequireStartedStateAndReturnDeterministic503`
  - `testTraceExporterReceivesTraceContextMetadata`
- `tests/integration/HTTPIntegrationTests.m`
  - `testHealthEndpointSupportsJSONSignalPayload`
  - `testTraceparentAndCorrelationHeadersAreEmitted`
- `tests/integration/DeploymentIntegrationTests.m`
  - `testReleaseSmokeScriptValidatesDeployRunbook`
- `tests/unit/Phase7CTests.m`
  - `testObservabilityAndOperabilityContractFixtureSchemaAndTestCoverage`

## 7. Remaining 7C Follow-On

The broader 7C roadmap still includes:

- broader stable event-shape contracts across async job/runtime supervision paths
- stronger trace/span propagation across distributed runtime boundaries
- richer operational diagnostics artifact packs for release confidence review workflows
