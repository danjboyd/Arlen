# Arlen

Arlen is a GNUstep-native Objective-C web framework with an MVC runtime, EOC templates (`.html.eoc`), and a developer server (`boomhauer`).

Arlen is designed to solve the same class of problems as frameworks like
Mojolicious while staying idiomatic to Objective-C/GNUstep conventions. The
project is still young, but the shipped surface is already broad: HTML-first
and JSON-first app paths, OpenAPI output, first-party auth/admin/jobs/storage
modules, WebSocket/SSE support, a PostgreSQL-first data layer, optional MSSQL,
a runtime-inactive Dataverse Web API integration surface, and a managed
production runtime (`propane`).

## Start Here

If you are new to Arlen, start with:

- `docs/FIRST_APP_GUIDE.md`
- `docs/GETTING_STARTED.md`
- `docs/GETTING_STARTED_TRACKS.md`
- `docs/APP_AUTHORING_GUIDE.md`
- `docs/LITE_MODE_GUIDE.md`
- `docs/README.md`

## Quick Start

```bash
source tools/source_gnustep_env.sh
./bin/arlen doctor
make all

mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Then open `http://127.0.0.1:3000/`.

If you already use a managed GNUstep toolchain, you can source its env script
first instead. The Arlen helper resolves `GNUSTEP_SH`, `GNUSTEP_MAKEFILES`,
`gnustep-config`, and finally `/usr/GNUstep`.

The default full scaffold gives you:

- `src/main.m`
- `src/Controllers/HomeController.{h,m}`
- `templates/layouts/main.html.eoc`
- `templates/index.html.eoc`
- `config/app.plist`

## Why Arlen

Arlen is for teams that want a batteries-included web framework in
Objective-C/GNUstep instead of a thin HTTP layer plus a long list of unrelated
libraries. The goal is to let you scaffold a real app, serve HTML or JSON, add
auth and operational surfaces, work against a serious data layer, and ship with
one coherent toolchain.

## Good Fit If

- you want to stay native to Objective-C and GNUstep for web work
- you want one framework for server-rendered HTML, JSON APIs, or mixed apps
- you want built-in modules for auth, admin, jobs, notifications, storage, ops, and search
- you want first-party tooling for OpenAPI, migrations, schema/SQL codegen, and production runtime management
- you prefer explicit, deterministic behavior over heavy convention or hidden magic

## Probably Not A Fit If

- you need a large third-party ecosystem today
- you need untrusted template execution or sandboxed template code; EOC templates are trusted code
- you want a non-GNUstep stack or a generic GCC-oriented GNUstep setup
- you want the smallest possible microframework and plan to assemble everything yourself

## What Ships Today

- `HTML-first and JSON-first paths`: EOC templates, layouts, partials, forms, controller rendering helpers, and API endpoints in the same app.
- `API tooling`: OpenAPI generation, interactive docs, and JSON-first scaffolds.
- `Auth and security`: sessions, CSRF, rate limiting, MFA, recovery codes, passkeys/WebAuthn, and OIDC/provider login.
- `First-party modules`: `auth`, `admin-ui`, `jobs`, `notifications`, `storage`, `ops`, and `search`.
- `Realtime and live UI`: WebSocket and SSE support, live fragment responses, built-in `/arlen/live.js`, keyed collection helpers, live regions, and controller helpers for live updates/navigation.
- `Data layer`: PostgreSQL-first migrations, schema codegen, typed SQL helpers, optional MSSQL support, and a runtime-inactive Dataverse Web API client/query/codegen surface.
- `Runtime`: `boomhauer` for development and `propane` for production worker supervision, reloads, and cluster controls.
- `Diagnostics and verification`: `arlen doctor`, build diagnostics, focused regression lanes, and live-backed integration coverage.

## Features People Usually Do Not Expect Here

- interactive OpenAPI explorer and generated API docs
- passkey/WebAuthn MFA and OIDC login flows
- built-in admin, ops, storage, notifications, jobs, and search surfaces
- WebSocket/SSE support plus production runtime management with `propane`
- typed schema and SQL code generation rather than only raw SQL strings
- Dataverse metadata/codegen and OData helpers without forcing Dataverse through the SQL adapter seam

## Quick Evaluation Path

- `5 minutes`: run the quick start, then hit `/`, `/healthz`, and `/openapi`.
- `15 minutes`: add a second endpoint with `arlen generate endpoint Hello --route /hello --method GET --template` and see how the controller/template flow feels.
- `30 minutes`: try a first-party module such as `auth`, or open one of the example apps listed below.

## Example Apps

- [Basic App Smoke Guide](examples/basic_app/README.md): smallest app-owned smoke path.
- [API-First Reference App](examples/api_reference/README.md): JSON/OpenAPI-heavy reference surface.
- [Dataverse Reference](examples/dataverse_reference/README.md): app-level Dataverse config, controller helpers, and codegen flow.
- [Auth + Admin Demo](examples/auth_admin_demo/README.md): modules, auth, and admin composition.
- [Phase 16 Modules Demo](examples/phase16_modules_demo/README.md): broader multi-module app surface.
- [Search Module Playbook](examples/search_module_playbook/README.md): scaffold-first path for app-owned search resources and engine swaps.
- [Tech Demo](examples/tech_demo/README.md): larger end-to-end example with Arlen UI/runtime features, including `/tech-demo/live`.

