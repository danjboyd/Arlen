# Arlen Documentation

This is the main documentation index for Arlen.

Generate browser-friendly docs:

```bash
make docs-api
make docs-html
make ci-docs
make docs-serve
```

Open `build/docs/index.html` in your browser, or use `make docs-serve` for local hosting.

Audit browser-facing error surfaces:

```bash
make browser-error-audit
```

Then open `build/browser-error-audit/index.html`.

## Start Here

- [Current Status](STATUS.md): latest checkpoint and verified milestone state.
- [First App Guide](FIRST_APP_GUIDE.md): fastest path to scaffold, run, and extend your first app with the composition-first EOC layout/partial defaults.
- [Getting Started](GETTING_STARTED.md): prerequisites, framework build, tests, and workflow overview, including the default `layout` / `yield` / `render` scaffold path.
- [Getting Started Tracks](GETTING_STARTED_TRACKS.md): quickstart, API-first, HTML-first, and data-layer onboarding paths.
- [API Reference](API_REFERENCE.md): generated public API docs with per-method purpose and usage guidance.
- [Arlen for X Migration Guides](ARLEN_FOR_X_INDEX.md): framework-by-framework migration playbooks.
- [Toolchain Matrix](TOOLCHAIN_MATRIX.md): known-good onboarding/runtime toolchain baseline.
- [CLI Reference](CLI_REFERENCE.md): command reference for `arlen`, `boomhauer`, and helper scripts.
- [Core Concepts](CORE_CONCEPTS.md): runtime architecture and request lifecycle.
- [Modules](MODULES.md): first-class module architecture, install flow, and override model.
- [Auth Module](AUTH_MODULE.md): first-party auth product routes, embeddable fragment contract, runtime helpers, `/auth/api` surface, and optional disabled-by-default SMS/Twilio Verify MFA.
- [Auth UI Integration Modes](AUTH_UI_INTEGRATION_MODES.md): `headless`, `module-ui`, and `generated-app-ui` contract plus the Phase 18 fragment-first MFA/UI refinements.
- [Admin UI Module](ADMIN_UI_MODULE.md): first-party admin resource contract with bulk actions, exports, typed filters, autocomplete, and `/admin/api` surface.
- [Jobs Module](JOBS_MODULE.md): first-party jobs runtime contracts plus protected `/jobs` HTML and `/jobs/api` JSON surfaces.
- [Notifications Module](NOTIFICATIONS_MODULE.md): first-party notifications product flows on jobs + mail with inbox/preferences, preview/test-send, and `/notifications/api` surfaces.
- [Storage Module](STORAGE_MODULE.md): first-party storage collections, direct uploads, signed downloads, variants, and `/storage/api` management surfaces.
- [Ops Module](OPS_MODULE.md): protected operational dashboard with history, drilldowns, app/module cards/widgets, and `/ops/api` JSON/OpenAPI surfaces.
- [Search Module](SEARCH_MODULE.md): durable searchable-resource contracts, job-backed reindex + incremental-sync flows, and shared admin/ops integration.
- [Deployment Guide](DEPLOYMENT.md): deployment model and production guidance.
- [Systemd Runbook](SYSTEMD_RUNBOOK.md): reference `systemd` unit template, debug drop-in workflow, and incident collection steps.
- [Password Hashing](PASSWORD_HASHING.md): Argon2id password hashing API, defaults, and rehash workflow.
- [Realtime and Composition](REALTIME_COMPOSITION.md): websocket/SSE contracts, pubsub hub, and app mounting.
- [Ecosystem Services](ECOSYSTEM_SERVICES.md): jobs/cache/i18n/mail/attachment adapter contracts and plugin wiring.
- [ArlenData Reuse Guide](ARLEN_DATA.md): standalone data-layer packaging, PostgreSQL/MSSQL dialect usage, typed PostgreSQL result materialization, and result-helper guidance.
- [SQL Builder Conformance Matrix](SQL_BUILDER_CONFORMANCE_MATRIX.md): phase-4 SQL snapshot matrix and regression gate map.
- [Phase 5A Reliability Contracts](PHASE5A_RELIABILITY_CONTRACTS.md): contract map, external regression intake workflow, and adapter capability metadata baselines.
- [Phase 5B Runtime Routing](PHASE5B_RUNTIME_ROUTING.md): multi-database read/write routing, scoped stickiness, and diagnostics contracts.
- [Phase 5C Multi-Database Tooling](PHASE5C_MULTI_DATABASE_TOOLING.md): target-aware migrate/schema-codegen flows and deterministic per-target migration state.
- [Phase 5D Typed Data Contracts](PHASE5D_TYPED_CONTRACTS.md): typed row/insert/update generation, decode helpers, and typed SQL artifacts.
- [Phase 5E Hardening + Confidence](PHASE5E_HARDENING_CONFIDENCE.md): soak/fault gates and release confidence artifact pack workflow.
- [Phase 20 Roadmap](PHASE20_ROADMAP.md): extended data-layer depth pass; `20A-20F` are delivered and `20G-20K` now cover relation-kind-safe reflection, richer codec parity, broader inspection, lighter execution ergonomics, and backend support tiers.
- [Phase 7A Runtime Hardening](PHASE7A_RUNTIME_HARDENING.md): websocket backpressure safety limit contract and deterministic overload diagnostics.
- [Phase 7B Security Defaults](PHASE7B_SECURITY_DEFAULTS.md): security profile presets, fail-fast startup validation, and policy contracts.
- [Phase 7C Observability + Operability](PHASE7C_OBSERVABILITY_OPERABILITY.md): trace/correlation propagation, JSON health/readiness signal contracts, and deploy operability validation script.
- [Phase 7D Service Durability](PHASE7D_SERVICE_DURABILITY.md): jobs idempotency-key contracts, cache expiry/removal durability semantics, and retry wrappers for mail/attachment adapters.
- [Phase 7E Template Pipeline Maturity](PHASE7E_TEMPLATE_PIPELINE_MATURITY.md): lint diagnostics, expanded multiline/nested fixture matrix, and render-path hardening contracts.
- [Phase 7F Frontend Integration Starters](PHASE7F_FRONTEND_STARTERS.md): frontend starter generation presets, static/API wiring templates, and deploy-packaging reproducibility contracts.
- [Phase 7G Coding-Agent DX Contracts](PHASE7G_CODING_AGENT_DX_CONTRACTS.md): machine-readable scaffold/build/check/deploy planning payloads and fix-it diagnostics for coding-agent workflows.
- [Phase 7H Distributed Runtime Depth](PHASE7H_DISTRIBUTED_RUNTIME_DEPTH.md): quorum-gated readiness semantics, expanded `/clusterz` coordination matrix, and distributed-runtime diagnostics headers.
- [Sanitizer Suppression Policy](SANITIZER_SUPPRESSION_POLICY.md): temporary suppression lifecycle and expiration contracts for Phase 9H sanitizer lanes.
- [Phase 9I Fault Injection](PHASE9I_FAULT_INJECTION.md): deterministic runtime seam fault scenarios, seed replay, and triage artifacts.
- [Phase 9J Release Certification](PHASE9J_RELEASE_CERTIFICATION.md): release checklist execution, certification thresholds, and enterprise release artifact pack.
- [Known Risk Register](KNOWN_RISK_REGISTER.md): active release risks with owner and target date contracts.
- [Release Notes](RELEASE_NOTES.md): current release-notes scaffold linked to certification and risk-register evidence.
- [Template Troubleshooting](TEMPLATE_TROUBLESHOOTING.md): deterministic transpile/lint diagnostics and repair workflow.
- [SQL Builder Phase 4 Migration Guide](SQL_BUILDER_PHASE4_MIGRATION.md): migration from string-heavy builder usage to IR/typed patterns.
- [Propane Manager](PROPANE.md): production process manager and propane accessories.
- [Release Process](RELEASE_PROCESS.md): semantic versioning, deprecations, and release checklist.
- [Performance Profiles](PERFORMANCE_PROFILES.md): profile pack, trend reports, and baseline governance.
- [GSWeb Migration Guide](MIGRATION_GSWEB.md): side-by-side migration strategy and sample parity routes.
- [Arlen for Rails](ARLEN_FOR_RAILS.md): concept and architecture migration path from Rails.
- [Arlen for Django](ARLEN_FOR_DJANGO.md): concept and architecture migration path from Django.
- [Arlen for Laravel](ARLEN_FOR_LARAVEL.md): concept and architecture migration path from Laravel.
- [Arlen for FastAPI](ARLEN_FOR_FASTAPI.md): concept and architecture migration path from FastAPI.
- [Comparative Benchmarking](COMPARATIVE_BENCHMARKING.md): source-of-truth split between Arlen's in-repo perf regression gates and the sibling comparative/publication benchmark program.
- [Competitive Benchmark Roadmap](COMPETITIVE_BENCHMARK_ROADMAP.md): historical in-repo benchmark track that seeded the later external comparative benchmark program.
- [Benchmark Handoff (2026-02-24 EOD)](BENCHMARK_HANDOFF_2026-02-24.md): historical checkpoint log for the in-repo Phase D campaign handoff.
- [Phase B Parity Checklist (FastAPI)](PHASEB_PARITY_CHECKLIST_FASTAPI.md): executable parity gate for frozen v1 benchmark scenarios.
- [Phase C Benchmark Protocol](PHASEC_BENCHMARK_PROTOCOL.md): warmup + concurrency-ladder benchmark protocol with reproducibility artifacts.
- [Phase D Baseline Campaign](PHASED_BASELINE_CAMPAIGN.md): full Arlen-vs-FastAPI baseline matrix execution with comparison tables and artifact bundle.
- [Arlen for Express/NestJS](ARLEN_FOR_EXPRESS_NESTJS.md): concept and architecture migration path from Express/NestJS.
- [Arlen for Mojolicious](ARLEN_FOR_MOJOLICIOUS.md): concept and architecture migration path from Mojolicious.

