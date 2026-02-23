# Arlen Phase 7 Roadmap

Status: Active (Phase 7A, 7B, 7C, 7D, 7E, and 7F initial slices implemented; follow-on in progress)  
Last updated: 2026-02-23

Related docs:
- `docs/PHASE5_ROADMAP.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/PHASE7A_RUNTIME_HARDENING.md`
- `docs/PHASE7B_SECURITY_DEFAULTS.md`
- `docs/PHASE7C_OBSERVABILITY_OPERABILITY.md`
- `docs/PHASE7D_SERVICE_DURABILITY.md`
- `docs/PHASE7E_TEMPLATE_PIPELINE_MATURITY.md`
- `docs/PHASE7F_FRONTEND_STARTERS.md`
- `docs/STATUS.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/PROPANE.md`
- `docs/EOC_V1_ROADMAP.md`

## 1. Objective

Mature non-SQL system components after Phase 5 so Arlen is a stronger default choice for:

- production runtime reliability
- secure-by-default services
- observable operations
- coding-agent-first workflows

Phase 7 intentionally keeps current scope guardrails:

- no full ORM default requirement
- raw SQL remains first-class and unchanged
- Objective-C/GNUstep-first APIs remain the default style

## 2. Scope Summary

1. Harden `boomhauer`/`propane` runtime behavior under sustained load and failure modes.
2. Strengthen security defaults, policy contracts, and misconfiguration diagnostics.
3. Expand observability and operability contracts for production usage.
4. Improve ecosystem service durability semantics (jobs/cache/mail/attachments).
5. Mature EOC/template pipeline diagnostics and fixture coverage.
6. Publish official frontend integration starters/guides.
7. Add coding-agent-first DX contracts and machine-readable workflows.
8. Deepen distributed runtime/cluster correctness contracts.

## 3. Components

## 3.1 Phase 7A: Runtime Hardening (`boomhauer` + `propane`)

Status: Initial slice implemented (2026-02-23); remaining 7A deliverables in progress

Deliverables:

- Backpressure and queue-boundary policy for request and worker paths.
- Stronger timeout contracts (read/write/header/body/idle) with deterministic diagnostics.
- Graceful deploy/reload and shutdown behavior hardening across worker replacement paths.
- Additional failure-mode regression coverage (crash loops, slow downstreams, overload).

Acceptance (required):

- Deterministic runtime behavior in overload and worker-failure scenarios.
- Contract tests cover restart/reload and graceful shutdown guarantees.
- No silent fallback for runtime safety-limit violations.

Implementation notes (initial slice, 2026-02-23):

- Added runtime websocket backpressure limit contract:
  - config key: `runtimeLimits.maxConcurrentWebSocketSessions` (default `256`)
  - environment override: `ARLEN_MAX_WEBSOCKET_SESSIONS` (legacy fallback supported)
- Added deterministic overload response contract for websocket session limit violations:
  - `503 Service Unavailable`
  - `Retry-After: 1`
  - `X-Arlen-Backpressure-Reason: websocket_session_limit`
- Added executable contract fixture and docs:
  - `tests/fixtures/phase7a/runtime_hardening_contracts.json`
  - `docs/PHASE7A_RUNTIME_HARDENING.md`
- Added regression coverage:
  - `tests/integration/HTTPIntegrationTests.m` (`testWebSocketSessionLimitReturns503UnderBackpressure`)
  - `tests/unit/ConfigTests.m` (default + env override coverage for runtime limit)
  - `tests/unit/Phase7ATests.m` (fixture schema/reference integrity)

## 3.2 Phase 7B: Security Defaults + Policy Contracts

Status: Initial slice implemented (2026-02-23); remaining 7B deliverables in progress

Deliverables:

- Security profile presets with clear default/on/off behavior (headers, CSRF/session, proxy trust).
- Expanded authn/authz contract tests for common misconfiguration paths.
- Secrets/config validation contracts with fail-fast diagnostics.
- Security runbook updates for deployment and incident response workflows.

