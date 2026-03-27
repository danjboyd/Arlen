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
- Phase 7: complete for current first-party scope (runtime hardening, security defaults, observability/operability, ecosystem durability, template pipeline maturity, frontend starters, coding-agent DX, and distributed-runtime contracts; closeout verified 2026-03-13).
- Phase 9: complete (documentation platform, generated API reference, onboarding tracks/migration guides, and enterprise release certification hardening track).
- Phase 11A: complete (session/bearer/CSRF hardening).
- Phase 11B: complete (HTTP header and parser-boundary hardening).
- Phase 11C: complete (websocket handshake/origin/stall hardening).
- Phase 11D: complete (static/attachment filesystem containment and private on-disk adapter permissions).
- Phase 11E: complete (trusted proxy CIDR boundaries and text-log control-character escaping).
- Phase 11F: complete (hostile protocol corpus, deterministic fuzz/live probes, and Phase 11 sanitizer confidence lanes).
- Phase 12: complete (12A-12F delivered: auth-assurance/step-up primitives, TOTP/recovery helpers, WebAuthn/passkey MFA baseline, OIDC/provider-login primitives, and Phase 12 confidence artifacts).
- Phase 13: complete (13A-13I delivered: first-class module substrate, first-party `auth` and `admin-ui` modules, Django-inspired admin resources, `/auth/api` + `/admin/api` surfaces, sample app, and Phase 13 confidence gate).
- Phase 14: complete (14A-14I delivered: first-party `jobs`, `notifications`, `storage`, `ops`, and `search` modules, Phase 14 sample app, and `phase14-confidence` gate).
- Phase 15: complete (15A-15E delivered on 2026-03-10: `headless`, `module-ui`, `generated-app-ui`, auth UI examples, and `phase15-confidence`).
- Phase 16: complete (`16A-16G` delivered on 2026-03-11: `jobs`, `notifications`, `storage`, `search`, `ops`, and `admin-ui` maturity; `examples/phase16_modules_demo` and `phase16-confidence` included. See `docs/PHASE16_ROADMAP.md`).
- Phase 17: complete (`17A-17D` delivered on 2026-03-12: backend-neutral SQL dialect/migration seams, optional MSSQL adapter + dialect, configured `migrate` / `module migrate` backend selection, and updated data-layer docs. See `docs/PHASE17_ROADMAP.md`).
- Phase 18: complete (`18A-18H` delivered on 2026-03-14: fragment-first MFA UI reuse, headless MFA contract refinement, optional SMS/Twilio Verify support, and generated-app-ui include-path hardening. See `docs/PHASE18_ROADMAP.md`).
- Phase 19: complete (`19A-19F` delivered on 2026-03-14: incremental GNUmake/GNUstep build-graph narrowing, generated-template object reuse, clearer `boomhauer` build phases, and `phase19-confidence`. See `docs/PHASE19_ROADMAP.md`).
- Phase 20: complete (`20A-20K` delivered on 2026-03-26; `20L-20R` delivered on 2026-03-27 for MSSQL native transport tightening, ordered result semantics, bounded PostgreSQL metadata expansion, explicit live-test requirement accounting, shared test support/assertion layers, and repo-native focused confidence lanes. See `docs/PHASE20_ROADMAP.md`).

## Quick Start

Prerequisites:
- clang-built GNUstep toolchain installed
- `tools-xctest` installed (provides `xctest`)

Optional contributor fast path:
- set `ARLEN_XCTEST=/path/to/patched/xctest` to use a filter-capable XCTest runner for focused reruns such as `make test-unit-filter TEST=RuntimeTests/testRenderAndIncludeNormalizeUnsuffixedTemplateReferences`
- if that runner comes from a local uninstalled `tools-xctest` checkout, also set `ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj`