## Status

For readers evaluating maturity: Arlen is young, but not minimal. The list
below is the detailed milestone ledger for the shipped surface summarized above.

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
- Phase 21: complete (`21A-21G` delivered on 2026-03-27 for in-process request harnesses, shared request/pipeline assertion helpers, explicit async DB ownership rules, template-suite decomposition, raw protocol corpus replay, generated-app matrix coverage, and repo-native focused confidence lanes. See `docs/PHASE21_ROADMAP.md`).
- Phase 22: complete (`22A-22G` delivered on 2026-03-30 for newcomer-first onboarding, docs/code parity hardening, app-author guides, module/lite-mode guidance, plugin/frontend guides, and docs quality closeout. See `docs/PHASE22_ROADMAP.md`).
- Phase 23: complete (`23A-23I` delivered on 2026-03-31 for the runtime-inactive Dataverse Web API client, OData query builder, CRUD/batch helpers, metadata normalization, typed Dataverse codegen, app/controller Dataverse helpers, focused regression suites, parity/characterization artifacts, repo-native confidence lanes, and docs/example closeout. See `docs/PHASE23_ROADMAP.md`).
- Phase 25: complete (`25A-25L` delivered on 2026-04-01). The shipped fragment-first live UI now includes `ALNLive`, `/arlen/live.js`, live request metadata, keyed collection helpers, lazy/poll/deferred regions, upload-progress-aware live forms, websocket-backed push updates, a Node-backed executable runtime harness behind `phase25-live-tests`, adversarial live regression fixtures, and the strengthened `phase25-confidence` artifact pack. Full diff-engine/live-component depth remains future work.
- Phase 27: complete (`27A-27L` landed on 2026-04-01; the `27E-27L` audit follow-up closed on 2026-04-02). The search module now ships safe public result shaping, typed/capability-normalized metadata, PostgreSQL FTS/trigram, authoritative first-party Meilisearch/OpenSearch adapters, streamed rebuilds, resource-scoped tenant/visibility semantics, and a fail-closed `phase27-confidence` gate. See `docs/PHASE27_ROADMAP.md`.

## Requirements and Setup Details

If you are evaluating Arlen rather than contributing to the framework itself,
the quick start above plus the example apps and docs index are usually enough
for a first pass. The rest of this section covers the more detailed local
toolchain and quality-gate workflow.

Prerequisites:
- clang-built GNUstep toolchain installed
- `tools-xctest` installed (provides `xctest`)

Optional contributor fast path:
- set `ARLEN_XCTEST=/path/to/patched/xctest` to use a filter-capable XCTest runner for focused reruns such as `make test-unit-filter TEST=RuntimeTests/testRenderAndIncludeNormalizeUnsuffixedTemplateReferences`
- if that runner comes from a local uninstalled `tools-xctest` checkout, also set `ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj`

Initialize GNUstep in your shell:

```bash
source tools/source_gnustep_env.sh
```

Run bootstrap diagnostics before building:

```bash
./bin/arlen doctor
```

CI note:
- Arlen CI expects a clang-built GNUstep toolchain, not a generic GCC-oriented distro stack.
- The workflow bootstrap entry point is `tools/ci/install_ci_dependencies.sh`.
- Current self-hosted runners use `ARLEN_CI_GNUSTEP_STRATEGY=preinstalled` with the clang-built GNUstep toolchain installed at `/usr/GNUstep`.
- Local contributor shells can use `tools/source_gnustep_env.sh`, which also
  supports managed toolchains that export `GNUSTEP_SH` or `GNUSTEP_MAKEFILES`.
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

Start with the [Docs Index](docs/README.md).

Best next reads for evaluation:

- [First App Guide](docs/FIRST_APP_GUIDE.md)
- [Getting Started](docs/GETTING_STARTED.md)
- [App Authoring Guide](docs/APP_AUTHORING_GUIDE.md)
- [Modules](docs/MODULES.md)
- [Auth Module](docs/AUTH_MODULE.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Toolchain Matrix](docs/TOOLCHAIN_MATRIX.md)
- [Arlen for X Migration Guides](docs/ARLEN_FOR_X_INDEX.md)
- [API Reference](docs/API_REFERENCE.md)

Generate browser-friendly HTML docs:

```bash
make docs-api
make docs-html
make docs-serve
```

Open `build/docs/index.html` in a browser.

For the broader guide set, examples, historical roadmap material, and specs,
use [docs/README.md](docs/README.md) and [docs/STATUS.md](docs/STATUS.md).

## Naming

- Development server: `boomhauer`
- Production manager: `propane`
- All `propane` settings are referred to as "propane accessories"

## License

Arlen is licensed under the GNU Lesser General Public License, version 2 or (at your option) any later version (LGPL-2.0-or-later), aligned with GNUstep Base library licensing.
