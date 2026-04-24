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

Before running repo-local build/test/doc commands, source
`/path/to/Arlen/tools/source_gnustep_env.sh` or source your active GNUstep
toolchain env directly for the Linux/GNUstep path. On macOS, use
`GETTING_STARTED_MACOS.md`.

## New Developers

- [First App Guide](FIRST_APP_GUIDE.md): shortest path to scaffold, run, and extend your first app.
- [Getting Started on macOS](GETTING_STARTED_MACOS.md): Apple-runtime bootstrap path for macOS without GNUstep.
- [Apple Platform Contract](APPLE_PLATFORM.md): current Apple-runtime support boundary on macOS, including the verified auth/runtime lane.
- [Getting Started](GETTING_STARTED.md): build Arlen, create an app, add a route, and choose the next guide.
- [Getting Started Tracks](GETTING_STARTED_TRACKS.md): quickstart, API-first, HTML-first, and data-layer entry paths.
- [App Authoring Guide](APP_AUTHORING_GUIDE.md): routes, controllers, middleware, and route metadata.
- [Configuration Reference](CONFIGURATION_REFERENCE.md): config keys app authors touch first.
- [Lite Mode Guide](LITE_MODE_GUIDE.md): when to choose lite mode and how to grow beyond it.
- [Toolchain Matrix](TOOLCHAIN_MATRIX.md): known-good onboarding/runtime baseline.
- [CLI Reference](CLI_REFERENCE.md): command reference for `arlen`, `boomhauer`, and helper scripts.

## App Authoring

- [Getting Started: API-First Track](GETTING_STARTED_API_FIRST.md): JSON APIs, schema/auth contracts, and OpenAPI.
- [Getting Started: HTML-First Track](GETTING_STARTED_HTML_FIRST.md): server-rendered EOC templates, layouts, and forms.
- [EOC Guide](EOC_GUIDE.md): comprehensive syntax and authoring guide for `.html.eoc` templates.
- [Live UI Guide](LIVE_UI.md): fragment-first live responses, `/arlen/live.js`, keyed collections, live regions, live forms/links, and realtime push updates.
- [Durable Event Streams](EVENT_STREAMS.md): durable append/replay, websocket/SSE/poll consumption, auth hooks, and the plain generated TypeScript stream client.
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
- [Search Module](SEARCH_MODULE.md): shaped public query contracts, PostgreSQL/Meilisearch/OpenSearch engines, reindex/incremental sync, and admin/ops integration.
- [Ecosystem Services](ECOSYSTEM_SERVICES.md): jobs/cache/i18n/mail/attachment adapter contracts.
- [Dataverse Integration](DATAVERSE.md): Dataverse Web API client, config shape, OData query usage, and typed codegen workflow.
- [ArlenData Reuse Guide](ARLEN_DATA.md): standalone data-layer packaging and PostgreSQL/MSSQL/Dataverse usage.
- [ArlenORM Guide](ARLEN_ORM.md): optional SQL and Dataverse ORM layers on ArlenData.
- [Arlen ORM Migration Contracts](ARLEN_ORM_MIGRATIONS.md): descriptor snapshots and schema/codegen drift checks.
- [Arlen ORM Backend Matrix](ARLEN_ORM_BACKEND_MATRIX.md): PostgreSQL, MSSQL, and Dataverse capability boundaries.
- [Arlen ORM Scorecard](ARLEN_ORM_SCORECARD.md): the narrow best-in-class claim Phase 26 can defend.

## Operations and Deployment