Acceptance (required):

- Secure-by-default profile is documented and regression tested.
- Risky/misconfigured paths fail clearly and deterministically.
- Security policy behavior is visible in docs and CI contracts.

Implementation notes (initial slice, 2026-02-23):

- Added security profile presets with deterministic default behavior:
  - `balanced` (default), `strict`, `edge`
  - profile-controlled defaults for `trustedProxy`, `session.enabled`, `csrf.enabled`, and `securityHeaders.enabled`
  - environment override: `ARLEN_SECURITY_PROFILE` (legacy fallback supported)
- Added fail-fast startup diagnostics for security misconfiguration:
  - `session.enabled` without `session.secret`
  - `csrf.enabled` without `session.enabled`
  - `auth.enabled` without `auth.bearerSecret`
- Added middleware wiring hardening:
  - CSRF middleware now requires active session middleware registration
- Added executable contract fixture and docs:
  - `tests/fixtures/phase7b/security_policy_contracts.json`
  - `docs/PHASE7B_SECURITY_DEFAULTS.md`
- Added regression coverage:
  - `tests/unit/ConfigTests.m` (profile defaults and legacy/env behavior)
  - `tests/unit/ApplicationTests.m` (startup fail-fast diagnostics and strict-profile success path)
  - `tests/unit/Phase7BTests.m` (fixture schema/reference integrity)

## 3.3 Phase 7C: Observability + Operability Maturity

Status: Initial slice implemented (2026-02-23); remaining 7C deliverables in progress

Deliverables:

- Structured logs with stable event shapes and correlation IDs across request/job/runtime paths.
- Trace/span propagation contracts for core runtime operations.
- SLO-oriented health/readiness signals and runbook validation scripts.
- Operational diagnostics pack for release/deploy confidence reviews.

Acceptance (required):

- Operators can trace representative request and background-job flows end-to-end.
- Health/readiness semantics are deterministic and test-covered.
- Observability payload schemas are documented and contract tested.

Implementation notes (initial slice, 2026-02-23):

- Added deterministic observability config contract:
  - `observability.tracePropagationEnabled` (default `YES`)
  - `observability.healthDetailsEnabled` (default `YES`)
  - `observability.readinessRequiresStartup` (default `NO`)
  - env overrides with legacy fallback support
- Added trace propagation and correlation response-header contracts:
  - `X-Request-Id`
  - `X-Correlation-Id`
  - `X-Trace-Id` (when trace propagation is enabled)
  - `traceparent` (when trace propagation is enabled)
- Added trace metadata enrichment for request logs and `traceExporter` payloads:
  - stable event shape `http.request.completed` for request-complete logs
  - trace metadata fields (`trace_id`, `span_id`, `parent_span_id`, `traceparent`) in exporter payloads
- Added JSON health/readiness signal contracts with deterministic check payload shape:
  - `/healthz` and `/readyz` return JSON payloads when `Accept: application/json` (or `?format=json`)
  - strict readiness option (`readinessRequiresStartup`) returns deterministic `503 not_ready` when startup has not completed
- Added deployment runbook operability validation script + smoke integration:
  - `tools/deploy/validate_operability.sh`
  - `tools/deploy/smoke_release.sh` now validates operability probes before passing
- Added executable contract fixture and docs:
  - `tests/fixtures/phase7c/observability_operability_contracts.json`
  - `docs/PHASE7C_OBSERVABILITY_OPERABILITY.md`
- Added regression coverage:
  - `tests/unit/ConfigTests.m` (observability default + env/legacy override behavior)
  - `tests/unit/ApplicationTests.m` (trace propagation, health/readiness JSON payload, strict readiness, trace exporter metadata)
  - `tests/integration/HTTPIntegrationTests.m` (health JSON signal + trace/correlation response headers)
  - `tests/integration/DeploymentIntegrationTests.m` (release smoke runbook operability validation path)
  - `tests/unit/Phase7CTests.m` (fixture schema/reference integrity)

