# Arlen

Arlen is a GNUstep-native Objective-C web framework with an MVC runtime, EOC templates (`.html.eoc`), and a developer server (`boomhauer`).

Arlen is designed to solve the same class of problems as frameworks like Mojolicious while staying idiomatic to Objective-C/GNUstep conventions.

## Status

- Phase 1: complete and working.
- Phase 2A: complete (`propane` + runtime hardening).
- Phase 2B: complete (PostgreSQL adapter, migrations, sessions/CSRF/rate-limit/security headers).
- Phase 2C: complete (developer error UX + validation + timing controls).
- Phase 2D: complete (parity baseline + deployment contract + perf gate hardening).
- Phase 3A: complete (metrics, schema/auth contracts, OpenAPI baseline, plugins/lifecycle).
- Phase 3B: complete (data-layer maturation, interactive OpenAPI explorer, GSWeb compatibility helpers).
- Phase 3C: complete (release/doc maturity, perf trend profiles, swagger docs style, migration readiness package).
- Phase 3D: complete (websocket/SSE baseline, mount composition, realtime pubsub abstraction).
- Phase 3E: complete (plugin-first ecosystem services: jobs/cache/i18n/mail/attachments).
- Phase 3F: complete (doctor + toolchain matrix, ALNPg diagnostics hardening, API helpers, static mount ergonomics, concrete jobs/mail adapters, async worker supervision baseline).
- Phase 3G: complete (SQL builder v2 expansion, PostgreSQL dialect builder, and standalone `ArlenData` reuse packaging).
- Phase 3H: complete (cluster runtime primitives: `/clusterz`, cluster response headers, and propane cluster controls).
- Phase 4A: complete (query IR foundation for expression compilation, safety contracts, and deterministic malformed-shape diagnostics).
- Phase 4B: complete (SQL surface completion for set/window/predicate/locking/join/CTE composition).
- Phase 4C: complete (typed schema codegen with generated table/column helper APIs and CLI workflow).
- Phase 4D: complete (builder execution caching, prepared-statement reuse policy, and structured/redacted query diagnostics).
- Phase 4E: complete (conformance matrix, property/long-run regression suite, migration/deprecation hardening, and Phase 4 quality gate wiring).
- Phase 5A: complete (reliability contract mapping, external regression intake, and adapter capability metadata baselines).
- Phase 5B: complete (runtime read/write routing, scoped read-after-write stickiness, and deterministic fallback diagnostics).
- Phase 5C: complete (target-aware multi-database migration/schema-codegen tooling and deterministic per-target state).
- Phase 5D: complete (typed row/insert/update schema contracts, typed decode helpers, and typed SQL codegen workflow).
- Phase 5E: complete (data-layer soak/fault hardening gates and release confidence artifact pack generation).
- Phase 7A: initial slice implemented (websocket runtime backpressure boundary + deterministic overload diagnostics).
- Phase 7B: initial slice implemented (security profile presets + fail-fast security misconfiguration startup diagnostics).
- Phase 7C: initial slice implemented (trace/correlation propagation headers, JSON health/readiness signal payloads, and deploy operability validation script integration).
- Phase 7D: initial slice implemented (jobs idempotency-key durability contracts, cache expiry/removal conformance hardening, and retry-policy wrappers for mail/attachments).
- Phase 7E: initial slice implemented (template lint diagnostics, expanded multiline/nested fixture coverage, and include/render path hardening integration checks).
- Phase 7F: initial slice implemented (frontend starter generation presets, static-asset/API wiring templates, and reproducibility/deploy-packaging validation).
- Phase 7G: initial slice implemented (coding-agent JSON workflow contracts, fix-it diagnostics, and deploy/build/check planning payloads).
- Phase 7H: initial slice implemented (quorum-gated readiness, expanded `/clusterz` coordination contracts, and distributed-runtime diagnostics headers).
- Phase 9: complete (documentation platform, generated API reference, onboarding tracks/migration guides, and enterprise release certification hardening track).

## Quick Start

Prerequisites:
- GNUstep toolchain installed
- `tools-xctest` installed (provides `xctest`)

Initialize GNUstep in your shell:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
```

Run bootstrap diagnostics before building:

```bash
./bin/arlen doctor
```

Build framework tools and dev server:

```bash
make all
```

Run the built-in development server:

```bash
./bin/boomhauer
```

Create and run your first app with the CLI:

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Run tests and quality gate:

```bash
./bin/test
make check
make parity-phaseb
make perf-phasec
make perf-phased
make ci-quality
make ci-fault-injection
make ci-release-certification
make test-data-layer
```

Run the technology demo:

```bash
./bin/tech-demo
```

Then open `http://127.0.0.1:3110/tech-demo`.

Run deployment smoke validation:

```bash
make deploy-smoke
```

## Documentation

Start here:
- [Docs Index](docs/README.md)

Generate browser-friendly HTML docs:

```bash
make docs-api
make docs-html
make docs-serve
```

Open `build/docs/index.html` in a browser.

