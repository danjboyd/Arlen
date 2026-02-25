# Arlen Phase 9 Roadmap

Status: Complete (Phase 9A complete; Phase 9B complete; Phase 9C complete; Phase 9D complete; Phase 9E complete; Phase 9F complete; Phase 9G complete; Phase 9H complete; Phase 9I complete; Phase 9J complete)  
Last updated: 2026-02-25

Related docs:
- `docs/PHASE8_ROADMAP.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/PHASE5E_HARDENING_CONFIDENCE.md`
- `docs/RUNTIME_CONCURRENCY_GATE.md`
- `docs/CONCURRENCY_AUDIT_2026-02-25.md`
- `docs/PHASE9I_FAULT_INJECTION.md`
- `docs/PHASE9J_RELEASE_CERTIFICATION.md`
- `docs/KNOWN_RISK_REGISTER.md`
- `docs/DOCUMENTATION_POLICY.md`
- `docs/API_REFERENCE.md`

## 1. Objective

Deliver a world-class documentation system for Arlen and extend that effort into enterprise reliability hardening that proves existing features are production-grade under stress.

Phase 9 has two tracks:

- documentation maturity (9A-9E)
- inline reliability hardening inside Arlen (9F-9J)

The reliability track is explicitly non-feature-expansion work:

- preserve core Arlen runtime behavior
- add guardrails, stress coverage, and deterministic diagnostics
- gate releases on reproducible confidence artifacts

## 2. Scope Summary

1. Phase 9A: docs platform and HTML publishing pipeline.
2. Phase 9B: API reference generation with per-method purpose/usage guidance.
3. Phase 9C: multi-track getting-started guides for common onboarding paths.
4. Phase 9D: "Arlen for X" migration guides for common incoming ecosystems.
5. Phase 9E: docs quality gates, coverage rules, and maintenance contracts.
6. Phase 9F: inline concurrency and backpressure hardening gates.
7. Phase 9G: worker lifecycle, signal, and startup/shutdown stress contracts.
8. Phase 9H: sanitizer and race-detection maturity for runtime-critical paths.
9. Phase 9I: deterministic fault-injection library for high-risk runtime seams.
10. Phase 9J: release confidence certification pack for enterprise readiness.

## 3. Milestones

## 3.1 Phase 9A: Docs Platform + HTML Publishing

Status: Complete (2026-02-24)

Deliverables:

- Expand docs HTML generation to include nested docs directories.
- Generate API reference docs as part of the docs build pipeline.
- Provide local docs serving entrypoint (`make docs-serve`).
- Keep output deterministic under `build/docs/`.

Acceptance (required):

- `make docs-html` regenerates complete docs portal and API reference HTML.
- `build/docs/index.html` resolves to docs index and cross-links correctly.
- `make docs-serve` serves docs locally from repository checkout.

## 3.2 Phase 9B: API Reference Completeness

Status: Complete (2026-02-24)

Deliverables:

- Generate API reference from public umbrella exports:
  - `src/Arlen/Arlen.h`
  - `src/ArlenData/ArlenData.h`
- Emit symbol pages under `docs/api/`.
- Document every public method with:
  - selector/signature
  - purpose
  - usage guidance
- Include symbol-level summaries and practical usage snippets for high-value APIs.

Acceptance (required):

- API index (`docs/API_REFERENCE.md`) enumerates exported symbols/method totals.
- Each exported symbol has a generated page in `docs/api/`.
- Generated docs are reproducible via `python3 tools/docs/generate_api_reference.py`.

## 3.3 Phase 9C: Getting-Started Track Suite

Status: Complete (2026-02-24)

Deliverables:

- Add track-specific onboarding guides:
  - quickstart path
  - API-first path
  - HTML-first path
  - data-layer-first path
- Cross-link track suite from primary docs index and root README.

Acceptance (required):

- New user can choose a path and reach a running app without ambiguity.
- Track docs include concrete commands and expected outcomes.

## 3.4 Phase 9D: Arlen-for-X Migration Suite

Status: Complete (2026-02-24)

Deliverables:

- Add migration guides for:
  - Rails
  - Django
  - Laravel
  - FastAPI
  - Express/NestJS
  - Mojolicious
- Include concept mapping, request lifecycle translation, and incremental cutover plans.

Acceptance (required):

- Each guide includes at least:
  - mental-model mapping table
  - app structure mapping
  - request/response/auth/data migration notes
  - phased migration checklist

## 3.5 Phase 9E: Documentation Quality Gates

Status: Complete (2026-02-25)

Deliverables:

- Update documentation policy with API-reference maintenance requirements.
- Define docs quality checks for generated API docs + HTML build validity.
- Wire docs process expectations into roadmap/index documentation.

Acceptance (required):

- `docs/DOCUMENTATION_POLICY.md` includes API docs and HTML quality checks.
- Docs contributors have explicit regeneration commands and review checklist updates.

Implementation notes (completed):