## 3.4 Phase 7D: Ecosystem Service Durability

Status: Initial slice implemented (2026-02-23); remaining 7D deliverables in progress

Deliverables:

- Stronger delivery semantics contracts (retry/idempotency/dead-letter behavior) for jobs.
- Cache consistency/expiry/failure behavior hardening for production adapters.
- Mail/attachment failure and retry policy contracts with deterministic outcomes.
- Additional integration suites for real adapter failure/recovery paths.

Acceptance (required):

- Service durability semantics are explicit and test-backed.
- Failure/retry behavior is deterministic and visible in diagnostics.
- Adapter conformance suites include production-style fault scenarios.

Implementation notes (initial slice, 2026-02-23):

- Added deterministic jobs idempotency-key contract (`enqueue` option: `idempotencyKey`):
  - duplicate enqueues with active pending/leased jobs return the same `jobID`
  - key mapping is released on acknowledgement so replay requests can enqueue new work
  - implemented for `ALNInMemoryJobAdapter` and `ALNFileJobAdapter` (persisted mapping state for file adapter)
- Expanded cache durability conformance semantics:
  - zero TTL (`ttlSeconds = 0`) is validated as non-expiring storage
  - `setObject:nil` is validated as deterministic key removal
- Added retry-policy wrappers with deterministic error contracts:
  - `ALNRetryingMailAdapter` (`maxAttempts`, `retryDelaySeconds`; exhaustion error code `4311`)
  - `ALNRetryingAttachmentAdapter` (`maxAttempts`, `retryDelaySeconds`; exhaustion error code `564`)
- Added executable contract fixture and docs:
  - `tests/fixtures/phase7d/service_durability_contracts.json`
  - `docs/PHASE7D_SERVICE_DURABILITY.md`
- Added regression coverage:
  - `tests/unit/Phase7DTests.m` (jobs idempotency, retry wrapper behavior, fixture schema/reference integrity)
  - `tests/unit/Phase3ETests.m` conformance execution path coverage for updated jobs/cache contracts

## 3.5 Phase 7E: EOC + Template Pipeline Maturity

Status: Initial slice implemented (2026-02-23); remaining 7E deliverables in progress

Deliverables:

- Template diagnostics/lint checks for higher-signal compile-time feedback.
- Expanded fixture matrix for multiline/nested/error-shape template scenarios.
- Additional include/render path hardening in integration suites.
- Documentation updates for template troubleshooting workflows.

Acceptance (required):

- Template failure diagnostics remain deterministic and actionable.
- Fixture coverage includes representative complex template patterns.
- End-to-end render-path regressions are captured in CI.

Implementation notes (initial slice, 2026-02-23):

- Added deterministic template lint diagnostics in `ALNEOCTranspiler`:
  - `lintDiagnosticsForTemplateString:logicalPath:error:`
  - rule: `unguarded_include` (warn when `ALNEOCInclude(...)` return value is not checked)
- `eocc` now emits compile-time lint warnings with stable shape:
  - `path`, `line`, `column`, `code`, `message`
- Expanded template fixture matrix:
  - multiline, malformed multiline expression/sigil, nested control-flow, guarded/unguarded include patterns
- Hardened default include/render path contract:
  - root template include now guards failure and returns `nil` deterministically
- Added executable contract fixture and docs:
  - `tests/fixtures/phase7e/template_pipeline_contracts.json`
  - `docs/PHASE7E_TEMPLATE_PIPELINE_MATURITY.md`
  - `docs/TEMPLATE_TROUBLESHOOTING.md`
- Added regression coverage:
  - `tests/unit/TranspilerTests.m` (fixture matrix + lint diagnostics)
  - `tests/integration/HTTPIntegrationTests.m` (root render includes partial contract)
  - `tests/integration/DeploymentIntegrationTests.m` (`eocc` lint output contract)
  - `tests/unit/Phase7ETests.m` (fixture schema/reference integrity)