Initialize GNUstep in your shell:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
```

Run bootstrap diagnostics before building:

```bash
./bin/arlen doctor
```

CI note:
- Arlen CI expects a clang-built GNUstep toolchain, not a generic GCC-oriented distro stack.
- The workflow bootstrap entry point is `tools/ci/install_ci_dependencies.sh`.
- Current self-hosted runners use `ARLEN_CI_GNUSTEP_STRATEGY=preinstalled` with the clang-built GNUstep toolchain installed at `/usr/GNUstep`.
- Use `ARLEN_CI_GNUSTEP_STRATEGY=apt` or `bootstrap` only when provisioning a runner that does not already carry that toolchain.

Build framework tools and dev server:

```bash
make all
```

Build policy: Arlen enforces ARC across first-party Objective-C compile paths (`-fobjc-arc` required).
`EXTRA_OBJC_FLAGS` is additive only and cannot disable ARC.
Changing compile toggles or `EXTRA_OBJC_FLAGS` invalidates cached repo build artifacts so sanitizer-built tools are not silently reused in normal lanes.
For app-root non-watch flows, `boomhauer --prepare-only` and `--print-routes`
now preserve the underlying non-zero build exit status and write diagnostics to
`.boomhauer/last_build_error.log` plus `.boomhauer/last_build_error.meta` so
automation does not treat stale binaries as a successful prepare.

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

Full-mode scaffolds now default to composition-first EOC:
- `templates/layouts/main.html.eoc` owns the app shell
- `templates/index.html.eoc` opts into that shell with `<%@ layout "layouts/main" %>`
- `templates/partials/_nav.html.eoc` and `templates/partials/_feature.html.eoc` demonstrate partial includes and collection rendering

Phase 13/14/15/16 modules quick path:

```bash
/path/to/Arlen/build/arlen module add auth
/path/to/Arlen/build/arlen module add admin-ui
/path/to/Arlen/build/arlen module add jobs
/path/to/Arlen/build/arlen module add notifications
/path/to/Arlen/build/arlen module add storage
/path/to/Arlen/build/arlen module add ops
/path/to/Arlen/build/arlen module add search
/path/to/Arlen/build/arlen module doctor --json
/path/to/Arlen/build/arlen module assets --output-dir build/module_assets
/path/to/Arlen/build/arlen module migrate --env development
```

Run `module migrate --env <env>` before the first local `auth` registration or
login attempt. Missing auth tables now surface an actionable module-migrate
message instead of a generic database error.

See `examples/phase16_modules_demo/README.md` for the canonical app-owned
`admin-ui` + `search` + `ops` composition path on top of the matured Phase 16
module stack.

First-party module surfaces:
- `auth` keeps `/auth/api/...` stable, now exposes explicit MFA `flow`/`mfa` JSON plus `/auth/api/mfa` factor discovery for headless clients, supports optional disabled-by-default SMS/Twilio Verify MFA, and lets apps choose `headless`, `module-ui`, or `generated-app-ui` ownership for `/auth/...`
- `admin-ui` ships HTML under `/admin/...` and JSON under `/admin/api/...`
- `jobs` ships protected HTML under `/jobs/...` and JSON under `/jobs/api/...`
- `notifications` ships user HTML under `/notifications/...`, admin HTML under `/notifications/...`, and JSON under `/notifications/api/...`
- `storage` ships protected HTML under `/storage/...`, JSON/OpenAPI under `/storage/api/...`, and signed downloads under `/storage/api/download/:token`
- `ops` ships protected HTML under `/ops/...` and JSON/OpenAPI under `/ops/api/...`
- `search` ships public query HTML/JSON under `/search/...` and protected reindex routes under `/search/api/...`

Auth UI ownership quick path:
- `module-ui`: default stock auth pages with optional app layout/context hook
- server-rendered EOC apps can now also embed coarse auth fragments such as the MFA enrollment/challenge/recovery panels inside app-owned pages
- `headless`: set `authModule.ui.mode = "headless"` and use `/auth/api/...` from your SPA or native client
- `generated-app-ui`: run `/path/to/Arlen/build/arlen module eject auth-ui --json` to scaffold `templates/auth/...`, `templates/auth/fragments/...`, factor-management pages, and `public/auth/auth.css` plus the local QR asset

Run tests and quality gate:

```bash
./bin/test
make check
make parity-phaseb
make perf-phasec
make perf-phased
make ci-perf-smoke
make ci-benchmark-contracts
make ci-quality
make ci-fault-injection
make ci-release-certification
make ci-phase11
make phase14-confidence
make phase15-confidence
make phase16-confidence
make test-data-layer
make browser-error-audit
```

`make ci-perf-smoke` is the lighter local/manual macro perf subset. The
self-hosted quality workflow already runs the broader multi-profile macro perf
matrix through `make ci-quality`, pinned to
`tests/performance/baselines/iep-apt` on the current `iep-apt` runner.

`make browser-error-audit` generates a browser-reviewable gallery of representative
build/runtime error surfaces under `build/browser-error-audit/index.html`.

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
- [Modules](docs/MODULES.md)
- [Auth Module](docs/AUTH_MODULE.md)
- [Auth UI Integration Modes](docs/AUTH_UI_INTEGRATION_MODES.md)
- [Admin UI Module](docs/ADMIN_UI_MODULE.md)
- [Jobs Module](docs/JOBS_MODULE.md)
- [Notifications Module](docs/NOTIFICATIONS_MODULE.md)
- [Storage Module](docs/STORAGE_MODULE.md)
- [Ops Module](docs/OPS_MODULE.md)
- [Search Module](docs/SEARCH_MODULE.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Systemd Runbook](docs/SYSTEMD_RUNBOOK.md)
- [Password Hashing](docs/PASSWORD_HASHING.md)
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
- [Comparative Benchmarking](docs/COMPARATIVE_BENCHMARKING.md)
- [Competitive Benchmark Roadmap (Historical In-Repo Track)](docs/COMPETITIVE_BENCHMARK_ROADMAP.md)
- [Benchmark Handoff (Historical 2026-02-24 EOD)](docs/BENCHMARK_HANDOFF_2026-02-24.md)
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
- [Phase 10 Roadmap](docs/PHASE10_ROADMAP.md)
- [Phase 11 Roadmap](docs/PHASE11_ROADMAP.md)
- [Phase 12 Roadmap](docs/PHASE12_ROADMAP.md)
- [Phase 13 Roadmap](docs/PHASE13_ROADMAP.md)
- [Phase 14 Roadmap](docs/PHASE14_ROADMAP.md)
- [Phase 15 Roadmap](docs/PHASE15_ROADMAP.md)
- [Phase 16 Roadmap](docs/PHASE16_ROADMAP.md)
- [Phase 17 Roadmap](docs/PHASE17_ROADMAP.md)
- [Phase 20 Roadmap](docs/PHASE20_ROADMAP.md)
- [Comparative Benchmarking](docs/COMPARATIVE_BENCHMARKING.md)
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