High-value guides:
- [First App Guide](docs/FIRST_APP_GUIDE.md)
- [Getting Started](docs/GETTING_STARTED.md)
- [Getting Started Tracks](docs/GETTING_STARTED_TRACKS.md)
- [API Reference](docs/API_REFERENCE.md)
- [Arlen for X Migration Guides](docs/ARLEN_FOR_X_INDEX.md)
- [Toolchain Matrix](docs/TOOLCHAIN_MATRIX.md)
- [CLI Reference](docs/CLI_REFERENCE.md)
- [Core Concepts](docs/CORE_CONCEPTS.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Realtime and Composition](docs/REALTIME_COMPOSITION.md)
- [Ecosystem Services](docs/ECOSYSTEM_SERVICES.md)
- [ArlenData Reuse Guide](docs/ARLEN_DATA.md)
- [SQL Builder Conformance Matrix](docs/SQL_BUILDER_CONFORMANCE_MATRIX.md)
- [Phase 5E Hardening + Confidence](docs/PHASE5E_HARDENING_CONFIDENCE.md)
- [Phase 7A Runtime Hardening](docs/PHASE7A_RUNTIME_HARDENING.md)
- [Phase 7B Security Defaults](docs/PHASE7B_SECURITY_DEFAULTS.md)
- [Phase 7C Observability + Operability](docs/PHASE7C_OBSERVABILITY_OPERABILITY.md)
- [Phase 7D Service Durability](docs/PHASE7D_SERVICE_DURABILITY.md)
- [Phase 7E Template Pipeline Maturity](docs/PHASE7E_TEMPLATE_PIPELINE_MATURITY.md)
- [Phase 7F Frontend Integration Starters](docs/PHASE7F_FRONTEND_STARTERS.md)
- [Phase 7G Coding-Agent DX Contracts](docs/PHASE7G_CODING_AGENT_DX_CONTRACTS.md)
- [Phase 7H Distributed Runtime Depth](docs/PHASE7H_DISTRIBUTED_RUNTIME_DEPTH.md)
- [Template Troubleshooting](docs/TEMPLATE_TROUBLESHOOTING.md)
- [SQL Builder Phase 4 Migration Guide](docs/SQL_BUILDER_PHASE4_MIGRATION.md)
- [Propane Manager](docs/PROPANE.md)
- [Sanitizer Suppression Policy](docs/SANITIZER_SUPPRESSION_POLICY.md)
- [Phase 9I Fault Injection](docs/PHASE9I_FAULT_INJECTION.md)
- [Phase 9J Release Certification](docs/PHASE9J_RELEASE_CERTIFICATION.md)
- [Known Risk Register](docs/KNOWN_RISK_REGISTER.md)
- [Release Notes](docs/RELEASE_NOTES.md)
- [Release Process](docs/RELEASE_PROCESS.md)
- [Performance Profiles](docs/PERFORMANCE_PROFILES.md)
- [GSWeb Migration Guide](docs/MIGRATION_GSWEB.md)
- [Arlen for Rails](docs/ARLEN_FOR_RAILS.md)
- [Arlen for Django](docs/ARLEN_FOR_DJANGO.md)
- [Arlen for Laravel](docs/ARLEN_FOR_LARAVEL.md)
- [Arlen for FastAPI](docs/ARLEN_FOR_FASTAPI.md)
- [Competitive Benchmark Roadmap](docs/COMPETITIVE_BENCHMARK_ROADMAP.md)
- [Phase B Parity Checklist (FastAPI)](docs/PHASEB_PARITY_CHECKLIST_FASTAPI.md)
- [Phase C Benchmark Protocol](docs/PHASEC_BENCHMARK_PROTOCOL.md)
- [Phase D Baseline Campaign](docs/PHASED_BASELINE_CAMPAIGN.md)
- [Arlen for Express/NestJS](docs/ARLEN_FOR_EXPRESS_NESTJS.md)
- [Arlen for Mojolicious](docs/ARLEN_FOR_MOJOLICIOUS.md)
- [Documentation Policy](docs/DOCUMENTATION_POLICY.md)

Specifications and roadmaps:
- [Phase 1 Spec](docs/PHASE1_SPEC.md)
- [Phase 2 Roadmap](docs/PHASE2_ROADMAP.md)
- [Phase 3 Roadmap](docs/PHASE3_ROADMAP.md)
- [Phase 4 Roadmap](docs/PHASE4_ROADMAP.md)
- [Phase 5 Roadmap](docs/PHASE5_ROADMAP.md)
- [Phase 7 Roadmap](docs/PHASE7_ROADMAP.md)
- [Phase 8 Roadmap](docs/PHASE8_ROADMAP.md)
- [Phase 9 Roadmap](docs/PHASE9_ROADMAP.md)
- [Competitive Benchmark Roadmap](docs/COMPETITIVE_BENCHMARK_ROADMAP.md)
- [Phase B Parity Checklist (FastAPI)](docs/PHASEB_PARITY_CHECKLIST_FASTAPI.md)
- [Phase C Benchmark Protocol](docs/PHASEC_BENCHMARK_PROTOCOL.md)
- [Phase D Baseline Campaign](docs/PHASED_BASELINE_CAMPAIGN.md)
- [EOC v1 Spec](V1_SPEC.md)
- [RFC: Keypath Locals + Transformers + Route Compile](docs/RFC_KEYPATH_TRANSFORMERS_ROUTE_COMPILE.md)

## Naming

- Development server: `boomhauer`
- Production manager: `propane`
- All `propane` settings are referred to as "propane accessories"

## License

Arlen is licensed under the GNU Lesser General Public License, version 2 or (at your option) any later version (LGPL-2.0-or-later), aligned with GNUstep Base library licensing.