## 3.6 Phase 7F: Frontend Integration Starters

Status: Initial slice implemented (2026-02-23); remaining 7F deliverables in progress

Deliverables:

- Official frontend integration guides and starter project templates.
- Reference wiring for static assets, API consumption, and deployment packaging.
- CI validation for starter reproducibility and basic smoke checks.
- Versioning/upgrade guidance for starter maintenance.

Acceptance (required):

- New users can bootstrap supported frontend integration paths quickly.
- Starter flows are deterministic and tested.
- Frontend guidance stays aligned with Arlen release policy.

Implementation notes (initial slice, 2026-02-23):

- Added frontend starter generation path in CLI:
  - `arlen generate frontend <Name> --preset <vanilla-spa|progressive-mpa>`
  - deterministic generated layout under `public/frontend/<slug>/...`
  - default preset when omitted: `vanilla-spa`
- Starter templates include static assets plus API consumption examples:
  - built-in JSON signal endpoint usage (`/healthz?format=json`)
  - metrics endpoint preview (`/metrics`)
- Added deterministic starter version manifest contract:
  - generated `starter_manifest.json` with version `phase7f-starter-v1`
- Added release-packaging alignment:
  - starter assets are generated under `public/`, matching deploy packaging contract
- Added executable contract fixture and docs:
  - `tests/fixtures/phase7f/frontend_starter_contracts.json`
  - `docs/PHASE7F_FRONTEND_STARTERS.md`
- Added regression coverage:
  - `tests/integration/DeploymentIntegrationTests.m` (starter reproducibility + release packaging)
  - `tests/unit/Phase7FTests.m` (fixture schema/reference integrity)

## 3.7 Phase 7G: Coding-Agent-First DX Contracts

Status: Planned

Deliverables:

- Machine-readable CLI output contracts for scaffold/build/check/deploy workflows.
- Deterministic scaffold generation with stable file/layout conventions.
- "Fix-it" style diagnostics that map errors to concrete repair actions.
- Agent regression harness scenarios for common coding-agent tasks.

Acceptance (required):

- Key workflows are reliable for Codex/Claude-style iterative execution.
- CLI outputs are stable and parseable for automation.
- Agent-targeted workflows are documented and regression tested.

## 3.8 Phase 7H: Distributed Runtime Depth

Status: Planned

Deliverables:

- Expanded multi-node correctness contracts beyond baseline cluster primitives.
- Failure-mode tests for partial outages, node churn, and coordination edge cases.
- Clear consistency/coordination capability matrix for clustered runtime behavior.
- Updated operational guidance for distributed deployment troubleshooting.

Acceptance (required):

- Cluster behavior under failure is deterministic and contract tested.
- Capability boundaries are explicit and documented.
- Operational diagnostics support rapid incident triage.

## 4. Suggested Execution Sequence

Recommended sequencing for adoption impact and risk reduction:

1. Wave 1: Phase 7A + Phase 7B (initial slices complete)
2. Wave 2: Phase 7C + Phase 7D + Phase 7E (initial slices complete)
3. Wave 3: Phase 7G + Phase 7H

## 5. Testing and Quality Strategy

Phase 7 follows contract-first quality gates:

- Unit contracts for deterministic behavior and diagnostics.
- Integration contracts for runtime, services, and adapter execution paths.
- Fault-injection and soak suites for long-run stability signals.
- Release confidence artifacts tied to milestone acceptance criteria.

External framework regression suites may inform scenario selection, but Arlen contracts remain the source of truth.

## 6. Scope Guardrails

- Keep full ORM as optional/"Maybe Someday"; not a Phase 7 default.
- Keep admin/backoffice and account-product surfaces outside Arlen core scope.
- Keep raw SQL, EOC compile-time determinism, and GNUstep compatibility as non-negotiable baselines.
