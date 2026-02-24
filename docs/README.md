# Arlen Documentation

This is the main documentation index for Arlen.

Generate browser-friendly docs:

```bash
make docs-html
```

Open `build/docs/index.html` in your browser.

## Start Here

- [Current Status](STATUS.md): latest checkpoint and verified milestone state.
- [First App Guide](FIRST_APP_GUIDE.md): fastest path to scaffold, run, and extend your first app.
- [Getting Started](GETTING_STARTED.md): prerequisites, framework build, tests, and workflow overview.
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
- [Template Troubleshooting](TEMPLATE_TROUBLESHOOTING.md): deterministic transpile/lint diagnostics and repair workflow.
- [SQL Builder Phase 4 Migration Guide](SQL_BUILDER_PHASE4_MIGRATION.md): migration from string-heavy builder usage to IR/typed patterns.
- [Propane Manager](PROPANE.md): production process manager and propane accessories.
- [Release Process](RELEASE_PROCESS.md): semantic versioning, deprecations, and release checklist.
- [Performance Profiles](PERFORMANCE_PROFILES.md): profile pack, trend reports, and baseline governance.
- [GSWeb Migration Guide](MIGRATION_GSWEB.md): side-by-side migration strategy and sample parity routes.

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
