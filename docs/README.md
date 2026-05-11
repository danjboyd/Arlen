# Arlen Documentation

This is the curated documentation index for Arlen. It is organized by reader
intent: getting started, building apps, modules, data layer, operations,
reference, and examples.

Generate browser-friendly HTML docs:

```bash
make docs-api
make docs-html
make ci-docs
make docs-serve
```

Open `build/docs/index.html` in your browser, or use `make docs-serve` for
local hosting.

Before running repo-local build/test/doc commands, source
`/path/to/Arlen/tools/source_gnustep_env.sh` or source your active GNUstep
toolchain env directly for the Linux/GNUstep path. On macOS, use
`GETTING_STARTED_MACOS.md`.

## Start Here

- [First App Guide](FIRST_APP_GUIDE.md): shortest path to scaffold, run, and extend your first app.
- [Getting Started](GETTING_STARTED.md): build Arlen, create an app, add a route, and choose the next guide.
- [Getting Started Quickstart](GETTING_STARTED_QUICKSTART.md): the minimum-friction first-app path.
- [Getting Started Tracks](GETTING_STARTED_TRACKS.md): quickstart, API-first, HTML-first, and data-layer entry paths.
- [Getting Started on macOS](GETTING_STARTED_MACOS.md): Apple-runtime bootstrap path for macOS without GNUstep.
- [Toolchain Matrix](TOOLCHAIN_MATRIX.md): known-good onboarding/runtime baseline.

## Building Apps

- [App Authoring Guide](APP_AUTHORING_GUIDE.md): routes, controllers, middleware, and route metadata.
- [Core Concepts](CORE_CONCEPTS.md): runtime architecture and request lifecycle.
- [Getting Started: API-First Track](GETTING_STARTED_API_FIRST.md): JSON APIs, schema/auth contracts, and OpenAPI.
- [Getting Started: HTML-First Track](GETTING_STARTED_HTML_FIRST.md): server-rendered EOC templates, layouts, and forms.
- [EOC Guide](EOC_GUIDE.md): comprehensive syntax and authoring guide for `.html.eoc` templates.
- [Template Troubleshooting](TEMPLATE_TROUBLESHOOTING.md): deterministic transpile/lint diagnostics and repair workflow.
- [Live UI Guide](LIVE_UI.md): fragment-first live responses, `/arlen/live.js`, keyed collections, live regions, live forms/links, and realtime push updates.
- [Durable Event Streams](EVENT_STREAMS.md): durable append/replay, websocket/SSE/poll consumption, auth hooks, and the plain generated TypeScript stream client.
- [Realtime and Composition](REALTIME_COMPOSITION.md): websocket/SSE contracts, live fragment transport, pubsub hub, and app mounting.
- [Configuration Reference](CONFIGURATION_REFERENCE.md): config keys app authors touch first.
- [Lite Mode Guide](LITE_MODE_GUIDE.md): when to choose lite mode and how to grow beyond it.
- [Frontend Starters Guide](FRONTEND_STARTERS.md): choose and customize generated frontend starter folders.
- [CLI Reference](CLI_REFERENCE.md): command reference for `arlen`, `boomhauer`, and helper scripts.

## Modules

- [Modules](MODULES.md): install, doctor, migrate, assets, upgrade, eject, remove, and override guidance.
- [Plugin + Service Guide](PLUGIN_SERVICE_GUIDE.md): generate app-local plugins and service adapters.
- [Auth Module](AUTH_MODULE.md): first-party auth product routes, fragments, helpers, and `/auth/api` surface.
- [Auth UI Integration Modes](AUTH_UI_INTEGRATION_MODES.md): `headless`, `module-ui`, and `generated-app-ui`.
- [Admin UI Module](ADMIN_UI_MODULE.md): admin resources, filters, exports, and `/admin/api`.
- [Jobs Module](JOBS_MODULE.md): `/jobs` HTML plus `/jobs/api` JSON/OpenAPI surface.
- [Notifications Module](NOTIFICATIONS_MODULE.md): inbox/preferences plus admin preview/outbox/test-send flows.
- [Storage Module](STORAGE_MODULE.md): collections, direct uploads, signed downloads, and `/storage/api`.
- [Ops Module](OPS_MODULE.md): operational dashboard plus `/ops/api`.
- [Search Module](SEARCH_MODULE.md): shaped public query contracts, PostgreSQL/Meilisearch/OpenSearch engines, reindex/incremental sync, and admin/ops integration.
- [Ecosystem Services](ECOSYSTEM_SERVICES.md): jobs/cache/i18n/mail/attachment adapter contracts.

## Data Layer

