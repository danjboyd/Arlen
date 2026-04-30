# Arlen Phase 39 Roadmap

Status: Planned
Last updated: 2026-04-30

Related docs:

- `docs/PROPANE.md`
- `docs/DEPLOYMENT.md`
- `docs/CLI_REFERENCE.md`
- `docs/CONFIGURATION_REFERENCE.md`
- `docs/ECOSYSTEM_SERVICES.md`
- `docs/ARLEN_ORM.md`

## 1. Objective

Make Arlen's multi-worker production state contract explicit and enforceable
enough that apps do not accidentally depend on process-local memory for durable
production data.

`propane` correctly runs multiple worker processes for production workloads.
Each worker has isolated process memory. That means process-local dictionaries,
arrays, singleton service instances, and in-memory adapter instances diverge
across workers. A user, role, scenario, workflow record, or other domain object
created in one worker may be missing from another worker unless it is backed by
shared durable storage.

Phase 39 is a product-safety phase, not a change to the multi-worker model. The
goal is to document the contract, add deploy-time warnings, label demo-only
in-memory patterns, and provide durable state examples that make production-safe
design the easy path.

## 2. Current Assessment

The feature request from `TaxCalculator` is accepted as a valid product gap.
It is not classified as a runtime bug: isolated worker memory is expected in a
prefork production manager. The problem is that Arlen defaults production
configuration toward multiple workers while the documentation and deploy
guardrails are not prominent enough about the state implications.

Current facts:

1. `ALNConfig` defaults `propaneAccessories.workerCount` to `4`.
2. `propane` enables production multi-worker operation through worker
   processes, not shared-memory threads.
3. Arlen already has database deployment contracts for deploy targets.
4. Arlen's session middleware stores signed cookie-backed session state by
   default, but app-owned user/domain lookups still need durable shared storage.
5. First-party in-memory adapters are useful for demos, tests, local
   development, and cache-like data, but they are not a durable production data
   model for multi-worker apps.

## 3. Scope Summary

1. Phase 39A: multi-worker state contract documentation.
2. Phase 39B: durable state configuration contract.
3. Phase 39C: `arlen doctor` and `deploy doctor` warning checks.
4. Phase 39D: deploy dry-run, push, and release warnings.
5. Phase 39E: demo-only in-memory store labeling.
6. Phase 39F: durable store examples and app patterns.
7. Phase 39G: optional worker identity diagnostics.
8. Phase 39H: confidence coverage and docs closeout.

## 4. Milestones

## 4.1 Phase 39A: Multi-Worker State Contract Documentation

Status: Planned

Deliverables:

- Add a prominent state-safety section to `docs/PROPANE.md`.
- Add deployment guidance to `docs/DEPLOYMENT.md` near the database dependency
  contract.
- Update `docs/CORE_CONCEPTS.md` or `docs/APP_AUTHORING_GUIDE.md` with app
  authoring guidance for request-spanning state.
- Document unsafe patterns:
  - `NSMutableDictionary *usersByEmail`
  - app-owned singleton user stores
  - in-memory scenario/workflow stores
  - in-memory role/permission maps that are mutated at runtime
- Document safe patterns:
  - signed cookie session plus database-backed user lookup
  - SQLite or file-backed state for single-host pilot deployments
  - PostgreSQL for multi-worker and multi-host production
  - durable first-party adapters where available

Acceptance:

- A new app author can find the production state rule from the propane,
  deployment, and app-authoring docs.
- The docs explicitly state that sticky sessions are not the default correctness
  model for normal HTTP apps.
- The docs distinguish demo/test/cache state from durable production state.

## 4.2 Phase 39B: Durable State Configuration Contract

Status: Planned

Deliverables:

- Define the configuration/deploy metadata that lets Arlen tell whether an app
  has declared a durable state strategy.
- Prefer an explicit contract over inference-only checks. Candidate shape:

  ```plist
  state = {
    durable = YES;
    mode = "database";
    target = "default";
  };
  ```

- Decide how the new contract relates to existing `database` deployment
  metadata:
  - database contract present may satisfy the first warning version
  - explicit state contract should become the authoritative long-term signal
- Document compatibility behavior for existing apps with only `database`
  config.

Acceptance:

- Arlen has a stable config key or deploy metadata field for app-level durable
  state intent.
- Existing deploy database contracts remain compatible.
- The contract does not claim Arlen can prove every app-owned store is durable;
  it records operator/developer intent and drives diagnostics.

## 4.3 Phase 39C: Doctor Warning Checks

Status: Planned

Deliverables:

- Add a `multi_worker_state` check to `arlen doctor --env production`.
- Add a `multi_worker_state` check to `arlen deploy doctor`.
- Trigger a warning when:
  - environment is `production`
  - `propaneAccessories.workerCount > 1`
  - no durable state contract or acceptable database-backed state signal is
    configured
- Keep the first release as `warn`, not `fail`, so existing apps get actionable
  guidance without blocking emergency deploys.
