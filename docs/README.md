# Arlen Documentation

This is the main documentation index for Arlen.

Generate browser-friendly docs:

```bash
make docs-api
make docs-html
make ci-docs
make docs-serve
```

Open `build/docs/index.html` in your browser, or use `make docs-serve` for
local hosting.

## New Developers

- [First App Guide](FIRST_APP_GUIDE.md): shortest path to scaffold, run, and extend your first app.
- [Getting Started](GETTING_STARTED.md): build Arlen, create an app, add a route, and choose the next guide.
- [Getting Started Tracks](GETTING_STARTED_TRACKS.md): quickstart, API-first, HTML-first, and data-layer entry paths.
- [App Authoring Guide](APP_AUTHORING_GUIDE.md): routes, controllers, middleware, and route metadata.
- [Configuration Reference](CONFIGURATION_REFERENCE.md): config keys app authors touch first.
- [Lite Mode Guide](LITE_MODE_GUIDE.md): when to choose lite mode and how to grow beyond it.
- [Toolchain Matrix](TOOLCHAIN_MATRIX.md): known-good onboarding/runtime baseline.
- [Windows CLANG64 Preview](WINDOWS_CLANG64.md): native Windows/MSYS2 `CLANG64` Phase 24 workflow and current support scope.
- [Windows Runtime Story](WINDOWS_RUNTIME_STORY.md): explicit native Windows runtime/deployment support boundary.
- [CLI Reference](CLI_REFERENCE.md): command reference for `arlen`, `boomhauer`, and helper scripts.

## App Authoring

- [Getting Started: API-First Track](GETTING_STARTED_API_FIRST.md): JSON APIs, schema/auth contracts, and OpenAPI.
- [Getting Started: HTML-First Track](GETTING_STARTED_HTML_FIRST.md): server-rendered EOC templates, layouts, and forms.
- [Core Concepts](CORE_CONCEPTS.md): runtime architecture and request lifecycle.
- [Template Troubleshooting](TEMPLATE_TROUBLESHOOTING.md): deterministic transpile/lint diagnostics and repair workflow.
- [API Reference](API_REFERENCE.md): generated public API docs with per-method purpose and usage guidance.

## Modules and Integrations

- [Modules](MODULES.md): module install, doctor, migrate, assets, upgrade, eject, remove, and override guidance.
- [Plugin + Service Guide](PLUGIN_SERVICE_GUIDE.md): generate app-local plugins and service adapters.
- [Frontend Starters Guide](FRONTEND_STARTERS.md): choose and customize generated frontend starter folders.
- [Auth Module](AUTH_MODULE.md): first-party auth product routes, fragments, helpers, and `/auth/api` surface.
- [Auth UI Integration Modes](AUTH_UI_INTEGRATION_MODES.md): `headless`, `module-ui`, and `generated-app-ui`.
- [Admin UI Module](ADMIN_UI_MODULE.md): admin resources, filters, exports, and `/admin/api`.
- [Jobs Module](JOBS_MODULE.md): `/jobs` HTML plus `/jobs/api` JSON/OpenAPI surface.
- [Notifications Module](NOTIFICATIONS_MODULE.md): inbox/preferences plus admin preview/outbox/test-send flows.
- [Storage Module](STORAGE_MODULE.md): collections, direct uploads, signed downloads, and `/storage/api`.
- [Ops Module](OPS_MODULE.md): operational dashboard plus `/ops/api`.
- [Search Module](SEARCH_MODULE.md): query, reindex, incremental sync, and admin/ops integration.
- [Ecosystem Services](ECOSYSTEM_SERVICES.md): jobs/cache/i18n/mail/attachment adapter contracts.
- [ArlenData Reuse Guide](ARLEN_DATA.md): standalone data-layer packaging and PostgreSQL/MSSQL usage.

## Operations and Deployment

- [Deployment Guide](DEPLOYMENT.md): deployment model and production guidance.
- [Systemd Runbook](SYSTEMD_RUNBOOK.md): systemd unit template and incident collection steps.
- [Propane Manager](PROPANE.md): production process manager and propane accessories.
- [Windows Runtime Story](WINDOWS_RUNTIME_STORY.md): native Windows support boundary for runtime/deployment surfaces.
- [Release Process](RELEASE_PROCESS.md): semantic versioning, deprecations, and release checklist.
- [Testing Workflow](TESTING_WORKFLOW.md): focused contributor lanes for turning bug reports into regressions.

## Reference

- [Password Hashing](PASSWORD_HASHING.md): Argon2id password hashing defaults and rehash workflow.
- [Realtime and Composition](REALTIME_COMPOSITION.md): websocket/SSE contracts, pubsub hub, and app mounting.
- [Arlen for X Migration Guides](ARLEN_FOR_X_INDEX.md): migration playbooks from Rails, Django, Laravel, FastAPI, Express/NestJS, Mojolicious, and GSWeb.
- [SQL Builder Conformance Matrix](SQL_BUILDER_CONFORMANCE_MATRIX.md): phase-4 SQL snapshot matrix and regression map.

## Contributor and Historical Docs

- [Current Status](STATUS.md): latest checkpoint and verified milestone state.
- [Session Handoff (2026-03-27)](SESSION_HANDOFF_2026-03-27.md): historical pause point before the Phase 22 closeout.
- [Documentation Policy](DOCUMENTATION_POLICY.md): docs standards and review checklist.
- [Phase 20 Roadmap](PHASE20_ROADMAP.md): completed data-layer depth pass.
- [Phase 21 Roadmap](PHASE21_ROADMAP.md): completed public-release test robustness pass.
- [Phase 22 Roadmap](PHASE22_ROADMAP.md): completed documentation cleanup pass for newcomer-first onboarding and docs quality closeout.
- [Phase 24 Roadmap](PHASE24_ROADMAP.md): completed Windows/MSYS2 `CLANG64` preview-contract roadmap on branch `windows/clang64`.
- [Combined Roadmap Index (Historical Aggregate)](PHASE2_PHASE3_ROADMAP.md)
- [Phase 1 Spec](PHASE1_SPEC.md)
- [Arlen CLI Spec](ARLEN_CLI_SPEC.md)
- [Lite Mode Spec](LITE_MODE_SPEC.md)
- [Phase 7 Roadmap](PHASE7_ROADMAP.md)
- [Phase 9 Roadmap](PHASE9_ROADMAP.md)
- [EOC v1 Roadmap](EOC_V1_ROADMAP.md)
- [Known Risk Register](KNOWN_RISK_REGISTER.md)
- [Release Notes](RELEASE_NOTES.md)
- [Comparative Benchmarking](COMPARATIVE_BENCHMARKING.md)
- [Competitive Benchmark Roadmap](COMPETITIVE_BENCHMARK_ROADMAP.md)

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