- [Deployment Guide](DEPLOYMENT.md): deployment model and production guidance.
- [Systemd Runbook](SYSTEMD_RUNBOOK.md): systemd unit template and incident collection steps.
- [Propane Manager](PROPANE.md): production process manager and propane accessories.
- [Release Process](RELEASE_PROCESS.md): semantic versioning, deprecations, and release checklist.
- [Testing Workflow](TESTING_WORKFLOW.md): focused contributor lanes for turning bug reports into regressions.
- [Route Policies](ROUTE_POLICIES.md): named access policies, proxy-aware source IP allowlisting, `/admin` policy wiring, diagnostics, and confidence checks.
- [Windows CLANG64 Preview](WINDOWS_CLANG64.md): current `main`-branch Windows bootstrap, packaged-release preview contract, and support statement.
- [Platform Runner Runbook](PLATFORM_RUNNERS.md): Phase 34K Apple/Windows runner provisioning, labels, validation commands, and deferred package-manager boundary.

## Reference

- [Password Hashing](PASSWORD_HASHING.md): Argon2id password hashing defaults and rehash workflow.
- [Realtime and Composition](REALTIME_COMPOSITION.md): websocket/SSE contracts, live fragment transport, pubsub hub, and app mounting.
- [Arlen for X Migration Guides](ARLEN_FOR_X_INDEX.md): migration playbooks from Rails, Django, Laravel, FastAPI, Express/NestJS, Mojolicious, and GSWeb.
- [SQL Builder Conformance Matrix](SQL_BUILDER_CONFORMANCE_MATRIX.md): phase-4 SQL snapshot matrix and regression map.

## Contributor and Historical Docs