## Documentation Process

- [Documentation Policy](DOCUMENTATION_POLICY.md): standards for keeping docs current as features evolve.
- [Session Handoff (2026-03-21 EOD)](SESSION_HANDOFF_2026-03-21.md): exact end-of-day resume point for the cross-repo GNUstep CI/toolchain work.

## Downstream Reports

- [MusicianApp Report Reconciliation (2026-03-21)](MUSICIANAPP_REPORT_RECONCILIATION_2026-03-21.md): upstream-only assessment of the current `MusicianApp` report set and ownership split.
- [Structurizer Report Reconciliation (2026-03-21)](STRUCTURIZER_REPORT_RECONCILIATION_2026-03-21.md): upstream-only assessment of the external `ARLEN_FRAMEWORK_ROOT` sanitizer-artifact report and downstream revalidation status.
- [StateCompulsoryPoolingAPI Report Reconciliation (2026-03-24)](STATECOMPULSORYPOOLINGAPI_REPORT_RECONCILIATION_2026-03-24.md): upstream-only assessment of the `boomhauer --prepare-only` exit-status report and downstream revalidation status.

## Specs and Plans

- [Phase 1 Spec](PHASE1_SPEC.md)
- [Arlen CLI Spec](ARLEN_CLI_SPEC.md)
- [Lite Mode Spec](LITE_MODE_SPEC.md)
- [Phase 2 Roadmap](PHASE2_ROADMAP.md)
- [Phase 3 Roadmap](PHASE3_ROADMAP.md)
- [Phase 4 Roadmap](PHASE4_ROADMAP.md)
- [Phase 5 Roadmap](PHASE5_ROADMAP.md)
- [Phase 7 Roadmap](PHASE7_ROADMAP.md)
- [Phase 8 Roadmap](PHASE8_ROADMAP.md)
- [Phase 9 Roadmap](PHASE9_ROADMAP.md)
- [Phase 10 Roadmap](PHASE10_ROADMAP.md)
- [Phase 11 Roadmap](PHASE11_ROADMAP.md)
- [Phase 12 Roadmap](PHASE12_ROADMAP.md)
- [Phase 13 Roadmap](PHASE13_ROADMAP.md)
- [Phase 14 Roadmap](PHASE14_ROADMAP.md)
- [Phase 15 Roadmap](PHASE15_ROADMAP.md)
- [Phase 16 Roadmap](PHASE16_ROADMAP.md)
- [Phase 17 Roadmap](PHASE17_ROADMAP.md)
- [Phase 18 Roadmap](PHASE18_ROADMAP.md)
- [Phase 19 Roadmap](PHASE19_ROADMAP.md)
- [Phase 20 Roadmap](PHASE20_ROADMAP.md): current data-layer depth pass; `20A-20F` are delivered and `20G-20K` remain planned.
- [Comparative Benchmarking](COMPARATIVE_BENCHMARKING.md)
- [Competitive Benchmark Roadmap](COMPETITIVE_BENCHMARK_ROADMAP.md)
- [Phase B Parity Checklist (FastAPI)](PHASEB_PARITY_CHECKLIST_FASTAPI.md)
- [Phase C Benchmark Protocol](PHASEC_BENCHMARK_PROTOCOL.md)
- [Phase D Baseline Campaign](PHASED_BASELINE_CAMPAIGN.md)
- [Combined Roadmap Index (Historical Aggregate)](PHASE2_PHASE3_ROADMAP.md)
- [Feature Parity Matrix](FEATURE_PARITY_MATRIX.md)
- [EOC v1 Roadmap](EOC_V1_ROADMAP.md)
- [EOC v1 Spec](../V1_SPEC.md)
- [RFC: Keypath Locals + Transformers + Route Compile](RFC_KEYPATH_TRANSFORMERS_ROUTE_COMPILE.md)

## Examples

- [Tech Demo](../examples/tech_demo/README.md)
- [Basic App Smoke Guide](../examples/basic_app/README.md)
- [API-First Reference App](../examples/api_reference/README.md)
- [Auth Primitives Example](../examples/auth_primitives/README.md)
- [Auth + Admin Demo](../examples/auth_admin_demo/README.md)
- [Auth UI Modes](../examples/auth_ui_modes/README.md)
- [Phase 14 Modules Demo](../examples/phase14_modules_demo/README.md)
- [Phase 16 Modules Demo](../examples/phase16_modules_demo/README.md)
- [GSWeb Migration Sample](../examples/gsweb_migration/README.md)
- [ArlenData Standalone Example](../examples/arlen_data/README.md)