- Added CI docs quality gate entrypoint:
  - `tools/ci/run_docs_quality.sh`
- Added Makefile docs gate target:
  - `make ci-docs`
- Added dedicated GitHub Actions docs-quality workflow:
  - `.github/workflows/docs-quality.yml`
- Expanded documentation policy with explicit docs quality checklist and automated-gate source-of-truth command.
- Updated contributor PR template to include docs quality validation when docs/public API surfaces change.

## 3.6 Phase 9F: Inline Concurrency + Backpressure Hardening

Status: Complete (2026-02-25)

Deliverables:

- Define and enforce bounded concurrency contracts for HTTP workers, queue depth, realtime subscribers, and websocket admission.
- Expand deterministic overload diagnostics (`503` + stable machine-readable reason headers/body fields).
- Add mixed-traffic churn integration scenarios (HTTP routes + websocket channels + SSE + startup/shutdown overlap).
- Promote runtime concurrency probe and gate to release-blocking quality checks.

Acceptance (required):

- Regression tests prove no worker crash/regression under bounded stress in both serialized and concurrent dispatch modes.
- Backpressure rejection paths are deterministic, observable, and test-covered.
- `tools/ci/run_runtime_concurrency_gate.sh` passes in CI and locally.

Implementation notes (completed):

- Added bounded worker-pool and queue backpressure integration coverage with stable `X-Arlen-Backpressure-Reason` diagnostics.
- Added deterministic websocket channel-subscriber admission rejections for realtime per-channel/global caps.
- Expanded mixed lifecycle stress coverage to include websocket echo, websocket channel fanout, SSE stream checks, and HTTP churn in both dispatch modes.
- Expanded runtime concurrency probe to include startup/shutdown overlap under active mixed traffic and post-restart recovery checks.
- Wired runtime concurrency gate into release-quality CI path (`tools/ci/run_phase5e_quality.sh` + workflow).

## 3.7 Phase 9G: Worker Lifecycle + Signal Durability

Status: Complete (2026-02-25)

Deliverables:

- Add deterministic tests for repeated boot/stop/restart loops with active traffic.
- Validate graceful shutdown semantics under queued, in-flight, and keep-alive connections.
- Add signal-handling stress tests for mixed SIGTERM/SIGINT scenarios through propane worker supervision.
- Add diagnostics contracts for worker churn, restart cause, and stop reasons.

Acceptance (required):

- No crashes, deadlocks, or leaked worker processes across lifecycle stress loops.
- Startup/shutdown regressions are captured in integration tests and CI gates.
- Runtime emits stable lifecycle diagnostics for triage and automation.

Implementation notes (completed):

- Added deterministic propane lifecycle diagnostics contract:
  - machine-readable `propane:lifecycle` events on stdout
  - optional mirrored diagnostics file via `ARLEN_PROPANE_LIFECYCLE_LOG`
  - stable churn/restart/stop fields (`reason`, `status`, `exit_reason`, `restart_action`)
- Added propane lifecycle/signal integration regressions:
  - repeated restart loops with active concurrent HTTP traffic
  - graceful shutdown drain validation for in-flight + queued + keep-alive requests
  - mixed signal supervision path (`SIGHUP` reload + `SIGTERM` shutdown) with lifecycle diagnostics assertions
- Updated operator-facing propane docs/CLI references with lifecycle diagnostics contract details.

## 3.8 Phase 9H: Sanitizer + Race Detection Maturity

Status: Complete (2026-02-25)

Deliverables:

- Expand sanitizer matrix and route coverage for runtime-critical flows (routing, render, realtime, data-layer, lifecycle).
- Keep TSAN lane active as experimental non-blocking until false-positive budget is understood, then promote to required gate.
- Add suppression policy docs with strict expiration tracking for temporary suppressions.
- Record sanitizer deltas and ownership in confidence artifacts.

Completed scope:

- Added Phase 9H sanitizer lane fixture matrix + suppression registry fixtures:
  - `tests/fixtures/sanitizers/phase9h_sanitizer_matrix.json`
  - `tests/fixtures/sanitizers/phase9h_suppressions.json`
- Added suppression registry validator:
  - `tools/ci/check_sanitizer_suppressions.py`
- Added sanitizer confidence artifact generator:
  - `tools/ci/generate_phase9h_sanitizer_confidence_artifacts.py`
  - outputs under `build/release_confidence/phase9h/`
- Upgraded sanitizer gate orchestration:
  - `tools/ci/run_phase5e_sanitizers.sh`
  - validates suppression registry, tracks blocking/TSAN lane status, and emits confidence artifacts
- Upgraded TSAN experimental lane artifact retention:
  - `tools/ci/run_phase5e_tsan_experimental.sh`
  - retained artifacts: `build/sanitizers/tsan/tsan.log`, `build/sanitizers/tsan/summary.json`
- Expanded runtime sanitizer probe route/data-layer coverage:
  - `tools/ci/runtime_concurrency_probe.py`