- [Current Status](STATUS.md): latest checkpoint and verified milestone state.
- [CI Alignment](CI_ALIGNMENT.md): required CI shape, merge-gate guidance, and the rule that CI must stay current and green.
- [Phase 37 Roadmap](PHASE37_ROADMAP.md): planned public-release test confidence phase covering a public-surface test contract matrix, expanded EOC golden-render regressions, deterministic parser/protocol corpora, acceptance-site harnesses, battle-test sites for EOC/MVC/modules/data/live/deploy surfaces, and `phase37-confidence`.
- [Phase 36 Roadmap](PHASE36_ROADMAP.md): completed deploy operator-UX phase; `36A-36L` delivered `deploy list`, `deploy dryrun`, release inventories, named-target release reuse, initialized-target guards, deploy config samples, `deploy target sample`, bash/PowerShell completion generation, completion safety coverage, docs refresh, and `phase36-confidence`.
- [Phase 35 Roadmap](PHASE35_ROADMAP.md): completed route/middleware policy layer for named access policies, proxy-aware source IP allowlisting, `/admin` as the first consumer, and `phase35-confidence`; `35I-35M` add and close plist route definitions as a declarative registration surface over the existing router with route inspection source metadata.
- [Phase 34 Roadmap](PHASE34_ROADMAP.md): completed CI-robustness phase covering workflow honesty, merge-gate cleanup, docs-gate promotion, branch-protection/release-lane cleanup, and platform-runner standardization.
- [Phase 33 Roadmap](PHASE33_ROADMAP.md): completed durable event-stream seam phase; `33A-33L` delivered the store/broker/auth seam, replay-window and `resync_required` contract, websocket/SSE/HTTP integration, plain generated TypeScript consumer surface, confidence lane, and docs/module-boundary closeout.
- [Phase 32 Roadmap](PHASE32_ROADMAP.md): completed target-aware deployment phase plus host-bootstrap closeout; `32A-32V` now cover the shipped deploy contract, named targets, `deploy init`, SSH transport/activation, fresh GNUstep host readiness, and Debian-first generated host artifacts/docs.
- [Phase 30 Roadmap](PHASE30_ROADMAP.md): Apple-runtime roadmap on macOS; `30A-30S` are now delivered, including the compatibility-shim cleanup for warning-free Apple/GNUstep builds.
- [Session Handoff (2026-04-03)](SESSION_HANDOFF_2026-04-03.md): Phase 28 closeout checkpoint covering `28I-28L`, the live reference server, and the final verification set.
- [Session Handoff (2026-04-02)](SESSION_HANDOFF_2026-04-02.md): historical Phase 28 pause point after shipping `28E-28H` and the React reference workspace.
- [OwnerConnect Report Reconciliation (2026-04-02)](OWNERCONNECT_REPORT_RECONCILIATION_2026-04-02.md): upstream status note for the Dataverse polymorphic-lookup codegen bug reported from `OwnerConnect`.
- [OwnerConnect Report Reconciliation (2026-04-07)](OWNERCONNECT_REPORT_RECONCILIATION_2026-04-07.md): upstream closure note for the packaged `deploy doctor --base-url` release-helper bug and current deploy-gap assessment reported from `OwnerConnect`.
- [OwnerConnect Report Reconciliation (2026-04-17)](OWNERCONNECT_REPORT_RECONCILIATION_2026-04-17.md): upstream closure note for the SSH remote `bash -lc` transport bug reported from `OwnerConnect`.
- [Platform Report Reconciliation (2026-03-31)](PLATFORM_REPORT_RECONCILIATION_2026-03-31.md): upstream closure note for the managed-GNUstep bootstrap bug reported from `iep-platform`.
- [Session Handoff (2026-03-27)](SESSION_HANDOFF_2026-03-27.md): historical pause point before the Phase 22 closeout.
- [Documentation Policy](DOCUMENTATION_POLICY.md): docs standards and review checklist.
- [Phase 20 Roadmap](PHASE20_ROADMAP.md): completed data-layer depth pass.
- [Phase 21 Roadmap](PHASE21_ROADMAP.md): completed public-release test robustness pass.
- [Phase 22 Roadmap](PHASE22_ROADMAP.md): completed documentation cleanup pass for newcomer-first onboarding and docs quality closeout.
- [Phase 23 Roadmap](PHASE23_ROADMAP.md): completed Dataverse integration phase.
- [Phase 24 Roadmap](PHASE24_ROADMAP.md): imported Windows CLANG64 roadmap and current `main` reintegration order.
- [Phase 25 Roadmap](PHASE25_ROADMAP.md): completed live UI baseline plus stream/recovery/adversarial hardening through `25L`.
- [Phase 26 Roadmap](PHASE26_ROADMAP.md): completed optional ORM phase plus Dataverse ORM tail work.
- [Phase 27 Roadmap](PHASE27_ROADMAP.md): completed search best-in-class phase; `27A-27L` landed on 2026-04-01 and the audited `27E-27L` closeout landed on 2026-04-02 for authoritative Meilisearch/OpenSearch behavior, streamed rebuilds, policy-scoped search semantics, and fail-closed confidence artifacts.
- [Phase 28 Roadmap](PHASE28_ROADMAP.md): completed descriptor-first React/TypeScript ORM interop phase; `28A-28L` closed on 2026-04-03 for generated TypeScript models, validators, query/resource/module metadata, typed transport, optional React integrations, live verification lanes, and confidence/docs closeout on top of ArlenORM plus route/OpenAPI contracts.
- [Phase 29 Roadmap](PHASE29_ROADMAP.md): completed deploy product phase delivering first-class `arlen deploy` orchestration, release metadata normalization, reserved operability probes, deploy-focused diagnostics, and `phase29-confidence`.
- [Phase 31 Roadmap](PHASE31_ROADMAP.md): completed Windows release/deployment closeout after the main-based Phase 24 runtime reintegration; Phase 30 is intentionally unused.
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
- [Search Module Playbook](../examples/search_module_playbook/README.md)
- [GSWeb Migration Sample](../examples/gsweb_migration/README.md)
- [ArlenData Standalone Example](../examples/arlen_data/README.md)
- [Dataverse Reference](../examples/dataverse_reference/README.md)
- [Arlen ORM Reference](../examples/arlen_orm_reference/README.md)
- [Phase 28 React Reference](../examples/phase28_react_reference/README.md)
- [Phase 28 Reference Server](../examples/phase28_reference/README.md)
