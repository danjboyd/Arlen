# Arlen Phase 7 Roadmap

Status: Active (Phase 7A and 7B initial slices implemented; follow-on in progress)  
Last updated: 2026-02-23

Related docs:
- `docs/PHASE5_ROADMAP.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/PHASE7A_RUNTIME_HARDENING.md`
- `docs/PHASE7B_SECURITY_DEFAULTS.md`
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

Status: Planned

Deliverables:

- Structured logs with stable event shapes and correlation IDs across request/job/runtime paths.
- Trace/span propagation contracts for core runtime operations.
- SLO-oriented health/readiness signals and runbook validation scripts.
- Operational diagnostics pack for release/deploy confidence reviews.

Acceptance (required):

- Operators can trace representative request and background-job flows end-to-end.
- Health/readiness semantics are deterministic and test-covered.
- Observability payload schemas are documented and contract tested.

## 3.4 Phase 7D: Ecosystem Service Durability

Status: Planned

Deliverables:

- Stronger delivery semantics contracts (retry/idempotency/dead-letter behavior) for jobs.
- Cache consistency/expiry/failure behavior hardening for production adapters.
- Mail/attachment failure and retry policy contracts with deterministic outcomes.
- Additional integration suites for real adapter failure/recovery paths.

Acceptance (required):

- Service durability semantics are explicit and test-backed.
- Failure/retry behavior is deterministic and visible in diagnostics.
- Adapter conformance suites include production-style fault scenarios.

## 3.5 Phase 7E: EOC + Template Pipeline Maturity

Status: Planned

Deliverables:

- Template diagnostics/lint checks for higher-signal compile-time feedback.
- Expanded fixture matrix for multiline/nested/error-shape template scenarios.
- Additional include/render path hardening in integration suites.
- Documentation updates for template troubleshooting workflows.

Acceptance (required):

- Template failure diagnostics remain deterministic and actionable.
- Fixture coverage includes representative complex template patterns.
- End-to-end render-path regressions are captured in CI.

## 3.6 Phase 7F: Frontend Integration Starters

Status: Planned

Deliverables:

- Official frontend integration guides and starter project templates.
- Reference wiring for static assets, API consumption, and deployment packaging.
- CI validation for starter reproducibility and basic smoke checks.
- Versioning/upgrade guidance for starter maintenance.

Acceptance (required):

- New users can bootstrap supported frontend integration paths quickly.
- Starter flows are deterministic and tested.
- Frontend guidance stays aligned with Arlen release policy.

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

1. Wave 1: Phase 7A + Phase 7B
2. Wave 2: Phase 7C + Phase 7G + Phase 7E
3. Wave 3: Phase 7D + Phase 7F + Phase 7H

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