- Added CI artifact upload contracts:
  - `.github/workflows/phase4-sanitizers.yml`
- Added suppression lifecycle policy documentation:
  - `docs/SANITIZER_SUPPRESSION_POLICY.md`

Acceptance (required):

- Blocking sanitizer lanes are green for release candidates.
- TSAN lane has deterministic execution recipe and artifact retention for failures.
- New runtime concurrency code paths require sanitizer coverage updates.

## 3.9 Phase 9I: Fault Injection Library for Runtime Seams

Status: Complete (2026-02-25)

Deliverables:

- Build reusable fault-injection helpers for socket churn, delayed writes, abrupt disconnects, partial request frames, and malformed upgrade handshakes.
- Add deterministic fault scripts for high-risk seams:
  - HTTP parser/dispatcher boundaries
  - websocket handshake and channel lifecycle
  - runtime stop/start boundaries
- Add replayable seed support for non-deterministic failure patterns.

Completed scope:

- Added deterministic Phase 9I fault-injection harness:
  - `tools/ci/runtime_fault_injection.py`
- Added explicit CI/local entrypoint:
  - `tools/ci/run_phase9i_fault_injection.sh`
  - `make ci-fault-injection`
- Added seam/scenario matrix fixture:
  - `tests/fixtures/fault_injection/phase9i_fault_scenarios.json`
- Added confidence artifacts for triage:
  - `build/release_confidence/phase9i/fault_injection_results.json`
  - `build/release_confidence/phase9i/phase9i_fault_injection_summary.md`
  - `build/release_confidence/phase9i/manifest.json`
- Added seed replay controls:
  - `ARLEN_PHASE9I_SEED`
  - `ARLEN_PHASE9I_ITERS`
  - `ARLEN_PHASE9I_MODES`
  - `ARLEN_PHASE9I_SCENARIOS`
- Added regression coverage for the new tooling and artifacts:
  - `tests/integration/DeploymentIntegrationTests.m`
- Added operator/developer documentation:
  - `docs/PHASE9I_FAULT_INJECTION.md`

Acceptance (required):

- Fault-injection scenarios are executable via one documented command path.
- High-risk runtime seams have mapped regression coverage and artifacts.
- Failure signatures are normalized into deterministic diagnostics for triage.

## 3.10 Phase 9J: Enterprise Release Certification Pack

Status: Complete (2026-02-25)

Deliverables:

- Produce release confidence bundle for each release candidate:
  - inline hardening gate summaries
  - sanitizer/race-detection reports
  - stress/fault scenario pass matrices
  - known-risk register with owner and target date
- Publish minimum certification thresholds and fail criteria.
- Add release checklist enforcement in CI/release scripts.

Completed scope:

- Added threshold-driven certification pack generator:
  - `tools/ci/generate_phase9j_release_certification_pack.py`
- Added release-certification gate entrypoint:
  - `tools/ci/run_phase9j_release_certification.sh`
  - `make ci-release-certification`
- Added Phase 9J threshold and known-risk fixtures:
  - `tests/fixtures/release/phase9j_certification_thresholds.json`
  - `tests/fixtures/release/phase9j_known_risks.json`
- Added release confidence certification artifact bundle:
  - `build/release_confidence/phase9j/manifest.json`
  - `build/release_confidence/phase9j/certification_summary.json`
  - `build/release_confidence/phase9j/release_gate_matrix.json`
  - `build/release_confidence/phase9j/known_risk_register_snapshot.json`
  - `build/release_confidence/phase9j/phase9j_release_certification.md`
- Enforced certification requirements in release packaging script:
  - `tools/deploy/build_release.sh`
  - default requirement: valid `phase9j` manifest with `status=certified`
  - explicit non-RC override: `--allow-missing-certification`
- Added documentation and release-notes linkage for known-risk register:
  - `docs/PHASE9J_RELEASE_CERTIFICATION.md`
  - `docs/KNOWN_RISK_REGISTER.md`
  - `docs/RELEASE_NOTES.md`
- Added integration regression coverage for certification tooling/enforcement:
  - `tests/integration/DeploymentIntegrationTests.m`

Acceptance (required):

- Release candidate without certification pack is considered incomplete.
- Certification artifacts are reproducible from repository commands.
- Known-risk register is current and linked from release notes.

## 4. Rollout and Maintenance

- Keep documentation and reliability tracks coupled: contract changes must update docs and tests together.
- Keep runtime hardening additive and default-first; do not require feature removals to achieve stability.
- Require deterministic failure diagnostics for every new guardrail or stress-path assertion.
- Promote gates incrementally: start non-blocking where needed, then graduate to release-blocking once stable.

## 5. Explicitly Deferred (Future Consideration, Not Phase 9 Scope)

1. New end-user framework features unrelated to reliability hardening.
2. Multi-version hosted docs release automation.
3. Cross-language runtime rewrite or non-Objective-C runtime forks.