- Emit structured JSON in doctor output:
  - `id = "multi_worker_state"`
  - `status = "warn"`
  - message naming the worker count and missing durable state signal
  - hint explaining process-local state isolation

Acceptance:

- Doctor warns before production multi-worker apps ship with no declared
  durable state strategy.
- JSON output is deterministic and regression-tested.
- Single-worker development and test configs do not produce noisy warnings.

## 4.4 Phase 39D: Deploy Dry-Run, Push, and Release Warnings

Status: Planned

Deliverables:

- Surface the same warning during:
  - `arlen deploy dryrun`
  - `arlen deploy push`
  - `arlen deploy release`
- Include warning data in JSON payloads without changing successful exit codes
  for the initial implementation.
- Ensure remote target flows preserve the warning in local and delegated output.
- Document the warning in `docs/CLI_REFERENCE.md`.

Acceptance:

- Production deploy planning surfaces the issue before activation.
- Warning payloads are visible to humans and automation.
- Existing successful deploy flows remain successful unless a later phase
  deliberately promotes the policy to fail-closed.

## 4.5 Phase 39E: Demo-Only In-Memory Store Labeling

Status: Planned

Deliverables:

- Audit examples and first-party sample stores for in-memory mutable state.
- Rename or clearly label demo stores with `DemoInMemory...` where API churn is
  acceptable.
- Add source comments and docs callouts:

  ```objc
  // Demo-only: not safe as durable state for multi-worker production.
  ```

- Add runtime warnings only for demo/example code paths where the signal is
  precise and not noisy.

Acceptance:

- Examples do not teach unqualified singleton dictionaries as production
  storage.
- In-memory adapters remain available for tests, local development, and caches.
- Public API changes are avoided unless the type is clearly example-owned.

## 4.6 Phase 39F: Durable Store Examples and App Patterns

Status: Planned

Deliverables:

- Add canonical examples for:
  - signed-cookie session plus durable user lookup
  - SQLite single-host pilot state
  - PostgreSQL multi-worker production state
  - file-backed development or pilot storage where appropriate
  - first-party adapter replacement for jobs/cache/attachments where relevant
- Prefer small, executable examples over broad prose.
- Show migration path from an in-memory demo store to a durable store.
- Clarify that cookie session claims are not a substitute for durable app-owned
  domain state when users, roles, or business records can change.

Acceptance:

- App authors have a concrete safe pattern for login/session plus user lookup.
- The examples support Linux/GNUstep and do not require unavailable services by
  default.
- PostgreSQL-backed examples integrate with existing database config and
  migration guidance.

## 4.7 Phase 39G: Optional Worker Identity Diagnostics

Status: Planned

Deliverables:

- Add opt-in request diagnostics for worker identity:
  - worker PID
  - optional worker index if available from `propane`
  - request ID
  - route/path
- Keep diagnostics disabled by default.
- Use logs and/or diagnostic headers only behind explicit config/env flags.
- Document this as an incident triage tool, not as an application correctness
  mechanism.

Acceptance:

- Operators can confirm worker-specific behavior during a debugging window.
- Default production logs remain quiet.
- The feature does not encourage sticky-session correctness as the default app
  design.

## 4.8 Phase 39H: Confidence Coverage and Docs Closeout

Status: Planned

Deliverables:

- Add unit coverage for config/state-contract interpretation.
- Add CLI tests for doctor warning behavior.
- Add deployment integration coverage for dry-run JSON warnings.
- Add docs-quality updates:
  - `docs/README.md`
  - `docs/CLI_REFERENCE.md`
  - `docs/DEPLOYMENT.md`
  - `docs/PROPANE.md`
  - `docs/CONFIGURATION_REFERENCE.md`
- Add a focused confidence command only if the implementation touches enough
  surfaces to justify it.

Acceptance:

- `make test-unit-filter` coverage exists for warning decisions.
- Deploy JSON warning contracts have regression coverage.
- `tools/ci/run_docs_quality.sh` passes.
- Phase 39 docs describe the delivered state and any deferred work.

## 5. Explicit Non-Goals

- Do not make sticky sessions the default fix for normal HTTP correctness.
- Do not introduce shared-memory worker state.
- Do not make `propane` serialize all requests to hide process-local state bugs.
- Do not require Redis or PostgreSQL for every Arlen app.
- Do not claim Arlen can statically prove every app-owned store is durable.
- Do not break demo/test/local workflows that intentionally use in-memory
  adapters.

## 6. Policy Notes

Initial guardrails should warn rather than fail. A later release may promote
the policy to fail-closed only when:

1. Arlen has an explicit durable state contract.
2. Existing apps have a documented migration path.
3. Deploy tooling can distinguish development, single-worker pilot, and
   production multi-worker risk with low false-positive rates.

The durable state rule is:

Process-local mutable state is acceptable for demos, tests, caches, and
single-worker development. Any state that must survive worker changes, worker
restarts, rolling reloads, deploys, or multiple hosts must live in shared
durable storage.