- [Getting Started: Data Layer](GETTING_STARTED_DATA_LAYER.md): PostgreSQL-first migrations, typed SQL helpers, and codegen.
- [ArlenData Reuse Guide](ARLEN_DATA.md): standalone data-layer packaging and PostgreSQL/MSSQL/Dataverse usage.
- [Dataverse Integration](DATAVERSE.md): Dataverse Web API client, config shape, OData query usage, and typed codegen workflow.
- [ArlenORM Guide](ARLEN_ORM.md): optional SQL and Dataverse ORM layers on ArlenData.
- [ArlenORM Migration Contracts](ARLEN_ORM_MIGRATIONS.md): descriptor snapshots and schema/codegen drift checks.
- [ArlenORM Backend Matrix](ARLEN_ORM_BACKEND_MATRIX.md): PostgreSQL, MSSQL, and Dataverse capability boundaries.
- [SQL Builder Conformance Matrix](SQL_BUILDER_CONFORMANCE_MATRIX.md): SQL snapshot matrix and regression map.

## Operations and Deployment

- [Deployment Guide](DEPLOYMENT.md): deployment model and production guidance.
- [Propane Manager](PROPANE.md): production process manager and propane accessories.
- [Systemd Runbook](SYSTEMD_RUNBOOK.md): systemd unit template and incident collection steps.
- [Route Policies](ROUTE_POLICIES.md): named access policies, proxy-aware source IP allowlisting, `/admin` policy wiring, diagnostics, and confidence checks.
- [Release Process](RELEASE_PROCESS.md): semantic versioning, deprecations, and release checklist.
- [Apple Platform Contract](APPLE_PLATFORM.md): current Apple-runtime support boundary on macOS, including the verified auth/runtime lane.
- [Windows CLANG64 Preview](WINDOWS_CLANG64.md): current `main`-branch Windows bootstrap, packaged-release preview contract, and support statement.

## Reference

- [API Reference](API_REFERENCE.md): generated public API docs with per-method purpose and usage guidance.
- [Password Hashing](PASSWORD_HASHING.md): Argon2id password hashing defaults and rehash workflow.
- [Public Test Contract](PUBLIC_TEST_CONTRACT.md): public-surface release-confidence matrix and default evidence contract.
- [Testing Workflow](TESTING_WORKFLOW.md): focused contributor lanes for turning bug reports into regressions.
- [Status](STATUS.md): current maturity snapshot.
- [Release Notes](RELEASE_NOTES.md): user-facing release history.
- [Known Risk Register](KNOWN_RISK_REGISTER.md): tracked risks affecting current builds.

## Migration Guides

- [Arlen for X Index](ARLEN_FOR_X_INDEX.md): migration playbooks from other frameworks.
- [Arlen for Rails](ARLEN_FOR_RAILS.md)
- [Arlen for Django](ARLEN_FOR_DJANGO.md)
- [Arlen for Laravel](ARLEN_FOR_LARAVEL.md)
- [Arlen for FastAPI](ARLEN_FOR_FASTAPI.md)
- [Arlen for Express/NestJS](ARLEN_FOR_EXPRESS_NESTJS.md)
- [Arlen for Mojolicious](ARLEN_FOR_MOJOLICIOUS.md)
- [GSWeb Migration Guide](MIGRATION_GSWEB.md)

## Examples

- [Tech Demo](../examples/tech_demo/README.md): larger end-to-end example with Arlen UI/runtime features.
- [Basic App Smoke Guide](../examples/basic_app/README.md): smallest app-owned smoke path.
- [API-First Reference App](../examples/api_reference/README.md): JSON/OpenAPI-heavy reference surface.
- [Auth Primitives Example](../examples/auth_primitives/README.md): low-level auth primitive composition.
- [Auth + Admin Demo](../examples/auth_admin_demo/README.md): modules, auth, and admin composition.
- [Auth UI Modes](../examples/auth_ui_modes/README.md): `headless`, `module-ui`, and `generated-app-ui` side by side.
- [Multi-Module Demo](../examples/phase16_modules_demo/README.md): broader multi-module app surface (`admin-ui` + `search` + `ops`).
- [Search Module Playbook](../examples/search_module_playbook/README.md): scaffold-first path for app-owned search resources and engine swaps.
- [ArlenData Standalone Example](../examples/arlen_data/README.md): consuming the data layer outside Arlen.
- [Dataverse Reference](../examples/dataverse_reference/README.md): app-level Dataverse config, controller helpers, and codegen flow.
- [Arlen ORM Reference](../examples/arlen_orm_reference/README.md): optional SQL and Dataverse ORM reference surface.
- [React/TypeScript Reference](../examples/phase28_react_reference/README.md): descriptor-first React/TypeScript workspace showing generated validators, query contracts, module/resource metadata, and optional React helpers.
- [Reference Server (TypeScript Integration)](../examples/phase28_reference/README.md): live backend used by the generated TypeScript integration and React reference lanes.
- [GSWeb Migration Sample](../examples/gsweb_migration/README.md): migration-path example from GSWeb.

## Contributing and Internal Material

- [Documentation Policy](DOCUMENTATION_POLICY.md): docs standards, review checklist, and the internal/user-facing split.
- [CI Alignment](CI_ALIGNMENT.md): required CI shape and merge-gate guidance.
- [Comparative Benchmarking](COMPARATIVE_BENCHMARKING.md): benchmarking source-of-truth split.
- [Internal docs (`docs/internal/`)](internal/): engineering material — phase roadmaps, session handoffs, dated reconciliation notes, audits, and benchmark/operational handoffs. Not part of the user-facing surface.
