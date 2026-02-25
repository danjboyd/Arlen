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

## Start Here

- [Current Status](STATUS.md): latest checkpoint and verified milestone state.
- [First App Guide](FIRST_APP_GUIDE.md): fastest path to scaffold, run, and extend your first app.
- [Getting Started](GETTING_STARTED.md): prerequisites, framework build, tests, and workflow overview.
- [Getting Started Tracks](GETTING_STARTED_TRACKS.md): quickstart, API-first, HTML-first, and data-layer onboarding paths.
- [API Reference](API_REFERENCE.md): generated public API docs with per-method purpose and usage guidance.
- [Arlen for X Migration Guides](ARLEN_FOR_X_INDEX.md): framework-by-framework migration playbooks.
- [Toolchain Matrix](TOOLCHAIN_MATRIX.md): known-good onboarding/runtime toolchain baseline.
- [CLI Reference](CLI_REFERENCE.md): command reference for `arlen`, `boomhauer`, and helper scripts.
- [Core Concepts](CORE_CONCEPTS.md): runtime architecture and request lifecycle.
- [Deployment Guide](DEPLOYMENT.md): deployment model and production guidance.
- [Realtime and Composition](REALTIME_COMPOSITION.md): websocket/SSE contracts, pubsub hub, and app mounting.
- [Ecosystem Services](ECOSYSTEM_SERVICES.md): jobs/cache/i18n/mail/attachment adapter contracts and plugin wiring.
- [ArlenData Reuse Guide](ARLEN_DATA.md): standalone data-layer packaging, checkout, and versioning policy.
- [SQL Builder Conformance Matrix](SQL_BUILDER_CONFORMANCE_MATRIX.md): phase-4 SQL snapshot matrix and regression gate map.
- [Phase 5A Reliability Contracts](PHASE5A_RELIABILITY_CONTRACTS.md): contract map, external regression intake workflow, and adapter capability metadata baselines.
- [Phase 5B Runtime Routing](PHASE5B_RUNTIME_ROUTING.md): multi-database read/write routing, scoped stickiness, and diagnostics contracts.
- [Phase 5C Multi-Database Tooling](PHASE5C_MULTI_DATABASE_TOOLING.md): target-aware migrate/schema-codegen flows and deterministic per-target migration state.
- [Phase 5D Typed Data Contracts](PHASE5D_TYPED_CONTRACTS.md): typed row/insert/update generation, decode helpers, and typed SQL artifacts.
- [Phase 5E Hardening + Confidence](PHASE5E_HARDENING_CONFIDENCE.md): soak/fault gates and release confidence artifact pack workflow.
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
- [Competitive Benchmark Roadmap](COMPETITIVE_BENCHMARK_ROADMAP.md): scenario-driven, reproducible benchmark plan for publishable Arlen-vs-framework claims.
- [Benchmark Handoff (2026-02-24 EOD)](BENCHMARK_HANDOFF_2026-02-24.md): checkpoint log with latest run ids, artifacts, blocker notes, and morning resume steps.
- [Phase B Parity Checklist (FastAPI)](PHASEB_PARITY_CHECKLIST_FASTAPI.md): executable parity gate for frozen v1 benchmark scenarios.
- [Phase C Benchmark Protocol](PHASEC_BENCHMARK_PROTOCOL.md): warmup + concurrency-ladder benchmark protocol with reproducibility artifacts.
- [Phase D Baseline Campaign](PHASED_BASELINE_CAMPAIGN.md): full Arlen-vs-FastAPI baseline matrix execution with comparison tables and artifact bundle.
- [Arlen for Express/NestJS](ARLEN_FOR_EXPRESS_NESTJS.md): concept and architecture migration path from Express/NestJS.
- [Arlen for Mojolicious](ARLEN_FOR_MOJOLICIOUS.md): concept and architecture migration path from Mojolicious.

## Documentation Process

- [Documentation Policy](DOCUMENTATION_POLICY.md): standards for keeping docs current as features evolve.

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
- [Competitive Benchmark Roadmap](COMPETITIVE_BENCHMARK_ROADMAP.md)
- [Phase B Parity Checklist (FastAPI)](PHASEB_PARITY_CHECKLIST_FASTAPI.md)
- [Phase C Benchmark Protocol](PHASEC_BENCHMARK_PROTOCOL.md)
- [Phase D Baseline Campaign](PHASED_BASELINE_CAMPAIGN.md)
- [Combined Roadmap Index](PHASE2_PHASE3_ROADMAP.md)
- [Feature Parity Matrix](FEATURE_PARITY_MATRIX.md)
- [EOC v1 Roadmap](EOC_V1_ROADMAP.md)
- [EOC v1 Spec](../V1_SPEC.md)
- [RFC: Keypath Locals + Transformers + Route Compile](RFC_KEYPATH_TRANSFORMERS_ROUTE_COMPILE.md)

## Examples

- [Tech Demo](../examples/tech_demo/README.md)
- [Basic App Smoke Guide](../examples/basic_app/README.md)
- [API-First Reference App](../examples/api_reference/README.md)
- [GSWeb Migration Sample](../examples/gsweb_migration/README.md)
- [ArlenData Standalone Example](../examples/arlen_data/README.md)
